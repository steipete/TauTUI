import Foundation

enum PasteSanitizer {
    static func sanitize(_ text: String, allowsNewlines: Bool, tabWidth: Int = 4) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: String(repeating: " ", count: max(0, tabWidth)))

        return normalized.unicodeScalars.reduce(into: "") { result, scalar in
            if scalar == "\n" {
                if allowsNewlines {
                    result.unicodeScalars.append(scalar)
                }
            } else if !CharacterSet.controlCharacters.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
    }
}
