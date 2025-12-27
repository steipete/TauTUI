public struct ImageTheme: Sendable {
    public var fallbackColor: @Sendable (_ str: String) -> String

    public init(fallbackColor: @escaping @Sendable (_ str: String) -> String) {
        self.fallbackColor = fallbackColor
    }

    public static let `default` = ImageTheme(fallbackColor: { "\u{001B}[90m\($0)\u{001B}[39m" })
}

public struct ImageOptions: Sendable {
    public var maxWidthCells: Int?
    public var maxHeightCells: Int?
    public var filename: String?

    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, filename: String? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.filename = filename
    }
}

public final class Image: Component {
    private let base64Data: String
    private let mimeType: String
    private let dimensions: ImageDimensions
    private let theme: ImageTheme
    private let options: ImageOptions

    private var cachedLines: [String]?
    private var cachedWidth: Int?

    public init(
        base64Data: String,
        mimeType: String,
        theme: ImageTheme = .default,
        options: ImageOptions = .init(),
        dimensions: ImageDimensions? = nil)
    {
        self.base64Data = base64Data
        self.mimeType = mimeType
        self.theme = theme
        self.options = options
        self.dimensions = dimensions
            ?? TerminalImage.getImageDimensions(base64Data: base64Data, mimeType: mimeType)
            ?? .init(widthPx: 800, heightPx: 600)
    }

    public func invalidate() {
        self.cachedLines = nil
        self.cachedWidth = nil
    }

    public func render(width: Int) -> [String] {
        if let cachedLines, self.cachedWidth == width {
            return cachedLines
        }

        let maxWidth = max(1, min(max(0, width - 2), self.options.maxWidthCells ?? 60))

        let caps = TerminalImage.getCapabilities()
        let lines: [String]

        if caps.images != nil,
           let result = TerminalImage.renderImage(
               base64Data: self.base64Data,
               imageDimensions: self.dimensions,
               options: .init(maxWidthCells: maxWidth))
        {
            var buffer: [String] = []
            buffer.reserveCapacity(result.rows)
            if result.rows > 1 {
                buffer.append(contentsOf: Array(repeating: "", count: result.rows - 1))
            }
            let moveUp = result.rows > 1 ? "\u{001B}[\(result.rows - 1)A" : ""
            buffer.append(moveUp + result.sequence)
            lines = buffer
        } else {
            let fallback = TerminalImage.imageFallback(
                mimeType: self.mimeType,
                dimensions: self.dimensions,
                filename: self.options.filename)
            lines = [self.theme.fallbackColor(fallback)]
        }

        self.cachedLines = lines
        self.cachedWidth = width
        return lines
    }
}
