import Foundation

/// Single-line text that truncates with an ellipsis and pads to the viewport width.
public final class TruncatedText: Component {
    public var text: String
    public var paddingX: Int
    public var paddingY: Int
    public var background: AnsiStyling.Background?

    public init(text: String, paddingX: Int = 1, paddingY: Int = 0, background: AnsiStyling.Background? = nil) {
        self.text = text
        self.paddingX = max(0, paddingX)
        self.paddingY = max(0, paddingY)
        self.background = background
    }

    public func render(width: Int) -> [String] {
        guard width > 0 else { return [] }

        var result: [String] = []
        let emptyLine = String(repeating: " ", count: width)

        for _ in 0..<self.paddingY {
            result.append(self.applyBackground(emptyLine))
        }

        let availableWidth = max(1, width - self.paddingX * 2)
        let truncated = self.truncatedLine(maxVisibleWidth: availableWidth)
        let leftPad = String(repeating: " ", count: self.paddingX)
        let rightPadWidth = max(0, width - (self.paddingX + VisibleWidth.measure(truncated)))
        let lineWithPadding = leftPad + truncated + String(repeating: " ", count: rightPadWidth)
        let finalLine = self.applyBackground(lineWithPadding)
        result.append(finalLine)

        for _ in 0..<self.paddingY {
            result.append(self.applyBackground(emptyLine))
        }

        return result
    }

    private func truncatedLine(maxVisibleWidth: Int) -> String {
        // Only render up to the first newline
        var firstLine = self.text
        if let newline = self.text.firstIndex(of: "\n") {
            firstLine = String(self.text[..<newline])
        }

        let visible = VisibleWidth.measure(firstLine)
        guard visible > maxVisibleWidth else { return firstLine }

        let target = max(0, maxVisibleWidth - 3) // space for "..."
        var currentWidth = 0
        var truncateAt = firstLine.startIndex
        var index = firstLine.startIndex

        while index < firstLine.endIndex {
            if let ansi = Self.extractAnsi(in: firstLine, from: index) {
                index = ansi.next
                truncateAt = index
                continue
            }

            let char = String(firstLine[index])
            let charWidth = VisibleWidth.measure(char)
            if currentWidth + charWidth > target {
                break
            }
            currentWidth += charWidth
            truncateAt = firstLine.index(after: index)
            index = truncateAt
        }

        let prefix = String(firstLine[..<truncateAt])
        return prefix + "\u{001B}[0m..."
    }

    public static func truncate(_ text: String, toWidth maxWidth: Int, ellipsis: String = "...") -> String {
        guard maxWidth > 0 else { return "" }

        // Only render up to the first newline
        var firstLine = text
        if let newline = text.firstIndex(of: "\n") {
            firstLine = String(text[..<newline])
        }

        let visible = VisibleWidth.measure(firstLine)
        guard visible > maxWidth else { return firstLine }

        let ellipsisWidth = VisibleWidth.measure(ellipsis)
        let target = maxWidth - ellipsisWidth
        if target <= 0 {
            return String(ellipsis.prefix(maxWidth))
        }

        var currentWidth = 0
        var truncateAt = firstLine.startIndex
        var index = firstLine.startIndex

        while index < firstLine.endIndex {
            if let ansi = Self.extractAnsi(in: firstLine, from: index) {
                index = ansi.next
                truncateAt = index
                continue
            }

            let char = firstLine[index]
            let charWidth = VisibleWidth.measure(String(char))
            if currentWidth + charWidth > target {
                break
            }
            currentWidth += charWidth
            truncateAt = firstLine.index(after: index)
            index = truncateAt
        }

        let prefix = String(firstLine[..<truncateAt])
        return prefix + "\u{001B}[0m" + ellipsis
    }

    private static func extractAnsi(in text: String, from index: String.Index) -> (code: String, next: String.Index)? {
        guard text[index] == "\u{001B}", text.index(after: index) < text.endIndex else { return nil }
        var current = text.index(after: index)
        while current < text.endIndex {
            let scalar = text[current].unicodeScalars.first!.value
            if scalar >= 0x40, scalar <= 0x7E {
                let next = text.index(after: current)
                return (String(text[index..<next]), next)
            }
            current = text.index(after: current)
        }
        return nil
    }

    private func applyBackground(_ line: String) -> String {
        guard let background else { return line }
        return AnsiWrapping.applyBackgroundToLine(line, width: VisibleWidth.measure(line), background: background)
    }

    public func invalidate() {}

    @MainActor public func apply(theme: ThemePalette) {
        self.background = theme.truncatedBackground
    }
}
