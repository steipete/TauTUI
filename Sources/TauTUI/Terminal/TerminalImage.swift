import Foundation

public enum ImageProtocol: Sendable {
    case kitty
    case iterm2
}

public struct TerminalCapabilities: Sendable {
    public var images: ImageProtocol?
    public var trueColor: Bool
    public var hyperlinks: Bool

    public init(images: ImageProtocol?, trueColor: Bool, hyperlinks: Bool) {
        self.images = images
        self.trueColor = trueColor
        self.hyperlinks = hyperlinks
    }
}

public struct CellDimensions: Sendable {
    public var widthPx: Int
    public var heightPx: Int

    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

public struct ImageDimensions: Sendable {
    public var widthPx: Int
    public var heightPx: Int

    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

public struct ImageRenderOptions: Sendable {
    public var maxWidthCells: Int?
    public var maxHeightCells: Int?
    public var preserveAspectRatio: Bool?

    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, preserveAspectRatio: Bool? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.preserveAspectRatio = preserveAspectRatio
    }
}

public enum TerminalImage {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var cachedCapabilities: TerminalCapabilities?
        var cellDimensions: CellDimensions = .init(widthPx: 9, heightPx: 18)
    }

    private static let storage = Storage()

    public static func getCellDimensions() -> CellDimensions {
        self.storage.lock.lock()
        defer { self.storage.lock.unlock() }
        return self.storage.cellDimensions
    }

    public static func setCellDimensions(_ dims: CellDimensions) {
        self.storage.lock.lock()
        self.storage.cellDimensions = dims
        self.storage.lock.unlock()
    }

    public static func detectCapabilities(
        env: [String: String] = ProcessInfo.processInfo.environment) -> TerminalCapabilities
    {
        let termProgram = (env["TERM_PROGRAM"] ?? "").lowercased()
        let term = (env["TERM"] ?? "").lowercased()
        let colorTerm = (env["COLORTERM"] ?? "").lowercased()

        if env["KITTY_WINDOW_ID"] != nil || termProgram == "kitty" {
            return .init(images: .kitty, trueColor: true, hyperlinks: true)
        }

        if termProgram == "ghostty" || term.contains("ghostty") || env["GHOSTTY_RESOURCES_DIR"] != nil {
            return .init(images: .kitty, trueColor: true, hyperlinks: true)
        }

        if env["WEZTERM_PANE"] != nil || termProgram == "wezterm" {
            return .init(images: .kitty, trueColor: true, hyperlinks: true)
        }

        if env["ITERM_SESSION_ID"] != nil || termProgram == "iterm.app" {
            return .init(images: .iterm2, trueColor: true, hyperlinks: true)
        }

        if termProgram == "vscode" {
            return .init(images: nil, trueColor: true, hyperlinks: true)
        }

        if termProgram == "alacritty" {
            return .init(images: nil, trueColor: true, hyperlinks: true)
        }

        let trueColor = colorTerm == "truecolor" || colorTerm == "24bit"
        return .init(images: nil, trueColor: trueColor, hyperlinks: true)
    }

    public static func getCapabilities() -> TerminalCapabilities {
        self.storage.lock.lock()
        if let cached = self.storage.cachedCapabilities {
            self.storage.lock.unlock()
            return cached
        }
        let caps = self.detectCapabilities()
        self.storage.cachedCapabilities = caps
        self.storage.lock.unlock()
        return caps
    }

    public static func resetCapabilitiesCache() {
        self.storage.lock.lock()
        self.storage.cachedCapabilities = nil
        self.storage.lock.unlock()
    }

