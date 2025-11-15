/// Displays multi-line text with padding and optional RGB background color.
public final class Text: Component {
    public struct Background: Equatable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var ansiPrefix: String {
            "\u{001B}[48;2;\(red);\(green);\(blue)m"
        }
    }

    public var text: String {
        didSet { invalidateCache() }
    }

    public var paddingX: Int {
        get { _paddingX }
        set {
            let clamped = max(0, newValue)
            if clamped != _paddingX {
                _paddingX = clamped
                invalidateCache()
            }
        }
    }

    public var paddingY: Int {
        get { _paddingY }
        set {
            let clamped = max(0, newValue)
            if clamped != _paddingY {
                _paddingY = clamped
                invalidateCache()
            }
        }
    }

    public var background: Background? {
        didSet { invalidateCache() }
    }

    private var _paddingX: Int
    private var _paddingY: Int
    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(text: String = "", paddingX: Int = 1, paddingY: Int = 1, background: Background? = nil) {
        self.text = text
        self._paddingX = max(0, paddingX)
        self._paddingY = max(0, paddingY)
        self.background = background
    }

    public func render(width: Int) -> [String] {
        if let cached = cachedLines, cachedWidth == width {
            return cached
        }

        guard width > 0 else {
            cachedWidth = width
            cachedLines = []
            return []
        }

        let contentWidth = max(1, width - _paddingX * 2)
        let normalized = Ansi.normalizeTabs(text, spacesPerTab: 3)
        var lines: [String] = []

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            wrapLine(String(rawLine), contentWidth: contentWidth, into: &lines)
        }

        if lines.isEmpty {
            lines.append("")
        }

        let leftPad = String(repeating: " ", count: _paddingX)
        let emptyLine = String(repeating: " ", count: width)
        var result: [String] = []

        for _ in 0..<_paddingY {
            result.append(applyBackground(to: emptyLine))
        }

        for line in lines {
            let visible = VisibleWidth.measure(line)
            let rightPadding = max(0, width - _paddingX - visible)
            let paddedLine = leftPad + line + String(repeating: " ", count: rightPadding)
            result.append(applyBackground(to: paddedLine))
        }

        for _ in 0..<_paddingY {
            result.append(applyBackground(to: emptyLine))
        }

        cachedWidth = width
        cachedLines = result
        return result
    }

    private func wrapLine(_ line: String, contentWidth: Int, into output: inout [String]) {
        guard !line.isEmpty else {
            output.append("")
            return
        }

        var current = ""
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let wordString = String(word)
            if wordString.isEmpty {
                current.append(" ")
                continue
            }

            if current.isEmpty {
                if VisibleWidth.measure(wordString) <= contentWidth {
                    current = wordString
                } else {
                    output.append(contentsOf: breakLongWord(wordString, limit: contentWidth))
                }
                continue
            }

            let candidate = current + " " + wordString
            if VisibleWidth.measure(candidate) <= contentWidth {
                current = candidate
            } else {
                output.append(current)
                if VisibleWidth.measure(wordString) <= contentWidth {
                    current = wordString
                } else {
                    output.append(contentsOf: breakLongWord(wordString, limit: contentWidth))
                    current = ""
                }
            }
        }

        if !current.isEmpty {
            output.append(current)
        }
    }

    private func breakLongWord(_ word: String, limit: Int) -> [String] {
        guard limit > 0 else { return [word] }
        var result: [String] = []
        var current = ""
        for char in word {
            let next = current + String(char)
            if VisibleWidth.measure(next) > limit {
                if !current.isEmpty {
                    result.append(current)
                    current = String(char)
                } else {
                    result.append(String(char))
                    current = ""
                }
            } else {
                current = next
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func applyBackground(to line: String) -> String {
        guard let background else { return line }
        return background.ansiPrefix + line + "\u{001B}[0m"
    }

    private func invalidateCache() {
        cachedWidth = nil
        cachedLines = nil
    }
}
