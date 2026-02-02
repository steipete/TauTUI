import Foundation

public struct AutocompleteItem: Equatable {
    public let value: String
    public let label: String
    public let description: String?

    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

public protocol SlashCommand {
    var name: String { get }
    var description: String? { get }
    func argumentCompletions(prefix: String) -> [AutocompleteItem]
}

public struct AutocompleteSuggestion {
    public let items: [AutocompleteItem]
    public let prefix: String
}

public protocol AutocompleteProvider {
    func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int)

    func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?

    func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> Bool
}

extension AutocompleteProvider {
    public func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?
    {
        nil
    }

    public func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> Bool
    {
        true
    }
}

public final class CombinedAutocompleteProvider: AutocompleteProvider {
    private let commands: [SlashCommand]
    private let staticCommands: [AutocompleteItem]
    private let baseURL: URL
    private let fileManager: FileManager
    private let attachmentRegex = try? NSRegularExpression(pattern: "@[^\\s]*$", options: [])
    private let pathRegex = try? NSRegularExpression(
        pattern: "(?:^|[\\s\"'=])((?:~\\/|\\.{0,2}\\/?)(?:[^\\s\"'=]*\\/?)*[^\\s\"'=]*)$",
        options: [])

    // basePath is captured as URL once to avoid repeated path parsing per keystroke.
    public init(
        commands: [SlashCommand] = [],
        staticCommands: [AutocompleteItem] = [],
        basePath: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default)
    {
        self.commands = commands
        self.staticCommands = staticCommands
        self.baseURL = URL(fileURLWithPath: basePath)
        self.fileManager = fileManager
    }

    public func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        guard lines.indices.contains(cursorLine) else { return nil }
        let currentLine = lines[cursorLine]
        let prefixIndex = currentLine.index(currentLine.startIndex, offsetBy: min(cursorCol, currentLine.count))
        let textBeforeCursor = String(currentLine[..<prefixIndex])

        if textBeforeCursor.hasPrefix("/") {
            return self.slashCommandSuggestions(textBeforeCursor: textBeforeCursor)
        }

        if let context = extractPathPrefix(from: textBeforeCursor, force: false) {
            let items = self.fileSuggestions(for: context)
            if !items.isEmpty {
                return AutocompleteSuggestion(items: items, prefix: context.token)
            }
        }

