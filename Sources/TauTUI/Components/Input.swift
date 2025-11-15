/// Single-line text input with horizontal scrolling and fake cursor rendering.
public final class Input: Component {
    public var value: String {
        didSet { cursor = min(cursor, value.count) }
    }

    private var cursor: Int
    public var onSubmit: ((String) -> Void)?

    public init(value: String = "") {
        self.value = value
        self.cursor = value.count
    }

    public func setValue(_ newValue: String) {
        value = newValue
        cursor = min(cursor, value.count)
    }

    public func render(width: Int) -> [String] {
        let prompt = "> "
        let available = width - prompt.count
        guard available > 0 else { return [prompt] }

        let (visibleText, cursorDisplayIndex) = windowedValue(available: available)
        let cursorChar = cursorDisplayIndex < visibleText.count ? visibleText[visibleText.index(visibleText.startIndex, offsetBy: cursorDisplayIndex)] : " "
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
        case .key(let key, let modifiers):
            handleKey(key, modifiers: modifiers)
        case .paste(let text):
            insert(text)
        case .raw(let data):
            data.forEach { insert(String($0)) }
        }
    }

    private func handleKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        switch key {
        case .character(let char):
            insert(String(char))
        case .enter:
            onSubmit?(value)
        case .backspace:
            guard cursor > 0 else { return }
            let index = value.index(value.startIndex, offsetBy: cursor - 1)
            value.remove(at: index)
            cursor -= 1
        case .delete:
            guard cursor < value.count else { return }
            let index = value.index(value.startIndex, offsetBy: cursor)
            value.remove(at: index)
        case .arrowLeft:
            cursor = max(0, cursor - 1)
        case .arrowRight:
            cursor = min(value.count, cursor + 1)
        case .home:
            cursor = 0
        case .end:
            cursor = value.count
        default:
            break
        }
    }

    private func insert(_ string: String) {
        guard !string.isEmpty else { return }
        let idx = value.index(value.startIndex, offsetBy: cursor)
        value.insert(contentsOf: string, at: idx)
        cursor += string.count
    }

    private func windowedValue(available: Int) -> (String, Int) {
        if value.count <= available {
            return (value, cursor)
        }
        let cursorAtEnd = cursor == value.count
        let scrollWidth = cursorAtEnd ? available - 1 : available
        let half = scrollWidth / 2
        var startIndex = cursor - half
        startIndex = max(0, min(startIndex, value.count - scrollWidth))
        let start = value.index(value.startIndex, offsetBy: startIndex)
        let end = value.index(start, offsetBy: min(scrollWidth, value.count - startIndex))
        let visible = String(value[start..<end])
        let cursorDisplay = cursorAtEnd ? visible.count : cursor - startIndex
        return (visible, cursorDisplay)
    }
}
