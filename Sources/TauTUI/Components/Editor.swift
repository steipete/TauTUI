import Foundation

public struct TextEditorConfig {
    public init() {}
}

public struct EditorTheme: Sendable {
    public var borderColor: AnsiStyling.Style
    public var selectList: SelectListTheme

    public init(borderColor: @escaping AnsiStyling.Style, selectList: SelectListTheme) {
        self.borderColor = borderColor
        self.selectList = selectList
    }

    public static let `default` = EditorTheme(
        borderColor: { "\u{001B}[90m\($0)\u{001B}[0m" },
        selectList: .default)
}

public final class Editor: Component {
    // Pure, Sendable buffer keeps mutations testable and UI-free.
    private var buffer = EditorBuffer()
    private var config = TextEditorConfig()

    // Autocomplete is optional and pluggable (slash commands + file completion).
    private var autocompleteProvider: AutocompleteProvider?
    private var autocompleteList: SelectList?
    private var isAutocompleting = false
    private var autocompletePrefix = ""

    // Large pastes are stored and replaced by markers until submit, mirroring pi-tui.
    private var pastes: [Int: String] = [:]
    private var pasteCounter = 0

    public var disableSubmit = false
    public var onSubmit: ((String) -> Void)?
    public var onChange: ((String) -> Void)?

    public var theme: EditorTheme

    public init(config: TextEditorConfig = TextEditorConfig(), theme: EditorTheme = .default) {
        self.config = config
        self.theme = theme
    }

    public func configure(_ config: TextEditorConfig) {
        self.config = config
    }

    public func setAutocompleteProvider(_ provider: AutocompleteProvider) {
        self.autocompleteProvider = provider
    }

    public func render(width: Int) -> [String] {
        let horizontal = self.theme.borderColor(String(repeating: "─", count: width))
        var result: [String] = [horizontal]
        let layoutLines = self.layout(width: width)
        result.append(contentsOf: layoutLines)
        result.append(horizontal)
        if self.isAutocompleting, let list = autocompleteList {
            result.append(contentsOf: list.render(width: width))
        }
        return result
    }

    public func handle(input: TerminalInput) {
        switch input {
        case let .paste(text):
            self.handlePaste(text)
        case let .key(key, modifiers):
            self.handleKey(key, modifiers: modifiers)
        case .raw:
            break
        case .terminalCellSize:
            break
        }
    }

    public func setText(_ text: String) {
        self.buffer.setText(text)
        self.onChange?(self.getText())
    }

    public func getText() -> String {
        self.buffer.text
    }

    private func layout(width: Int) -> [String] {
        var lines: [String] = []
        for (index, line) in self.buffer.lines.enumerated() {
            if line.count <= width {
                lines.append(self.renderLine(line: line, cursorLine: index))
            } else {
                var position = 0
                while position < line.count {
                    let end = min(line.count, position + width)
                    let chunkStart = line.index(line.startIndex, offsetBy: position)
                    let chunkEnd = line.index(line.startIndex, offsetBy: end)
                    let chunk = String(line[chunkStart..<chunkEnd])
                    lines.append(self.renderLine(line: chunk, cursorLine: index, offset: position))
                    position += width
                }
            }
        }
        if lines.isEmpty {
            lines.append(self.renderLine(line: "", cursorLine: 0))
        }
        return lines
    }

    private func renderLine(line: String, cursorLine: Int, offset: Int = 0) -> String {
        if cursorLine == self.buffer.cursorLine,
           self.buffer.cursorCol >= offset,
           self.buffer.cursorCol <= offset + line.count
        {
            let relative = self.buffer.cursorCol - offset
            let idx = line.index(line.startIndex, offsetBy: min(max(relative, 0), line.count))
            var rendered = line
            if relative < line.count {
                rendered.replaceSubrange(idx...idx, with: "\u{001B}[7m\(line[idx])\u{001B}[0m")
            } else {
                rendered.append("\u{001B}[7m \u{001B}[0m")
            }
            return rendered
        }
        return line
    }