    public static func encodeKitty(
        base64Data: String,
        columns: Int? = nil,
        rows: Int? = nil,
        imageId: Int? = nil) -> String
    {
        let chunkSize = 4096
        var params: [String] = ["a=T", "f=100", "q=2"]
        if let columns { params.append("c=\(columns)") }
        if let rows { params.append("r=\(rows)") }
        if let imageId { params.append("i=\(imageId)") }

        if base64Data.count <= chunkSize {
            return "\u{001B}_G\(params.joined(separator: ","));\(base64Data)\u{001B}\\"
        }

        var chunks: [String] = []
        chunks.reserveCapacity(max(1, base64Data.count / chunkSize))

        var offset = base64Data.startIndex
        var isFirst = true

        while offset < base64Data.endIndex {
            let end = base64Data.index(offset, offsetBy: chunkSize, limitedBy: base64Data.endIndex)
                ?? base64Data.endIndex
            let chunk = String(base64Data[offset..<end])
            let isLast = end == base64Data.endIndex

            if isFirst {
                chunks.append("\u{001B}_G\(params.joined(separator: ",")),m=1;\(chunk)\u{001B}\\")
                isFirst = false
            } else if isLast {
                chunks.append("\u{001B}_Gm=0;\(chunk)\u{001B}\\")
            } else {
                chunks.append("\u{001B}_Gm=1;\(chunk)\u{001B}\\")
            }

            offset = end
        }

        return chunks.joined()
    }

    public static func encodeITerm2(
        base64Data: String,
        width: String? = nil,
        height: String? = nil,
        name: String? = nil,
        preserveAspectRatio: Bool = true,
        inline: Bool = true) -> String
    {
        var params = ["inline=\(inline ? 1 : 0)"]
        if let width { params.append("width=\(width)") }
        if let height { params.append("height=\(height)") }
        if let name {
            let nameBase64 = Data(name.utf8).base64EncodedString()
            params.append("name=\(nameBase64)")
        }
        if preserveAspectRatio == false {
            params.append("preserveAspectRatio=0")
        }
        return "\u{001B}]1337;File=\(params.joined(separator: ";")):\(base64Data)\u{0007}"
    }

    public static func calculateImageRows(
        imageDimensions: ImageDimensions,
        targetWidthCells: Int,
        cellDimensions: CellDimensions = .init(widthPx: 9, heightPx: 18)) -> Int
    {
        guard targetWidthCells > 0,
              imageDimensions.widthPx > 0,
              imageDimensions.heightPx > 0,
              cellDimensions.widthPx > 0,
              cellDimensions.heightPx > 0
        else {
            return 1
        }

        let targetWidthPx = targetWidthCells * cellDimensions.widthPx
        let scale = Double(targetWidthPx) / Double(imageDimensions.widthPx)
        let scaledHeightPx = Double(imageDimensions.heightPx) * scale
        let rows = Int(ceil(scaledHeightPx / Double(cellDimensions.heightPx)))
        return max(1, rows)
    }

    public static func getImageDimensions(base64Data: String, mimeType: String) -> ImageDimensions? {
        switch mimeType {
        case "image/png":
            self.getPngDimensions(base64Data: base64Data)
        case "image/jpeg":
            self.getJpegDimensions(base64Data: base64Data)
        case "image/gif":
            self.getGifDimensions(base64Data: base64Data)
        case "image/webp":
            self.getWebpDimensions(base64Data: base64Data)
        default:
            nil
        }
    }

    public static func renderImage(
        base64Data: String,
        imageDimensions: ImageDimensions,
        options: ImageRenderOptions = .init()) -> (sequence: String, rows: Int)?
    {
        let caps = self.getCapabilities()
        guard let images = caps.images else { return nil }

        let maxWidth = options.maxWidthCells ?? 80
        let rows = self.calculateImageRows(
            imageDimensions: imageDimensions,
            targetWidthCells: maxWidth,
            cellDimensions: self.getCellDimensions())

        switch images {
        case .kitty:
            let sequence = self.encodeKitty(base64Data: base64Data, columns: maxWidth, rows: rows)
            return (sequence: sequence, rows: rows)
        case .iterm2:
            let sequence = self.encodeITerm2(
                base64Data: base64Data,
                width: "\(maxWidth)",
                height: "auto",
                preserveAspectRatio: options.preserveAspectRatio ?? true,
                inline: true)
            return (sequence: sequence, rows: rows)
        }
    }

