/// Single-line text input with horizontal scrolling and fake cursor rendering.
public final class Input: Component {
    public var value: String {
        didSet { self.cursor = min(self.cursor, self.value.count) }
    }

    private var cursor: Int
    public var onSubmit: ((String) -> Void)?

    public init(value: String = "") {
        self.value = value
        self.cursor = value.count
    }

    public func setValue(_ newValue: String) {
        self.value = newValue
        self.cursor = min(self.cursor, self.value.count)
    }

    public func render(width: Int) -> [String] {
        let prompt = "> "
        let available = width - prompt.count
        guard available > 0 else { return [prompt] }

        let (visibleText, cursorDisplayIndex) = self.windowedValue(available: available)
        let cursorChar = cursorDisplayIndex < visibleText.count ? visibleText[visibleText.index(
            visibleText.startIndex,
            offsetBy: cursorDisplayIndex)] : " "
        var rendered = visibleText
        if cursorDisplayIndex < visibleText.count {
            let idx = rendered.index(rendered.startIndex, offsetBy: cursorDisplayIndex)
            rendered.replaceSubrange(idx...idx, with: "\u{001B}[7m\(cursorChar)\u{001B}[27m")
        } else {
            rendered.append("\u{001B}[7m \u{001B}[27m")
        }
        let printableWidth = VisibleWidth.measure(rendered)
        if printableWidth < available {
            rendered.append(String(repeating: " ", count: available - printableWidth))
        }
        return [prompt + rendered]
    }

    public func handle(input: TerminalInput) {
        switch input {
        case let .key(key, modifiers):
            self.handleKey(key, modifiers: modifiers)
        case let .paste(text):
            self.insert(self.cleanedPaste(text))
        case .raw:
            break
        case .terminalCellSize:
            break
        }
    }

    private func handleKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        switch key {
        case let .character(char):
            if modifiers.contains(.control) {
                switch char.lowercased() {
                case "a":
                    self.cursor = 0
                case "e":
                    self.cursor = self.value.count
                case "w":
                    self.deleteWordBackwards()
                case "u":
                    self.deleteToStartOfLine()
                case "k":
                    self.deleteToEndOfLine()
                default:
                    break
                }
            } else {
                self.insert(String(char))
            }
        case .enter:
            self.onSubmit?(self.value)
        case .backspace:
            if modifiers.contains(.option) {
                self.deleteWordBackwards()
            } else {
                self.backspace()
            }
        case .delete:
            self.deleteForward()
        case .arrowLeft:
            if modifiers.contains(.control) || modifiers.contains(.option) {
                self.moveWordBackwards()
            } else {
                self.cursor = max(0, self.cursor - 1)
            }
        case .arrowRight:
            if modifiers.contains(.control) || modifiers.contains(.option) {
                self.moveWordForwards()
            } else {
                self.cursor = min(self.value.count, self.cursor + 1)
            }
        case .home:
            self.cursor = 0
        case .end:
            self.cursor = self.value.count
        default:
            break
        }
    }

    private func backspace() {
        guard self.cursor > 0 else { return }
        let index = self.value.index(self.value.startIndex, offsetBy: self.cursor - 1)
        self.value.remove(at: index)
        self.cursor -= 1
    }

    private func deleteForward() {
        guard self.cursor < self.value.count else { return }
        let index = self.value.index(self.value.startIndex, offsetBy: self.cursor)
        self.value.remove(at: index)
    }

    private func deleteToStartOfLine() {
        guard self.cursor > 0 else { return }
        let start = self.value.startIndex
        let end = self.value.index(start, offsetBy: self.cursor)
        self.value.removeSubrange(start..<end)
        self.cursor = 0
    }

    private func deleteToEndOfLine() {
        guard self.cursor < self.value.count else { return }
        let start = self.value.index(self.value.startIndex, offsetBy: self.cursor)
        self.value.removeSubrange(start..<self.value.endIndex)
    }

    private func deleteWordBackwards() {
        guard self.cursor > 0 else { return }
        let oldCursor = self.cursor
        self.moveWordBackwards()
        let deleteFrom = self.cursor
        self.cursor = oldCursor

        let start = self.value.index(self.value.startIndex, offsetBy: deleteFrom)
        let end = self.value.index(self.value.startIndex, offsetBy: self.cursor)
        self.value.removeSubrange(start..<end)
        self.cursor = deleteFrom
    }

    private func moveWordBackwards() {
        guard self.cursor > 0 else { return }
        let chars = Array(self.value)
        var idx = self.cursor

        while idx > 0, chars[idx - 1].isWhitespace {
            idx -= 1
        }

        if idx > 0 {
            if self.isPunctuation(chars[idx - 1]) {
                while idx > 0, self.isPunctuation(chars[idx - 1]) {
                    idx -= 1
                }
            } else {
                while idx > 0, !chars[idx - 1].isWhitespace, !self.isPunctuation(chars[idx - 1]) {
                    idx -= 1
                }
            }
        }

        self.cursor = idx
    }

    private func moveWordForwards() {
        let chars = Array(self.value)
        guard self.cursor < chars.count else { return }
        var idx = self.cursor

        while idx < chars.count, chars[idx].isWhitespace {
            idx += 1
        }

        if idx < chars.count {
            if self.isPunctuation(chars[idx]) {
                while idx < chars.count, self.isPunctuation(chars[idx]) {
                    idx += 1
                }
            } else {
                while idx < chars.count, !chars[idx].isWhitespace, !self.isPunctuation(chars[idx]) {
                    idx += 1
                }
            }
        }

        self.cursor = idx
    }

    private func isPunctuation(_ ch: Character) -> Bool {
        let punctuation: Set<Character> = Set("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")
        return punctuation.contains(ch)
    }

    private func insert(_ string: String) {
        guard !string.isEmpty else { return }
        let idx = self.value.index(self.value.startIndex, offsetBy: self.cursor)
        self.value.insert(contentsOf: string, at: idx)
        self.cursor += string.count
    }

    private func cleanedPaste(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func windowedValue(available: Int) -> (String, Int) {
        if self.value.count <= available {
            return (self.value, self.cursor)
        }
        let cursorAtEnd = self.cursor == self.value.count
        let scrollWidth = cursorAtEnd ? available - 1 : available
        let half = scrollWidth / 2
        var startIndex = self.cursor - half
        startIndex = max(0, min(startIndex, self.value.count - scrollWidth))
        let start = self.value.index(self.value.startIndex, offsetBy: startIndex)
        let end = self.value.index(start, offsetBy: min(scrollWidth, self.value.count - startIndex))
        let visible = String(value[start..<end])
        let cursorDisplay = cursorAtEnd ? visible.count : self.cursor - startIndex
        return (visible, cursorDisplay)
    }

    @MainActor public func apply(theme: ThemePalette) {
        // Input currently has no theming knobs.
    }
}
