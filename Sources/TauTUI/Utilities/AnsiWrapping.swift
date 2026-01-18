import Foundation

/// ANSI-aware wrapping utilities mirroring pi-tui v0.8.0 behavior.
public enum AnsiWrapping {
    /// Wrap text while preserving ANSI escape sequences.
    /// Mirrors pi-mono `wrapTextWithAnsi` (word-wrapping, no padding).
    /// Tabs are normalized to three spaces to match pi-tui.
    public static func wrapText(_ text: String, width: Int, tabSize: Int = 3) -> [String] {
        guard width > 0 else { return [""] }
        guard !text.isEmpty else { return [""] }

        let normalized = Ansi.normalizeTabs(text, spacesPerTab: tabSize)
        let inputLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var result: [String] = []
        let tracker = AnsiCodeTracker()

        for inputLine in inputLines {
            let prefix = result.isEmpty ? "" : tracker.getActiveCodes()
            result.append(contentsOf: self.wrapSingleLine(prefix + inputLine, width: width))
            tracker.updateFromText(inputLine)
        }

        return result.isEmpty ? [""] : result
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
        guard !line.isEmpty else { return [""] }
        if VisibleWidth.measure(line) <= width { return [line] }

        var wrapped: [String] = []
        let tracker = AnsiCodeTracker()
        let tokens = self.splitIntoTokensWithAnsi(line)

        var currentLine = ""
        var currentVisibleLength = 0

        for token in tokens {
            let tokenVisibleLength = VisibleWidth.measure(token)
            let isWhitespace = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if tokenVisibleLength > width, !isWhitespace {
                if !currentLine.isEmpty {
                    if let lineEndReset = tracker.getLineEndReset(), !lineEndReset.isEmpty {
                        currentLine += lineEndReset
                    }
                    wrapped.append(currentLine)
                    currentLine.removeAll(keepingCapacity: true)
                    currentVisibleLength = 0
                }

                let broken = self.breakLongWord(token, width: width, tracker: tracker)
                if broken.count > 1 {
                    wrapped.append(contentsOf: broken.dropLast())
                }
                currentLine = broken.last ?? ""
                currentVisibleLength = VisibleWidth.measure(currentLine)
                continue
            }

            let totalNeeded = currentVisibleLength + tokenVisibleLength
            if totalNeeded > width, currentVisibleLength > 0 {
                var lineToWrap = currentLine.rstripSpaces()
                if let lineEndReset = tracker.getLineEndReset(), !lineEndReset.isEmpty {
                    lineToWrap += lineEndReset
                }
                wrapped.append(lineToWrap)

                if isWhitespace {
                    currentLine = tracker.getActiveCodes()
                    currentVisibleLength = 0
                } else {
                    currentLine = tracker.getActiveCodes() + token
                    currentVisibleLength = tokenVisibleLength
                }
            } else {
                currentLine += token
                currentVisibleLength += tokenVisibleLength
            }

            tracker.updateFromText(token)
        }

        if !currentLine.isEmpty {
            wrapped.append(currentLine)
        }

        return wrapped.isEmpty ? [""] : wrapped
    }

    private static func breakLongWord(_ word: String, width: Int, tracker: AnsiCodeTracker) -> [String] {
        var lines: [String] = []
        var currentLine = tracker.getActiveCodes()
        var currentWidth = 0

        var index = word.startIndex
        while index < word.endIndex {
            if let ansi = extractAnsi(from: word, startingAt: index) {
                currentLine += ansi.code
                tracker.process(ansi.code)
                index = ansi.next
                continue
            }

            let grapheme = String(word[index])
            let graphemeWidth = VisibleWidth.measure(grapheme)
            if currentWidth + graphemeWidth > width {
                if let lineEndReset = tracker.getLineEndReset(), !lineEndReset.isEmpty {
                    currentLine += lineEndReset
                }
                lines.append(currentLine)
                currentLine = tracker.getActiveCodes()
                currentWidth = 0
            }
            currentLine += grapheme
            currentWidth += graphemeWidth
            index = word.index(after: index)
        }

        if !currentLine.isEmpty || lines.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }

    private static func splitIntoTokensWithAnsi(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var pendingAnsi = ""
        var inWhitespace = false

        var index = text.startIndex
        while index < text.endIndex {
            if let ansi = extractAnsi(from: text, startingAt: index) {
                pendingAnsi += ansi.code
                index = ansi.next
                continue
            }

            let ch = text[index]
            let isSpace = ch == " "
            if isSpace != inWhitespace, !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }

            if !pendingAnsi.isEmpty {
                current += pendingAnsi
                pendingAnsi.removeAll(keepingCapacity: true)
            }

            inWhitespace = isSpace
            current.append(ch)
            index = text.index(after: index)
        }