        return nil
    }

    public func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int)
    {
        guard lines.indices.contains(cursorLine) else { return (lines, cursorLine, cursorCol) }
        var mutableLines = lines
        var currentLine = lines[cursorLine]
        let safePrefixCount = min(prefix.count, cursorCol)
        let start = currentLine.index(currentLine.startIndex, offsetBy: cursorCol - safePrefixCount)
        let end = currentLine.index(start, offsetBy: safePrefixCount)
        let replacement = self.completionString(for: prefix, item: item)
        currentLine.replaceSubrange(start..<end, with: replacement)
        mutableLines[cursorLine] = currentLine
        let newCursor = cursorCol - safePrefixCount + replacement.count
        return (mutableLines, cursorLine, max(0, newCursor))
    }

    public func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?
    {
        guard lines.indices.contains(cursorLine) else { return nil }
        let currentLine = lines[cursorLine]
        let prefixIndex = currentLine.index(currentLine.startIndex, offsetBy: min(cursorCol, currentLine.count))
        let textBeforeCursor = String(currentLine[..<prefixIndex])
        guard let context = self.extractPathPrefix(from: textBeforeCursor, force: true) else { return nil }
        let items = self.fileSuggestions(for: context)
        guard !items.isEmpty else { return nil }
        return AutocompleteSuggestion(items: items, prefix: context.token)
    }

    public func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> Bool
    {
        guard lines.indices.contains(cursorLine) else { return true }
        let currentLine = lines[cursorLine]
        let prefixIndex = currentLine.index(currentLine.startIndex, offsetBy: min(cursorCol, currentLine.count))
        let textBeforeCursor = String(currentLine[..<prefixIndex])
        if textBeforeCursor.hasPrefix("/"), !textBeforeCursor.contains(" ") {
            return false
        }
        return true
    }

    private func completionString(for prefix: String, item: AutocompleteItem) -> String {
        if prefix.hasPrefix("/"), !prefix.contains(" ") {
            return "/" + item.value + " "
        }
        if prefix.hasPrefix("@") {
            return item.value + " "
        }
        return item.value
    }

    private func completionCursorOffset(for prefix: String, item: AutocompleteItem) -> Int {
        let replacement = self.completionString(for: prefix, item: item)
        return replacement.count
    }

    private func slashCommandSuggestions(textBeforeCursor: String) -> AutocompleteSuggestion? {
        if let spaceIndex = textBeforeCursor.firstIndex(of: " ") {
            let commandName =
                String(textBeforeCursor[textBeforeCursor.index(after: textBeforeCursor.startIndex)..<spaceIndex])
            guard let command = commands.first(where: { $0.name == commandName }) else { return nil }
            let argumentText = String(textBeforeCursor[textBeforeCursor.index(after: spaceIndex)...])
            let items = command.argumentCompletions(prefix: argumentText)
            return items.isEmpty ? nil : AutocompleteSuggestion(items: items, prefix: argumentText)
        } else {
            let prefixText = String(textBeforeCursor.dropFirst())
            var items = self.commands
                .filter { $0.name.lowercased().hasPrefix(prefixText.lowercased()) }
                .map { AutocompleteItem(value: $0.name, label: $0.name, description: $0.description) }
            let inlineMatches = self.staticCommands.filter {
                $0.value.lowercased().hasPrefix(prefixText.lowercased())
            }
            items.append(contentsOf: inlineMatches)
            return items.isEmpty ? nil : AutocompleteSuggestion(items: items, prefix: textBeforeCursor)
        }
    }

    private struct PathContext {
        let token: String
        let isAttachment: Bool
        let forced: Bool
    }

    private func extractPathPrefix(from text: String, force: Bool) -> PathContext? {
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        if let attachmentRegex,
           let match = attachmentRegex.firstMatch(in: text, options: [], range: fullRange),
           let range = Range(match.range, in: text)
        {
            return PathContext(token: String(text[range]), isAttachment: true, forced: force)
        }

        if let pathRegex,
           let match = pathRegex.firstMatch(in: text, options: [], range: fullRange),
           let captureRange = Range(match.range(at: 1), in: text)
        {
            let token = String(text[captureRange])
            if token.isEmpty, !force {
                return nil
            }
            if token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") {
                return PathContext(token: token, isAttachment: false, forced: force)
            }
            if force {
                return PathContext(token: token, isAttachment: false, forced: force)
            }
            return nil
        }

        return force ? PathContext(token: "", isAttachment: false, forced: true) : nil
    }

    private func fileSuggestions(for context: PathContext) -> [AutocompleteItem] {
        let baseToken = context.isAttachment ? String(context.token.dropFirst()) : context.token
        let typedToken = baseToken
        let resolved = self.resolvePath(typedToken)
        let directoryURL: URL
        let searchPrefix: String

        if typedToken.isEmpty || typedToken.hasSuffix("/") {
            directoryURL = resolved
            searchPrefix = ""
        } else {
            directoryURL = resolved.deletingLastPathComponent()
            searchPrefix = resolved.lastPathComponent
        }

        guard self.fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
            var items: [AutocompleteItem] = []
            for url in contents {
                let name = url.lastPathComponent
                let shouldBypassPrefix = context.forced && searchPrefix.isEmpty
                if !shouldBypassPrefix, !name.lowercased().hasPrefix(searchPrefix.lowercased()) {
                    continue
                }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if context.isAttachment, !isDirectory, !FileAttachmentFilter.isAttachable(url: url) {
                    continue
                }
                let valuePath = self.buildCompletionPath(
                    typedToken: typedToken,
                    component: name,
                    isDirectory: isDirectory,
                    context: context)
                let label = name + (isDirectory ? "/" : "")
                let description = isDirectory ? "directory" : "file"
                items.append(AutocompleteItem(value: valuePath, label: label, description: description))
            }
            return items.sorted { lhs, rhs in
                switch (lhs.description == "directory", rhs.description == "directory") {
                case (true, false): true
                case (false, true): false
                default: lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
            }.prefix(10).map(\.self)
        } catch {
            return []
        }
    }

    private func resolvePath(_ typed: String) -> URL {
        if typed.hasPrefix("/") {
            return URL(fileURLWithPath: typed).standardizedFileURL
        }
        if typed.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let suffix = String(typed.dropFirst())
            return home.appendingPathComponent(suffix)
        }
        if typed.isEmpty {
            return self.baseURL
        }
        return self.baseURL.appendingPathComponent(typed)
    }

    private func buildCompletionPath(
        typedToken: String,
        component: String,
        isDirectory: Bool,
        context: PathContext) -> String
    {
        var base = typedToken
        if base.isEmpty || base.hasSuffix("/") {
            base += component
        } else {
            let parent = (base as NSString).deletingLastPathComponent
            base = (parent.isEmpty ? component : parent + "/" + component)
        }
        var completed = base + (isDirectory ? "/" : "")
        if context.isAttachment {
            completed = "@" + completed
        }
        return completed
    }
}
