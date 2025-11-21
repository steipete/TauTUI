import Foundation

/// Lightweight ANSI styling helpers with composable foreground/background and text attributes.
public enum AnsiStyling {
    public typealias Style = @Sendable (String) -> String

    // MARK: - Foreground colors

    public static func color(_ code: Int) -> Style {
        { "\u{001B}[\(code)m\($0)\u{001B}[39m" }
    }

    public static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Style {
        { "\u{001B}[38;2;\(red);\(green);\(blue)m\($0)\u{001B}[39m" }
    }

    // MARK: - Text attributes

    public static let bold: Style = { "\u{001B}[1m\($0)\u{001B}[22m" }
    public static let dim: Style = { "\u{001B}[2m\($0)\u{001B}[22m" }
    public static let italic: Style = { "\u{001B}[3m\($0)\u{001B}[23m" }
    public static let underline: Style = { "\u{001B}[4m\($0)\u{001B}[24m" }
    public static let strikethrough: Style = { "\u{001B}[9m\($0)\u{001B}[29m" }

    // MARK: - Background

    public struct Background: Equatable, Sendable {
        public let start: String
        public let end: String

        public init(start: String, end: String = "\u{001B}[49m") {
            self.start = start
            self.end = end
        }

        public static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Background {
            Background(start: "\u{001B}[48;2;\(red);\(green);\(blue)m")
        }

        public func apply(_ text: String) -> String {
            // Apply background, reapplying after any full reset (0m) or background reset (49m).
            var withBg = self.start + text + self.end
            withBg = withBg.replacingOccurrences(of: "\u{001B}[0m", with: "\u{001B}[0m" + self.start)
            withBg = withBg.replacingOccurrences(of: "\u{001B}[49m", with: "\u{001B}[49m" + self.start)
            return withBg
        }
    }
}