        if !pendingAnsi.isEmpty {
            current += pendingAnsi
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    static func extractAnsi(from text: String, startingAt index: String.Index) -> (code: String, next: String.Index)? {
        // Mirrors pi-mono `extractAnsiCode`: only handle CSI sequences that start with ESC[,
        // and terminate on common final bytes used by the TUI renderer.
        guard text[index] == "\u{001B}" else { return nil }
        let afterEsc = text.index(after: index)
        guard afterEsc < text.endIndex, text[afterEsc] == "[" else { return nil }

        var current = text.index(after: afterEsc)
        while current < text.endIndex {
            let ch = text[current]
            if ch == "m" || ch == "G" || ch == "K" || ch == "H" || ch == "J" {
                let next = text.index(after: current)
                return (String(text[index..<next]), next)
            }
            current = text.index(after: current)
        }

        return nil
    }
}

private final class AnsiCodeTracker {
    private var bold = false
    private var dim = false
    private var italic = false
    private var underline = false
    private var blink = false
    private var inverse = false
    private var hidden = false
    private var strikethrough = false
    private var fgColor: String?
    private var bgColor: String?

    // swiftlint:disable cyclomatic_complexity
    func process(_ ansiCode: String) {
        guard ansiCode.hasSuffix("m") else { return }
        guard let start = ansiCode.range(of: "\u{001B}[")?.upperBound else { return }
        guard let end = ansiCode.lastIndex(of: "m"), end > start else { return }

        let params = String(ansiCode[start..<end])
        if params.isEmpty || params == "0" {
            self.reset()
            return
        }

        let parts = params.split(separator: ";").map(String.init)
        var i = 0
        while i < parts.count {
            let part = parts[i]
            let code = Int(part) ?? 0

            if code == 38 || code == 48 {
                if i + 2 < parts.count, parts[i + 1] == "5" {
                    let colorCode = "\(parts[i]);\(parts[i + 1]);\(parts[i + 2])"
                    if code == 38 { self.fgColor = colorCode } else { self.bgColor = colorCode }
                    i += 3
                    continue
                }
                if i + 4 < parts.count, parts[i + 1] == "2" {
                    let colorCode = "\(parts[i]);\(parts[i + 1]);\(parts[i + 2]);\(parts[i + 3]);\(parts[i + 4])"
                    if code == 38 { self.fgColor = colorCode } else { self.bgColor = colorCode }
                    i += 5
                    continue
                }
            }

            switch code {
            case 0:
                self.reset()
            case 1:
                self.bold = true
            case 2:
                self.dim = true
            case 3:
                self.italic = true
            case 4:
                self.underline = true
            case 5:
                self.blink = true
            case 7:
                self.inverse = true
            case 8:
                self.hidden = true
            case 9:
                self.strikethrough = true
            case 21:
                self.bold = false
            case 22:
                self.bold = false
                self.dim = false
            case 23:
                self.italic = false
            case 24:
                self.underline = false
            case 25:
                self.blink = false
            case 27:
                self.inverse = false
            case 28:
                self.hidden = false
            case 29:
                self.strikethrough = false
            case 39:
                self.fgColor = nil
            case 49:
                self.bgColor = nil
            default:
                if (code >= 30 && code <= 37) || (code >= 90 && code <= 97) {
                    self.fgColor = "\(code)"
                } else if (code >= 40 && code <= 47) || (code >= 100 && code <= 107) {
                    self.bgColor = "\(code)"
                }
            }

            i += 1
        }
    }

    // swiftlint:enable cyclomatic_complexity

    func updateFromText(_ text: String) {
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

    func getActiveCodes() -> String {
        var codes: [String] = []
        if self.bold { codes.append("1") }
        if self.dim { codes.append("2") }
        if self.italic { codes.append("3") }
        if self.underline { codes.append("4") }
        if self.blink { codes.append("5") }
        if self.inverse { codes.append("7") }
        if self.hidden { codes.append("8") }
        if self.strikethrough { codes.append("9") }
        if let fgColor { codes.append(fgColor) }
        if let bgColor { codes.append(bgColor) }
        if codes.isEmpty { return "" }
        return "\u{001B}[\(codes.joined(separator: ";"))m"
    }

    func getLineEndReset() -> String? {
        self.underline ? "\u{001B}[24m" : ""
    }

    private func reset() {
        self.bold = false
        self.dim = false
        self.italic = false
        self.underline = false
        self.blink = false
        self.inverse = false
        self.hidden = false
        self.strikethrough = false
        self.fgColor = nil
        self.bgColor = nil
    }
}

extension String {
    fileprivate func rstripSpaces() -> String {
        var end = self.endIndex
        while end > self.startIndex {
            let prev = self.index(before: end)
            if self[prev] == " " {
                end = prev
                continue
            }
            break
        }
        return String(self[..<end])
    }
}
