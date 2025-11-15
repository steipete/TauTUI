import Foundation

/// Simple helpers for stripping / normalizing ANSI escape sequences so layout
/// calculations can operate on visible characters.
enum Ansi {
    private static let escapeRegex: NSRegularExpression = {
        // Matches CSI sequences and single-character escapes.
        let pattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]|\u{001B}[()][0-2AB]|\u{001B}."
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            preconditionFailure("Failed to compile ANSI regex: \(error)")
        }
    }()

    static func stripCodes(_ text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        return self.escapeRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    static func normalizeTabs(_ text: String, spacesPerTab: Int) -> String {
        guard spacesPerTab > 0 else { return text }
        let replacement = String(repeating: " ", count: spacesPerTab)
        return text.replacingOccurrences(of: "\t", with: replacement)
    }
}
