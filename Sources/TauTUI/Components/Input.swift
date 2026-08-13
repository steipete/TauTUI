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
        self.cursor = WordNavigation.destination(in: self.value, from: self.cursor, direction: .backward)
    }

    private func moveWordForwards() {
        guard self.cursor < self.value.count else { return }
        self.cursor = WordNavigation.destination(in: self.value, from: self.cursor, direction: .forward)
    }

    private func insert(_ string: String) {
        guard !string.isEmpty else { return }
        let idx = self.value.index(self.value.startIndex, offsetBy: self.cursor)
        self.value.insert(contentsOf: string, at: idx)
        self.cursor += string.count
    }

    private func cleanedPaste(_ text: String) -> String {
        PasteSanitizer.sanitize(text, allowsNewlines: false)
    }

    private func windowedValue(available: Int) -> (String, Int) {
        let totalWidth = VisibleWidth.measure(self.value)
        let cursorAtEnd = self.cursor == self.value.count
        let cursorWidth = cursorAtEnd ? 1 : 0
        if totalWidth + cursorWidth <= available {
            return (self.value, self.cursor)
        }

        let scrollWidth = cursorAtEnd ? available - 1 : available
        guard scrollWidth > 0 else { return ("", 0) }

        let beforeCursor = String(self.value.prefix(self.cursor))
        let cursorColumn = VisibleWidth.measure(beforeCursor)
        let half = scrollWidth / 2
        let startColumn = if cursorColumn < half {
            0
        } else if cursorColumn > totalWidth - half {
            max(0, totalWidth - scrollWidth)
        } else {
            max(0, cursorColumn - half)
        }

        let visible = self.sliceByColumns(self.value, start: startColumn, width: scrollWidth)
        let visibleBeforeCursor = self.sliceByColumns(
            self.value,
            start: startColumn,
            width: max(0, cursorColumn - startColumn))
        let cursorDisplay = visibleBeforeCursor.count
        return (visible, cursorDisplay)
    }

    private func sliceByColumns(_ text: String, start: Int, width: Int) -> String {
        guard width > 0 else { return "" }

        let end = start + width
        var column = 0
        var result = ""
        for grapheme in text {
            let graphemeWidth = VisibleWidth.measure(String(grapheme))
            if column >= start, column < end, column + graphemeWidth <= end {
                result.append(grapheme)
            }
            column += graphemeWidth
            if column >= end { break }
        }
        return result
    }

    @MainActor public func apply(theme: ThemePalette) {
        // Input currently has no theming knobs.
    }
}
