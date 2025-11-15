import Foundation

public struct TextEditorConfig {
    public init() {}
}

public final class Editor: Component {
    private struct EditorState {
        var lines: [String] = [""]
        var cursorLine: Int = 0
        var cursorCol: Int = 0
    }

    private var state = EditorState()
    private var config = TextEditorConfig()

    // Autocomplete is optional and pluggable (slash commands + file completion).
    private var autocompleteProvider: AutocompleteProvider?
    private var autocompleteList: SelectList?
    private var isAutocompleting = false
    private var autocompletePrefix = ""

    // Large pastes are stored and replaced by markers until submit, mirroring pi-tui.
    private var pastes: [Int: String] = [:]
    private var pasteCounter = 0
    private var pasteBuffer = ""
    private var isInPaste = false

    public var disableSubmit = false
    public var onSubmit: ((String) -> Void)?
    public var onChange: ((String) -> Void)?

    public init(config: TextEditorConfig = TextEditorConfig()) {
        self.config = config
    }

    public func configure(_ config: TextEditorConfig) {
        self.config = config
    }

    public func setAutocompleteProvider(_ provider: AutocompleteProvider) {
        self.autocompleteProvider = provider
    }

    public func render(width: Int) -> [String] {
        let horizontal = String(repeating: "─", count: width)
        var result: [String] = [horizontal]
        let layoutLines = layout(width: width)
        result.append(contentsOf: layoutLines)
        result.append(horizontal)
        if isAutocompleting, let list = autocompleteList {
            result.append(contentsOf: list.render(width: width))
        }
        return result
    }

    public func handle(input: TerminalInput) {
        switch input {
        case .raw(let data):
            handleRawInput(data)          // raw captures escape sequences and bracketed paste markers
        case .paste(let text):
            handlePaste(text)            // direct paste from TerminalInput bypassing bracket markers
        case .key(let key, let modifiers):
            handleKey(key, modifiers: modifiers)
        }
    }

    public func setText(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        state.lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if state.lines.isEmpty { state.lines = [""] }
        state.cursorLine = state.lines.count - 1
        state.cursorCol = state.lines[state.cursorLine].count
        onChange?(getText())
    }

    public func getText() -> String {
        state.lines.joined(separator: "\n")
    }

    private func layout(width: Int) -> [String] {
        var lines: [String] = []
        for (index, line) in state.lines.enumerated() {
            if line.count <= width {
                lines.append(renderLine(line: line, cursorLine: index))
            } else {
                var position = 0
                while position < line.count {
                    let end = min(line.count, position + width)
                    let chunkStart = line.index(line.startIndex, offsetBy: position)
                    let chunkEnd = line.index(line.startIndex, offsetBy: end)
                    let chunk = String(line[chunkStart..<chunkEnd])
                    lines.append(renderLine(line: chunk, cursorLine: index, offset: position))
                    position += width
                }
            }
        }
        if lines.isEmpty {
            lines.append(renderLine(line: "", cursorLine: 0))
        }
        return lines
    }

    private func renderLine(line: String, cursorLine: Int, offset: Int = 0) -> String {
        if cursorLine == state.cursorLine,
           state.cursorCol >= offset,
           state.cursorCol <= offset + line.count {
            let relative = state.cursorCol - offset
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

    private func handleRawInput(_ data: String) {
        var buffer = data
        if buffer.contains("\u{001B}[200~") {
            isInPaste = true
            buffer = buffer.replacingOccurrences(of: "\u{001B}[200~", with: "")
        }
        if isInPaste {
            pasteBuffer += buffer
            if pasteBuffer.contains("\u{001B}[201~") {
                let components = pasteBuffer.components(separatedBy: "\u{001B}[201~")
                let pasteContent = components.first ?? ""
                handlePaste(pasteContent)
                pasteBuffer = components.dropFirst().joined(separator: "")
                isInPaste = false
                if !pasteBuffer.isEmpty {
                    handleRawInput(pasteBuffer)
                    pasteBuffer = ""
                }
            }
            return
        }
        for scalar in buffer {
            handleScalar(scalar)
        }
    }

    private func handleScalar(_ scalar: Character) {
        switch scalar {
        case "\u{0003}": // Ctrl+C
            return
        case "\r":
            if disableSubmit { return }
            submit()
        case "\n":
            insertNewLine()
        default:
            insertCharacter(String(scalar))
        }
    }

    private func handleKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        if isAutocompleting {
            switch key {
            case .arrowUp, .arrowDown:
                autocompleteList?.handle(input: .key(key, modifiers: modifiers))
                return
            case .enter, .tab:
                applySelectedAutocompleteItem()
                return
            case .escape:
                cancelAutocomplete()
                return
            default:
                break
            }
        }
        switch key {
        case .enter:
            if modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.meta) {
                insertNewLine()
            } else if disableSubmit {
                return
            } else {
                submit()
            }
        case .tab:
            triggerAutocomplete(explicit: true)
        case .escape:
            cancelAutocomplete()
        case .backspace:
            if modifiers.contains(.option) {
                deleteWordBackwards()
            } else {
                backspace()
            }
        case .delete:
            deleteForward()
        case .arrowUp:
            moveCursor(lineDelta: -1, columnDelta: 0)
        case .arrowDown:
            moveCursor(lineDelta: 1, columnDelta: 0)
        case .arrowLeft:
            if modifiers.contains(.option) {
                moveByWord(-1)
            } else {
                moveCursor(lineDelta: 0, columnDelta: -1)
            }
        case .arrowRight:
            if modifiers.contains(.option) {
                moveByWord(1)
            } else {
                moveCursor(lineDelta: 0, columnDelta: 1)
            }
        case .home:
            state.cursorCol = 0
        case .end:
            state.cursorCol = state.lines[state.cursorLine].count
        case .character(let char):
            if modifiers.contains(.control) {
                switch char.lowercased() {
                case "u":
                    deleteToStartOfLine()
                case "k":
                    deleteToEndOfLine()
                case "w":
                    deleteWordBackwards()
                default:
                    insertCharacter(String(char))
                }
            } else {
                insertCharacter(String(char))
            }
        default:
            break
        }
    }