    // swiftlint:disable cyclomatic_complexity
    private func handleKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        if self.isAutocompleting {
            switch key {
            case .arrowUp, .arrowDown:
                self.autocompleteList?.handle(input: .key(key, modifiers: modifiers))
                return
            case .enter, .tab:
                self.applySelectedAutocompleteItem()
                return
            case .escape:
                self.cancelAutocomplete()
                return
            default:
                break
            }
        }
        switch key {
        case .enter:
            if modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.meta) {
                self.insertNewLine()
            } else if self.disableSubmit {
                return
            } else {
                self.submit()
            }
        case .tab:
            self.handleTabCompletion()
        case .escape:
            self.cancelAutocomplete()
        case .backspace:
            if modifiers.contains(.option) {
                self.deleteWordBackwards()
            } else {
                self.backspace()
            }
        case .delete:
            if modifiers.contains(.option) {
                self.deleteWordForward()
            } else {
                self.deleteForward()
            }
        case .arrowUp:
            self.moveCursor(lineDelta: -1, columnDelta: 0)
        case .arrowDown:
            self.moveCursor(lineDelta: 1, columnDelta: 0)
        case .arrowLeft:
            if modifiers.contains(.option) || modifiers.contains(.control) {
                self.moveByWord(-1)
            } else {
                self.moveCursor(lineDelta: 0, columnDelta: -1)
            }
        case .arrowRight:
            if modifiers.contains(.option) || modifiers.contains(.control) {
                self.moveByWord(1)
            } else {
                self.moveCursor(lineDelta: 0, columnDelta: 1)
            }
        case .home:
            self.buffer = self.withMutatingBuffer { buf in buf.moveToLineStart() }
        case .end:
            self.buffer = self.withMutatingBuffer { buf in buf.moveToLineEnd() }
        case let .character(char):
            if modifiers.contains(.control) {
                switch char.lowercased() {
                case "u":
                    self.deleteToStartOfLine()
                case "k":
                    self.deleteToEndOfLine()
                case "w":
                    self.deleteWordBackwards()
                case "a":
                    self.buffer = self.withMutatingBuffer { buf in buf.moveToLineStart() }
                case "e":
                    self.buffer = self.withMutatingBuffer { buf in buf.moveToLineEnd() }
                default:
                    self.insertCharacter(String(char))
                }
            } else {
                self.insertCharacter(String(char))
            }
        default:
            break
        }
    }

    // swiftlint:enable cyclomatic_complexity

    private func insertCharacter(_ character: String) {
        self.buffer = self.withMutatingBuffer { buf in buf.insertCharacter(character) }
        self.onChange?(self.getText())
        if !self.isAutocompleting {
            self.triggerAutocomplete(explicit: false)
        } else {
            self.updateAutocomplete()
        }
    }

    private func insertNewLine() {
        self.buffer = self.withMutatingBuffer { buf in buf.insertNewLine() }
        self.onChange?(self.getText())
    }

    private func backspace() {
        self.buffer = self.withMutatingBuffer { buf in buf.backspace() }
        self.onChange?(self.getText())
    }

    private func deleteForward() {
        self.buffer = self.withMutatingBuffer { buf in buf.deleteForward() }
        self.onChange?(self.getText())
    }

    private func deleteWordForward() {
        self.buffer = self.withMutatingBuffer { buf in
            buf.deleteWordForward(isBoundary: self.isBoundary)
        }
        self.onChange?(self.getText())
    }

    private func moveCursor(lineDelta: Int, columnDelta: Int) {
        self.buffer = self.withMutatingBuffer { buf in buf.moveCursor(lineDelta: lineDelta, columnDelta: columnDelta) }
    }

    private func submit() {
        var text = self.getText().trimmingCharacters(in: .whitespacesAndNewlines)
        for (id, paste) in self.pastes {
            let pattern = "\\[paste #\(id)(?: [^\\]]+)?\\]"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: text.utf16.count)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: paste)
            }
        }
        self.buffer = EditorBuffer()
        self.pastes.removeAll()
        self.pasteCounter = 0
        self.onChange?("")
        self.onSubmit?(text)
    }

    private func deleteToStartOfLine() {
        self.buffer = self.withMutatingBuffer { buf in buf.deleteToStartOfLine() }
        self.onChange?(self.getText())
    }

    private func deleteToEndOfLine() {
        self.buffer = self.withMutatingBuffer { buf in buf.deleteToEndOfLine() }
        self.onChange?(self.getText())
    }

    private func deleteWordBackwards() {
        self.buffer = self.withMutatingBuffer { buf in
            buf.deleteWordBackwards(isBoundary: self.isBoundary)
        }
        self.onChange?(self.getText())
    }

    private func moveByWord(_ direction: Int) {
        self.buffer = self.withMutatingBuffer { buf in buf.moveByWord(direction, isBoundary: self.isBoundary) }
    }

    private func isPunctuation(_ ch: Character) -> Bool {
        let punctuation: Set<Character> = Set("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")
        return punctuation.contains(ch)
    }

    private func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    private func isBoundary(_ ch: Character) -> Bool {
        ch.isWhitespace || self.isPunctuation(ch)
    }

    private func handlePaste(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let spacesExpanded = normalized.replacingOccurrences(of: "\t", with: "    ")
        var sanitized = spacesExpanded.reduce(into: "") { partial, char in
            if char == "\n" {
                partial.append(char)
                return
            }
            // Keep any printable Unicode character; drop control chars (< 0x20).
            let hasControl = char.unicodeScalars.contains { $0.value < 32 }
            if !hasControl {
                partial.append(char)
            }
        }

        // If pasting a file path and the character before the cursor is a word character, prepend a space.
        if let first = sanitized.first,
           first == "/" || first == "~" || first == "."
        {
            let currentLine = self.buffer.lines[self.buffer.cursorLine]
            if self.buffer.cursorCol > 0, self.buffer.cursorCol <= currentLine.count {
                let beforeIndex = currentLine.index(currentLine.startIndex, offsetBy: self.buffer.cursorCol - 1)
                let charBeforeCursor = currentLine[beforeIndex]
                if self.isWordCharacter(charBeforeCursor) {
                    sanitized = " " + sanitized
                }
            }
        }

        let lines = sanitized.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 10 || sanitized.count > 1000 {
            self.pasteCounter += 1
            self.pastes[self.pasteCounter] = sanitized
            let marker = if lines.count > 10 {
                "[paste #\(self.pasteCounter) +\(lines.count) lines]"
            } else {
                "[paste #\(self.pasteCounter) \(sanitized.count) chars]"
            }
            for char in marker {
                self.insertCharacter(String(char))
            }
            return
        }
        if lines.count == 1 {
            for char in sanitized {
                self.insertCharacter(String(char))
            }
            return
        }
        let currentLine = self.buffer.lines[self.buffer.cursorLine]
        let before = currentLine.prefix(self.buffer.cursorCol)
        let after = currentLine.suffix(currentLine.count - self.buffer.cursorCol)
        self.buffer = self.withMutatingBuffer { buf in
            buf.lines[buf.cursorLine] = String(before) + String(lines.first ?? "")
        }
        var insertionIndex = self.buffer.cursorLine + 1
        for middle in lines.dropFirst().dropLast() {
            self.buffer = self.withMutatingBuffer { buf in buf.lines.insert(String(middle), at: insertionIndex) }
            insertionIndex += 1
        }
        if let last = lines.last {
            self.buffer = self.withMutatingBuffer { buf in
                buf.lines.insert(String(last) + String(after), at: insertionIndex)
                buf.cursorLine = insertionIndex
                buf.cursorCol = String(last).count
            }
        }
        self.onChange?(self.getText())
    }

    private func triggerAutocomplete(explicit: Bool) {
        guard let provider = autocompleteProvider else { return }
        if explicit, !provider.shouldTriggerFileCompletion(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        {
            return
        }
        let suggestion = provider.getSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        if let suggestion {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.cancelAutocomplete()
        }
    }

    private func updateAutocomplete() {
        guard let provider = autocompleteProvider, isAutocompleting else { return }
        let suggestion = provider.getSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        if let suggestion {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.cancelAutocomplete()
        }
    }

    private func cancelAutocomplete() {
        self.isAutocompleting = false
        self.autocompleteList = nil
        self.autocompletePrefix = ""
    }

    private func applySelectedAutocompleteItem() {
        guard let provider = autocompleteProvider,
              let list = autocompleteList,
              let selected = list.selectedItem()
        else {
            self.cancelAutocomplete()
            return
        }
        let autocompleteItem = AutocompleteItem(
            value: selected.value,
            label: selected.label,
            description: selected.description)
        let result = provider.applyCompletion(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol,
            item: autocompleteItem,
            prefix: self.autocompletePrefix)
        self.buffer = self.withMutatingBuffer { buf in
            buf.lines = result.lines
            buf.cursorLine = result.cursorLine
            buf.cursorCol = result.cursorCol
        }
        self.cancelAutocomplete()
        self.onChange?(self.getText())
    }

    private func handleTabCompletion() {
        guard self.autocompleteProvider != nil else { return }
        let currentLine = self.buffer.lines[self.buffer.cursorLine]
        let cursorIndex = currentLine.index(
            currentLine.startIndex,
            offsetBy: min(self.buffer.cursorCol, currentLine.count))
        let beforeCursor = String(currentLine[..<cursorIndex])
        if beforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            self.handleSlashCommandCompletion()
        } else {
            self.forceFileAutocomplete()
        }
    }

    private func handleSlashCommandCompletion() {
        self.triggerAutocomplete(explicit: true)
    }

    private func forceFileAutocomplete() {
        guard let provider = autocompleteProvider else { return }
        if let suggestion = provider.forceFileSuggestions(
            lines: self.buffer.lines,
            cursorLine: self.buffer.cursorLine,
            cursorCol: self.buffer.cursorCol)
        {
            self.presentAutocomplete(provider: provider, suggestion: suggestion)
        } else {
            self.triggerAutocomplete(explicit: true)
        }
    }

    private func presentAutocomplete(provider: AutocompleteProvider, suggestion: AutocompleteSuggestion) {
        self.autocompletePrefix = suggestion.prefix
        self.autocompleteList = SelectList(
            items: suggestion.items
                .map { SelectItem(value: $0.value, label: $0.label, description: $0.description) },
            maxVisible: 5,
            theme: self.theme.selectList)
        self.autocompleteList?.onSelect = { [weak self] selected in
            guard let self else { return }
            let result = provider.applyCompletion(
                lines: self.buffer.lines,
                cursorLine: self.buffer.cursorLine,
                cursorCol: self.buffer.cursorCol,
                item: AutocompleteItem(
                    value: selected.value,
                    label: selected.label,
                    description: selected.description),
                prefix: self.autocompletePrefix)
            self.buffer = self.withMutatingBuffer { buf in
                buf.lines = result.lines
                buf.cursorLine = result.cursorLine
                buf.cursorCol = result.cursorCol
            }
            self.cancelAutocomplete()
            self.onChange?(self.getText())
        }
        self.autocompleteList?.onCancel = { [weak self] in self?.cancelAutocomplete() }
        self.isAutocompleting = true
    }

    /// Helper to mutate the value-type buffer while keeping `Editor` reference semantics.
    private func withMutatingBuffer(_ mutate: (inout EditorBuffer) -> Void) -> EditorBuffer {
        var copy = self.buffer
        mutate(&copy)
        return copy
    }

    public func invalidate() {
        // Stateless renderer; nothing cached.
    }

    @MainActor public func apply(theme: ThemePalette) {
        self.theme = theme.editor
        // If an autocomplete list is already visible, refresh its theme.
        self.autocompleteList?.theme = theme.selectList
    }
}