    public static func imageFallback(
        mimeType: String,
        dimensions: ImageDimensions? = nil,
        filename: String? = nil) -> String
    {
        var parts: [String] = []
        if let filename { parts.append(filename) }
        parts.append("[\(mimeType)]")
        if let dimensions { parts.append("\(dimensions.widthPx)x\(dimensions.heightPx)") }
        return "[Image: \(parts.joined(separator: " "))]"
    }

    public static func getPngDimensions(base64Data: String) -> ImageDimensions? {
        guard let data = Data(base64Encoded: base64Data, options: [.ignoreUnknownCharacters]) else { return nil }
        if data.count < 24 { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 else { return nil }
        let width = Int(readUInt32BE(bytes, offset: 16))
        let height = Int(readUInt32BE(bytes, offset: 20))
        return .init(widthPx: width, heightPx: height)
    }

    public static func getJpegDimensions(base64Data: String) -> ImageDimensions? {
        guard let data = Data(base64Encoded: base64Data, options: [.ignoreUnknownCharacters]) else { return nil }
        let bytes = [UInt8](data)
        if bytes.count < 2 { return nil }
        guard bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }

        var offset = 2
        while offset < bytes.count - 9 {
            if bytes[offset] != 0xFF {
                offset += 1
                continue
            }

            let marker = bytes[offset + 1]
            if marker >= 0xC0, marker <= 0xC2 {
                let height = Int(readUInt16BE(bytes, offset: offset + 5))
                let width = Int(readUInt16BE(bytes, offset: offset + 7))
                return .init(widthPx: width, heightPx: height)
            }

            if offset + 3 >= bytes.count { return nil }
            let length = Int(readUInt16BE(bytes, offset: offset + 2))
            if length < 2 { return nil }
            offset += 2 + length
        }

        return nil
    }

    public static func getGifDimensions(base64Data: String) -> ImageDimensions? {
        guard let data = Data(base64Encoded: base64Data, options: [.ignoreUnknownCharacters]) else { return nil }
        if data.count < 10 { return nil }
        let bytes = [UInt8](data)
        let sig = String(bytes: Array(bytes[0..<6]), encoding: .ascii) ?? ""
        if sig != "GIF87a", sig != "GIF89a" { return nil }
        let width = Int(readUInt16LE(bytes, offset: 6))
        let height = Int(readUInt16LE(bytes, offset: 8))
        return .init(widthPx: width, heightPx: height)
    }

    public static func getWebpDimensions(base64Data: String) -> ImageDimensions? {
        guard let data = Data(base64Encoded: base64Data, options: [.ignoreUnknownCharacters]) else { return nil }
        if data.count < 30 { return nil }
        let bytes = [UInt8](data)
        let riff = String(bytes: Array(bytes[0..<4]), encoding: .ascii) ?? ""
        let webp = String(bytes: Array(bytes[8..<12]), encoding: .ascii) ?? ""
        guard riff == "RIFF", webp == "WEBP" else { return nil }

        let chunk = String(bytes: Array(bytes[12..<16]), encoding: .ascii) ?? ""
        switch chunk {
        case "VP8 ":
            if bytes.count < 30 { return nil }
            let width = Int(readUInt16LE(bytes, offset: 26) & 0x3FFF)
            let height = Int(readUInt16LE(bytes, offset: 28) & 0x3FFF)
            return .init(widthPx: width, heightPx: height)
        case "VP8L":
            if bytes.count < 25 { return nil }
            let bits = self.readUInt32LE(bytes, offset: 21)
            let width = Int((bits & 0x3FFF) + 1)
            let height = Int(((bits >> 14) & 0x3FFF) + 1)
            return .init(widthPx: width, heightPx: height)
        case "VP8X":
            if bytes.count < 30 { return nil }
            let width = Int(UInt32(bytes[24]) | (UInt32(bytes[25]) << 8) | (UInt32(bytes[26]) << 16)) + 1
            let height = Int(UInt32(bytes[27]) | (UInt32(bytes[28]) << 8) | (UInt32(bytes[29]) << 16)) + 1
            return .init(widthPx: width, heightPx: height)
        default:
            return nil
        }
    }

    private static func readUInt16BE(_ bytes: [UInt8], offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt16LE(_ bytes: [UInt8], offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32BE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
