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
        let cleaned = self.stripOscAndKitty(from: text)
        let range = NSRange(location: 0, length: cleaned.utf16.count)
        return self.escapeRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
    }

    static func normalizeTabs(_ text: String, spacesPerTab: Int) -> String {
        guard spacesPerTab > 0 else { return text }
        let replacement = String(repeating: " ", count: spacesPerTab)
        return text.replacingOccurrences(of: "\t", with: replacement)
    }

    private static func stripOscAndKitty(from text: String) -> String {
        guard text.contains("\u{001B}") else { return text }

        var result = ""
        result.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\u{001B}" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    let introducer = text[next]

                    // Kitty graphics protocol: ESC _ G ... ESC \
                    if introducer == "_" {
                        let gIndex = text.index(after: next)
                        if gIndex < text.endIndex, text[gIndex] == "G" {
                            if let end = text.range(of: "\u{001B}\\", range: gIndex..<text.endIndex) {
                                index = end.upperBound
                                continue
                            }
                            break // drop unterminated sequence
                        }
                    }

                    // OSC: ESC ] ... (BEL or ST)
                    if introducer == "]" {
                        let oscStart = text.index(after: next)
                        if let bel = text[oscStart...].firstIndex(of: "\u{0007}") {
                            index = text.index(after: bel)
                            continue
                        }
                        if let st = text.range(of: "\u{001B}\\", range: oscStart..<text.endIndex) {
                            index = st.upperBound
                            continue
                        }
                        break // drop unterminated OSC
                    }
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }
}
