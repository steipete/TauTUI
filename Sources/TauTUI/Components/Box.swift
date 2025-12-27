/// Container that applies padding and optional background to all children.
/// Mirrors `packages/tui/src/components/box.ts` in pi-mono.
public final class Box: Container {
    public var paddingX: Int { didSet { self.invalidateCache() } }
    public var paddingY: Int { didSet { self.invalidateCache() } }
    public var background: AnsiStyling.Background? { didSet { self.invalidateCache() } }

    private var cachedWidth: Int?
    private var cachedChildLinesKey: String?
    private var cachedBackground: AnsiStyling.Background?
    private var cachedLines: [String]?

    public init(
        paddingX: Int = 1,
        paddingY: Int = 1,
        background: AnsiStyling.Background? = nil,
        children: [Component] = [])
    {
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.background = background
        super.init(children: children)
    }

    override public func addChild(_ child: Component) {
        super.addChild(child)
        self.invalidateCache()
    }

    override public func removeChild(_ child: Component) {
        super.removeChild(child)
        self.invalidateCache()
    }

    override public func clear() {
        super.clear()
        self.invalidateCache()
    }

    override public func invalidate() {
        self.invalidateCache()
        super.invalidate()
    }

    override public func render(width: Int) -> [String] {
        if self.children.isEmpty { return [] }

        let contentWidth = max(1, width - self.paddingX * 2)
        let leftPad = String(repeating: " ", count: max(0, self.paddingX))

        var childLines: [String] = []
        for child in self.children {
            for line in child.render(width: contentWidth) {
                childLines.append(leftPad + line)
            }
        }

        if childLines.isEmpty { return [] }

        let childLinesKey = childLines.joined(separator: "\n")
        if let cachedLines,
           self.cachedWidth == width,
           self.cachedChildLinesKey == childLinesKey,
           self.cachedBackground == self.background
        {
            return cachedLines
        }

        var result: [String] = []
        for _ in 0..<max(0, self.paddingY) {
            result.append(self.applyBackground("", width: width))
        }
        for line in childLines {
            result.append(self.applyBackground(line, width: width))
        }
        for _ in 0..<max(0, self.paddingY) {
            result.append(self.applyBackground("", width: width))
        }

        self.cachedWidth = width
        self.cachedChildLinesKey = childLinesKey
        self.cachedBackground = self.background
        self.cachedLines = result
        return result
    }

    private func invalidateCache() {
        self.cachedWidth = nil
        self.cachedChildLinesKey = nil
        self.cachedBackground = nil
        self.cachedLines = nil
    }

    private func applyBackground(_ line: String, width: Int) -> String {
        let visibleLen = VisibleWidth.measure(line)
        let padNeeded = max(0, width - visibleLen)
        let padded = line + String(repeating: " ", count: padNeeded)

        if let background = self.background {
            return AnsiWrapping.applyBackgroundToLine(padded, width: width, background: background)
        }
        return padded
    }
}
