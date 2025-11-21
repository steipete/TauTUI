/// Single-line text input with horizontal scrolling and fake cursor rendering.
public final class Input: Component {
    public var value: String {
        didSet { self.cursor = min(self.cursor, self.value.count) }
    }

    private var cursor: Int
    private var pasteBuffer: String = ""
    private var isInPaste = false
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
        case let .raw(data):
            self.handleRaw(data)
        }
    }

    private func handleRaw(_ data: String) {
        var buffer = data

        if buffer.contains("\u{001B}[200~") {
            self.isInPaste = true
            buffer = buffer.replacingOccurrences(of: "\u{001B}[200~", with: "")
        }

        if self.isInPaste {
            self.pasteBuffer += buffer
            if let endRange = self.pasteBuffer.range(of: "\u{001B}[201~") {
                let beforeEnd = String(self.pasteBuffer[..<endRange.lowerBound])
                self.insert(self.cleanedPaste(beforeEnd))
                let trailing = String(self.pasteBuffer[endRange.upperBound...])
                self.pasteBuffer.removeAll(keepingCapacity: false)
                self.isInPaste = false
                if !trailing.isEmpty {
                    self.handleRaw(trailing)
                }
            }
            return
        }

        buffer.forEach { self.insert(String($0)) }
    }

    private func handleKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        switch key {
        case let .character(char):
            self.insert(String(char))
        case .enter:
            self.onSubmit?(self.value)
        case .backspace:
            guard self.cursor > 0 else { return }
            let index = self.value.index(self.value.startIndex, offsetBy: self.cursor - 1)
            self.value.remove(at: index)
            self.cursor -= 1
        case .delete:
            guard self.cursor < self.value.count else { return }
            let index = self.value.index(self.value.startIndex, offsetBy: self.cursor)
            self.value.remove(at: index)
        case .arrowLeft:
            self.cursor = max(0, self.cursor - 1)
        case .arrowRight:
            self.cursor = min(self.value.count, self.cursor + 1)
        case .home:
            self.cursor = 0
        case .end:
            self.cursor = self.value.count
        default:
            break
        }
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
