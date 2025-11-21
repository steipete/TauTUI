import Foundation

/// ANSI-aware wrapping utilities mirroring pi-tui v0.8.0 behavior.
public enum AnsiWrapping {
    /// Word-wrap text while preserving ANSI escape sequences and surrogate pairs.
    /// Tabs are normalized to three spaces to match pi-tui.
    public static func wrapText(_ text: String, width: Int, tabSize: Int = 3) -> [String] {
        guard width > 0 else { return [""] }
        let normalized = Ansi.normalizeTabs(text, spacesPerTab: tabSize)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.flatMap { self.wrapSingleLine(String($0), width: width) }
    }

    /// Apply a background style to the line and pad to the given width, preserving ANSI resets.
    public static func applyBackgroundToLine(_ line: String, width: Int, background: AnsiStyling.Background) -> String {
        let visibleLen = VisibleWidth.measure(line)
        let paddingNeeded = max(0, width - visibleLen)
        let padded = line + String(repeating: " ", count: paddingNeeded)
        return background.apply(padded)
    }

    // MARK: - Implementation details

    private static func wrapSingleLine(_ line: String, width: Int) -> [String] {
        if line.isEmpty { return [""] }
        if VisibleWidth.measure(line) <= width { return [line] }

        var result: [String] = []
        var tracker = AnsiCodeTracker()

        let words = splitIntoWordsWithAnsi(line)
        var current = ""
        var currentVisible = 0

        for word in words {
            let wordVisible = VisibleWidth.measure(word)

            if wordVisible > width {
                // Flush current line before breaking long word
                if !current.isEmpty {
                    result.append(closeLine(current, tracker: tracker))
                    current = tracker.activeCodes
                    currentVisible = 0
                }

                let broken = breakLongWord(word, width: width, tracker: &tracker)
                // All but last are complete lines
                if broken.count > 1 {
                    result.append(contentsOf: broken.dropLast().map { closeLine($0, tracker: tracker) })
                }
                if let last = broken.last {
                    current = last
                    currentVisible = VisibleWidth.measure(last)
                }
                continue
            }

            let needsSpace = currentVisible > 0 ? 1 : 0
            if currentVisible + needsSpace + wordVisible > width {
                result.append(closeLine(current, tracker: tracker))
                current = tracker.activeCodes + word
                currentVisible = wordVisible
            } else {
                if needsSpace > 0 {
                    current.append(" ")
                    currentVisible += 1
                }
                current.append(word)
                currentVisible += wordVisible
            }

            tracker.processAnsi(in: word)
        }

        if !current.isEmpty {
            result.append(closeLine(current, tracker: tracker))
        }

        return result.isEmpty ? [""] : result
    }

    private static func breakLongWord(_ word: String, width: Int, tracker: inout AnsiCodeTracker) -> [String] {
        var lines: [String] = []
        var current = tracker.activeCodes
        var currentVisible = 0

        var index = word.startIndex
        while index < word.endIndex {
            if let ansi = extractAnsi(from: word, startingAt: index) {
                current.append(ansi.code)
                tracker.process(ansi.code)
                index = ansi.next
                continue
            }

            let char = String(word[index])
            let charWidth = VisibleWidth.measure(char)
            if currentVisible + charWidth > width {
                lines.append(closeLine(current, tracker: tracker))
                current = tracker.activeCodes
                currentVisible = 0
            }
            current.append(char)
            currentVisible += charWidth
            index = word.index(after: index)
        }

        if !current.isEmpty || lines.isEmpty {
            lines.append(current)
        }

        return lines
    }

    private static func closeLine(_ line: String, tracker: AnsiCodeTracker) -> String {
        guard tracker.hasActiveCodes else { return line }
        return line + tracker.resetCode
    }

    private static func splitIntoWordsWithAnsi(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let ansi = extractAnsi(from: text, startingAt: index) {
                current.append(ansi.code)
                index = ansi.next
                continue
            }

            let ch = text[index]
            if ch == " " {
                if !current.isEmpty {
                    words.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                index = text.index(after: index)
                continue
            }

            current.append(ch)
            index = text.index(after: index)
        }

        if !current.isEmpty {
            words.append(current)
        }

        return words
    }

    static func extractAnsi(from text: String, startingAt index: String.Index) -> (code: String, next: String.Index)? {
        guard text[index] == "\u{001B}", text.index(after: index) < text.endIndex else { return nil }
        var current = text.index(after: index)
        while current < text.endIndex {
            let scalar = text[current].unicodeScalars.first!.value
            if scalar >= 0x40 && scalar <= 0x7E { // final byte of CSI / SGR
                let next = text.index(after: current)
                return (String(text[index..<next]), next)
            }
            current = text.index(after: current)
        }
        return nil
    }
}

private struct AnsiCodeTracker {
    private(set) var activeCodes: String = ""
    var hasActiveCodes: Bool { !self.activeCodes.isEmpty }
    let resetCode = "\u{001B}[0m"

    mutating func process(_ ansi: String) {
        guard ansi.hasSuffix("m") else { return }
        if ansi == "\u{001B}[0m" || ansi == "\u{001B}[m" {
            self.activeCodes = ""
        } else {
            self.activeCodes.append(ansi)
        }
    }

    mutating func processAnsi(in text: String) {
        var index = text.startIndex
        while index < text.endIndex {
            if let ansi = AnsiWrapping.extractAnsi(from: text, startingAt: index) {
                self.process(ansi.code)
                index = ansi.next
            } else {
                index = text.index(after: index)
            }
        }
    }
}
