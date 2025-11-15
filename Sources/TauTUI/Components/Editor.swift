import Foundation

public struct TextEditorConfig {
    public init() {}
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
        buffer.setText(text)
        onChange?(getText())
    }

    public func getText() -> String {
        buffer.text
    }

    private func layout(width: Int) -> [String] {
        var lines: [String] = []
        for (index, line) in buffer.lines.enumerated() {
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
        if cursorLine == buffer.cursorLine,
           buffer.cursorCol >= offset,
           buffer.cursorCol <= offset + line.count {
            let relative = buffer.cursorCol - offset
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
            if modifiers.contains(.option) {
                deleteWordForward()
            } else {
                deleteForward()
            }
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
            buffer = withMutatingBuffer { buf in buf.moveToLineStart() }
        case .end:
            buffer = withMutatingBuffer { buf in buf.moveToLineEnd() }
        case .character(let char):
            if modifiers.contains(.control) {
                switch char.lowercased() {
                case "u":
                    deleteToStartOfLine()
                case "k":
                    deleteToEndOfLine()
                case "w":
                    deleteWordBackwards()
                case "a":
                    buffer = withMutatingBuffer { buf in buf.moveToLineStart() }
                case "e":
                    buffer = withMutatingBuffer { buf in buf.moveToLineEnd() }
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
        buffer = withMutatingBuffer { buf in buf.insertCharacter(character) }
        onChange?(getText())
        if !isAutocompleting {
            triggerAutocomplete(explicit: false)
        } else {
            updateAutocomplete()
        }
    }

    private func insertNewLine() {
        buffer = withMutatingBuffer { buf in buf.insertNewLine() }
        onChange?(getText())
    }

    private func backspace() {
        buffer = withMutatingBuffer { buf in buf.backspace() }
        onChange?(getText())
    }

    private func deleteForward() {
        buffer = withMutatingBuffer { buf in buf.deleteForward() }
        onChange?(getText())
    }

    private func deleteWordForward() {
        buffer = withMutatingBuffer { buf in
            buf.deleteWordForward(isBoundary: isBoundary)
        }
        onChange?(getText())
    }

    private func moveCursor(lineDelta: Int, columnDelta: Int) {
        buffer = withMutatingBuffer { buf in buf.moveCursor(lineDelta: lineDelta, columnDelta: columnDelta) }
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
        buffer = EditorBuffer()
        pastes.removeAll()
        pasteCounter = 0
        onChange?("")
        onSubmit?(text)
    }

    private func deleteToStartOfLine() {
        buffer = withMutatingBuffer { buf in buf.deleteToStartOfLine() }
        onChange?(getText())
    }

    private func deleteToEndOfLine() {
        buffer = withMutatingBuffer { buf in buf.deleteToEndOfLine() }
        onChange?(getText())
    }

    private func deleteWordBackwards() {
        buffer = withMutatingBuffer { buf in
            buf.deleteWordBackwards(isBoundary: isBoundary)
        }
        onChange?(getText())
    }

    private func moveByWord(_ direction: Int) {
        buffer = withMutatingBuffer { buf in buf.moveByWord(direction, isBoundary: isBoundary) }
    }

    private func isPunctuation(_ ch: Character) -> Bool {
        let punctuation: Set<Character> = Set("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")
        return punctuation.contains(ch)
    }

    private func isBoundary(_ ch: Character) -> Bool {
        ch.isWhitespace || isPunctuation(ch)
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
        let currentLine = buffer.lines[buffer.cursorLine]
        let before = currentLine.prefix(buffer.cursorCol)
        let after = currentLine.suffix(currentLine.count - buffer.cursorCol)
        buffer = withMutatingBuffer { buf in
            buf.lines[buf.cursorLine] = String(before) + String(lines.first ?? "")
        }
        var insertionIndex = buffer.cursorLine + 1
        for middle in lines.dropFirst().dropLast() {
            buffer = withMutatingBuffer { buf in buf.lines.insert(String(middle), at: insertionIndex) }
            insertionIndex += 1
        }
        if let last = lines.last {
            buffer = withMutatingBuffer { buf in
                buf.lines.insert(String(last) + String(after), at: insertionIndex)
                buf.cursorLine = insertionIndex
                buf.cursorCol = String(last).count
            }
        }
        onChange?(getText())
    }

    private func triggerAutocomplete(explicit: Bool) {
        guard let provider = autocompleteProvider else { return }
        let suggestion = provider.getSuggestions(lines: buffer.lines, cursorLine: buffer.cursorLine, cursorCol: buffer.cursorCol)
        if let suggestion {
            autocompletePrefix = suggestion.prefix
            autocompleteList = SelectList(items: suggestion.items.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) }, maxVisible: 5)
            autocompleteList?.onSelect = { [weak self] selected in
                guard let self else { return }
                let result = provider.applyCompletion(
                    lines: self.buffer.lines,
                    cursorLine: self.buffer.cursorLine,
                    cursorCol: self.buffer.cursorCol,
                    item: AutocompleteItem(value: selected.value, label: selected.label, description: selected.description),
                    prefix: suggestion.prefix
                )
                self.buffer = self.withMutatingBuffer { buf in
                    buf.lines = result.lines
                    buf.cursorLine = result.cursorLine
                    buf.cursorCol = result.cursorCol
                }
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
        let suggestion = provider.getSuggestions(lines: buffer.lines, cursorLine: buffer.cursorLine, cursorCol: buffer.cursorCol)
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
            lines: buffer.lines,
            cursorLine: buffer.cursorLine,
            cursorCol: buffer.cursorCol,
            item: autocompleteItem,
            prefix: autocompletePrefix
        )
        buffer = withMutatingBuffer { buf in
            buf.lines = result.lines
            buf.cursorLine = result.cursorLine
            buf.cursorCol = result.cursorCol
        }
        cancelAutocomplete()
        onChange?(getText())
    }

    /// Helper to mutate the value-type buffer while keeping `Editor` reference semantics.
    private func withMutatingBuffer(_ mutate: (inout EditorBuffer) -> Void) -> EditorBuffer {
        var copy = buffer
        mutate(&copy)
        return copy
    }
}
