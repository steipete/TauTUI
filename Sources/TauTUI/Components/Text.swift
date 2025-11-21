/// Displays multi-line text with padding and optional RGB background color.
public final class Text: Component {
    public struct Background: Equatable, Sendable {
        public let style: AnsiStyling.Background

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.style = .rgb(red, green, blue)
        }

        public init(style: AnsiStyling.Background) {
            self.style = style
        }
    }

    public var text: String {
        didSet { self.invalidateCache() }
    }

    public var paddingX: Int {
        get { self._paddingX }
        set {
            let clamped = max(0, newValue)
            if clamped != self._paddingX {
                self._paddingX = clamped
                self.invalidateCache()
            }
        }
    }

    public var paddingY: Int {
        get { self._paddingY }
        set {
            let clamped = max(0, newValue)
            if clamped != self._paddingY {
                self._paddingY = clamped
                self.invalidateCache()
            }
        }
    }

    public var background: Background? {
        didSet { self.invalidateCache() }
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
            self.cachedWidth = width
            self.cachedLines = []
            return []
        }

        let contentWidth = max(1, width - self._paddingX * 2)
        let lines = AnsiWrapping.wrapText(self.text, width: contentWidth)

        let leftPad = String(repeating: " ", count: _paddingX)
        let emptyLine = String(repeating: " ", count: width)
        var result: [String] = []

        for _ in 0..<self._paddingY {
            result.append(self.applyBackground(emptyLine))
        }

        for line in lines {
            let visible = VisibleWidth.measure(line)
            let rightPadding = max(0, width - self._paddingX - visible)
            let paddedLine = leftPad + line + String(repeating: " ", count: rightPadding)

            result.append(self.applyBackground(paddedLine))
        }

        for _ in 0..<self._paddingY {
            result.append(self.applyBackground(emptyLine))
        }

        self.cachedWidth = width
        self.cachedLines = result
        return result
    }

    private func invalidateCache() {
        self.cachedWidth = nil
        self.cachedLines = nil
    }

    public func invalidate() {
        self.invalidateCache()
    }

    private func applyBackground(_ line: String) -> String {
        guard let background else { return line }
        return AnsiWrapping.applyBackgroundToLine(line, width: VisibleWidth.measure(line), background: background.style)
    }

    @MainActor public func apply(theme: ThemePalette) {
        self.background = theme.textBackground
    }
}