    private func insertCharacter(_ character: String) {
        var line = state.lines[state.cursorLine]
        let index = line.index(line.startIndex, offsetBy: state.cursorCol)
        line.insert(contentsOf: character, at: index)
        state.lines[state.cursorLine] = line
        state.cursorCol += character.count
        onChange?(getText())
        if !isAutocompleting {
            triggerAutocomplete(explicit: false)
        } else {
            updateAutocomplete()
        }
    }

    private func insertNewLine() {
        let line = state.lines[state.cursorLine]
        let index = line.index(line.startIndex, offsetBy: state.cursorCol)
        let before = String(line[..<index])
        let after = String(line[index...])
        state.lines[state.cursorLine] = before
        state.lines.insert(after, at: state.cursorLine + 1)
        state.cursorLine += 1
        state.cursorCol = 0
        onChange?(getText())
    }

    private func backspace() {
        if state.cursorCol > 0 {
            var line = state.lines[state.cursorLine]
            let index = line.index(line.startIndex, offsetBy: state.cursorCol - 1)
            line.remove(at: index)
            state.lines[state.cursorLine] = line
            state.cursorCol -= 1
        } else if state.cursorLine > 0 {
            let current = state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            state.cursorCol = state.lines[state.cursorLine].count
            state.lines[state.cursorLine] += current
        }
        onChange?(getText())
    }

    private func deleteForward() {
        var line = state.lines[state.cursorLine]
        guard state.cursorCol < line.count else {
            if state.cursorLine < state.lines.count - 1 {
                line += state.lines.remove(at: state.cursorLine + 1)
                state.lines[state.cursorLine] = line
            }
            return
        }
        let index = line.index(line.startIndex, offsetBy: state.cursorCol)
        line.remove(at: index)
        state.lines[state.cursorLine] = line
        onChange?(getText())
    }

    private func moveCursor(lineDelta: Int, columnDelta: Int) {
        let newLine = min(max(state.cursorLine + lineDelta, 0), state.lines.count - 1)
        let targetLine = state.lines[newLine]
        let newCol = min(max(state.cursorCol + columnDelta, 0), targetLine.count)
        state.cursorLine = newLine
        state.cursorCol = newCol
    }

    private func submit() {
        var text = getText().trimmingCharacters(in: .whitespacesAndNewlines)
        for (id, paste) in pastes {
            let pattern = "\\[paste #\(id)(?: [^\\]]+)?\\]"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: text.utf16.count)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: paste)
            }
        }
        state = EditorState()
        pastes.removeAll()
        pasteCounter = 0
        onChange?("")
        onSubmit?(text)
    }

    private func deleteToStartOfLine() {
        let line = state.lines[state.cursorLine]
        let index = line.index(line.startIndex, offsetBy: state.cursorCol)
        state.lines[state.cursorLine] = String(line[index...])
        state.cursorCol = 0
        onChange?(getText())
    }

    private func deleteToEndOfLine() {
        let line = state.lines[state.cursorLine]
        let index = line.index(line.startIndex, offsetBy: state.cursorCol)
        state.lines[state.cursorLine] = String(line[..<index])
        onChange?(getText())
    }

    private func deleteWordBackwards() {
        var line = state.lines[state.cursorLine]
        guard !line.isEmpty, state.cursorCol > 0 else {
            backspace()
            return
        }
        var deleteFrom = state.cursorCol
        while deleteFrom > 0 {
            let prevIndex = line.index(line.startIndex, offsetBy: deleteFrom - 1)
            let ch = line[prevIndex]
            if ch.isWhitespace || isPunctuation(ch) {
                break
            }
            deleteFrom -= 1
        }
        let start = line.index(line.startIndex, offsetBy: deleteFrom)
        let end = line.index(line.startIndex, offsetBy: state.cursorCol)
        line.removeSubrange(start..<end)
        state.lines[state.cursorLine] = line
        state.cursorCol = deleteFrom
        onChange?(getText())
    }

    private func moveByWord(_ direction: Int) {
        guard direction != 0 else { return }
        let line = state.lines[state.cursorLine]
        var idx = state.cursorCol
        func isBoundary(_ ch: Character) -> Bool { ch.isWhitespace || isPunctuation(ch) }
        if direction > 0 {
            while idx < line.count {
                let ch = line[line.index(line.startIndex, offsetBy: idx)]
                if isBoundary(ch) {
                    idx += 1
                } else { break }
            }
            while idx < line.count {
                let ch = line[line.index(line.startIndex, offsetBy: idx)]
                if isBoundary(ch) { break }
                idx += 1
            }
        } else {
            while idx > 0 {
                let ch = line[line.index(line.startIndex, offsetBy: idx - 1)]
                if isBoundary(ch) { idx -= 1 } else { break }
            }
            while idx > 0 {
                let ch = line[line.index(line.startIndex, offsetBy: idx - 1)]
                if isBoundary(ch) { break }
                idx -= 1
            }
        }
        state.cursorCol = max(0, min(line.count, idx))
    }

    private func isPunctuation(_ ch: Character) -> Bool {
        let punctuation: Set<Character> = Set("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")
        return punctuation.contains(ch)
    }

    private func handlePaste(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 10 || normalized.count > 1000 {
            pasteCounter += 1
            pastes[pasteCounter] = normalized
            let marker = lines.count > 10 ? "[paste #\(pasteCounter) +\(lines.count) lines]" : "[paste #\(pasteCounter) \(normalized.count) chars]"
            for char in marker {
                insertCharacter(String(char))
            }
            return
        }
        if lines.count == 1 {
            for char in normalized {
                insertCharacter(String(char))
            }
            return
        }
        let currentLine = state.lines[state.cursorLine]
        let before = currentLine.prefix(state.cursorCol)
        let after = currentLine.suffix(currentLine.count - state.cursorCol)
        state.lines[state.cursorLine] = String(before) + String(lines.first ?? "")
        var insertionIndex = state.cursorLine + 1
        for middle in lines.dropFirst().dropLast() {
            state.lines.insert(String(middle), at: insertionIndex)
            insertionIndex += 1
        }
        if let last = lines.last {
            state.lines.insert(String(last) + String(after), at: insertionIndex)
            state.cursorLine = insertionIndex
            state.cursorCol = String(last).count
        }
        onChange?(getText())
    }

    private func triggerAutocomplete(explicit: Bool) {
        guard let provider = autocompleteProvider else { return }
        let suggestion = provider.getSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol)
        if let suggestion {
            autocompletePrefix = suggestion.prefix
            autocompleteList = SelectList(items: suggestion.items.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) }, maxVisible: 5)
            autocompleteList?.onSelect = { [weak self] selected in
                guard let self else { return }
                let result = provider.applyCompletion(
                    lines: self.state.lines,
                    cursorLine: self.state.cursorLine,
                    cursorCol: self.state.cursorCol,
                    item: AutocompleteItem(value: selected.value, label: selected.label, description: selected.description),
                    prefix: suggestion.prefix
                )
                self.state.lines = result.lines
                self.state.cursorLine = result.cursorLine
                self.state.cursorCol = result.cursorCol
                self.cancelAutocomplete()
                self.onChange?(self.getText())
            }
            autocompleteList?.onCancel = { [weak self] in self?.cancelAutocomplete() }
            isAutocompleting = true
        } else {
            cancelAutocomplete()
        }
    }

    private func updateAutocomplete() {
        guard let provider = autocompleteProvider, isAutocompleting else { return }
        let suggestion = provider.getSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol)
        if let suggestion {
            autocompletePrefix = suggestion.prefix
            autocompleteList = SelectList(items: suggestion.items.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) }, maxVisible: 5)
        } else {
            cancelAutocomplete()
        }
    }

    private func cancelAutocomplete() {
        isAutocompleting = false
        autocompleteList = nil
        autocompletePrefix = ""
    }

    private func applySelectedAutocompleteItem() {
        guard let provider = autocompleteProvider,
              let list = autocompleteList,
              let selected = list.selectedItem() else {
            cancelAutocomplete()
            return
        }
        let autocompleteItem = AutocompleteItem(value: selected.value, label: selected.label, description: selected.description)
        let result = provider.applyCompletion(
            lines: state.lines,
            cursorLine: state.cursorLine,
            cursorCol: state.cursorCol,
            item: autocompleteItem,
            prefix: autocompletePrefix
        )
        state.lines = result.lines
        state.cursorLine = result.cursorLine
        state.cursorCol = result.cursorCol
        cancelAutocomplete()
        onChange?(getText())
    }
}
