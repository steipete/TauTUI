/// Pure, Sendable text buffer backing the `Editor` component.
/// Encapsulates cursor state and text mutations so UI/render logic can stay
/// in `Editor` while logic is exhaustively testable.
public struct EditorBuffer: Sendable {
    public internal(set) var lines: [String]
    public internal(set) var cursorLine: Int
    public internal(set) var cursorCol: Int

    public init() {
        self.lines = [""]
        self.cursorLine = 0
        self.cursorCol = 0
    }

    // MARK: - Accessors

    public var text: String {
        self.lines.joined(separator: "\n")
    }

    public mutating func setText(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if self.lines.isEmpty { self.lines = [""] }
        self.cursorLine = self.lines.count - 1
        self.cursorCol = self.lines[self.cursorLine].count
    }

    // MARK: - Mutations

    public mutating func insertCharacter(_ character: String) {
        var line = self.lines[self.cursorLine]
        let index = line.index(line.startIndex, offsetBy: self.cursorCol)
        line.insert(contentsOf: character, at: index)
        self.lines[self.cursorLine] = line
        self.cursorCol += character.count
    }

    public mutating func insertNewLine() {
        let line = self.lines[self.cursorLine]
        let index = line.index(line.startIndex, offsetBy: self.cursorCol)
        let before = String(line[..<index])
        let after = String(line[index...])
        self.lines[self.cursorLine] = before
        self.lines.insert(after, at: self.cursorLine + 1)
        self.cursorLine += 1
        self.cursorCol = 0
    }

    public mutating func backspace() {
        if self.cursorCol > 0 {
            var line = self.lines[self.cursorLine]
            let index = line.index(line.startIndex, offsetBy: self.cursorCol - 1)
            line.remove(at: index)
            self.lines[self.cursorLine] = line
            self.cursorCol -= 1
        } else if self.cursorLine > 0 {
            let current = self.lines.remove(at: self.cursorLine)
            self.cursorLine -= 1
            self.cursorCol = self.lines[self.cursorLine].count
            self.lines[self.cursorLine] += current
        }
    }

    public mutating func deleteForward() {
        var line = self.lines[self.cursorLine]
        guard self.cursorCol < line.count else {
            if self.cursorLine < self.lines.count - 1 {
                line += self.lines.remove(at: self.cursorLine + 1)
                self.lines[self.cursorLine] = line
            }
            return
        }
        let index = line.index(line.startIndex, offsetBy: self.cursorCol)
        line.remove(at: index)
        self.lines[self.cursorLine] = line
    }

    public mutating func deleteWordForward(isBoundary: (Character) -> Bool) {
        var line = self.lines[self.cursorLine]
        guard self.cursorCol < line.count else {
            if self.cursorLine < self.lines.count - 1 {
                line += self.lines.remove(at: self.cursorLine + 1)
                self.lines[self.cursorLine] = line
            }
            return
        }

        let oldCursorCol = self.cursorCol
        var tmp = self
        tmp.moveByWord(1, isBoundary: isBoundary)
        let deleteTo = tmp.cursorLine == self.cursorLine ? tmp.cursorCol : line.count

        let start = line.index(line.startIndex, offsetBy: oldCursorCol)
        let end = line.index(line.startIndex, offsetBy: min(deleteTo, line.count))
        line.removeSubrange(start..<end)
        self.lines[self.cursorLine] = line
    }

    public mutating func deleteToStartOfLine() {
        let line = self.lines[self.cursorLine]
        let index = line.index(line.startIndex, offsetBy: self.cursorCol)
        self.lines[self.cursorLine] = String(line[index...])
        self.cursorCol = 0
    }

    public mutating func deleteToEndOfLine() {
        let line = self.lines[self.cursorLine]
        let index = line.index(line.startIndex, offsetBy: self.cursorCol)
        self.lines[self.cursorLine] = String(line[..<index])
    }

    public mutating func moveToLineStart() {
        self.cursorCol = 0
    }

    public mutating func moveToLineEnd() {
        self.cursorCol = self.lines[self.cursorLine].count
    }

    public mutating func deleteWordBackwards(isBoundary: (Character) -> Bool) {
        var line = self.lines[self.cursorLine]
        guard !line.isEmpty, self.cursorCol > 0 else {
            self.backspace()
            return
        }

        let oldCursorCol = self.cursorCol
        var tmp = self
        tmp.moveByWord(-1, isBoundary: isBoundary)
        let deleteFrom = tmp.cursorLine == self.cursorLine ? tmp.cursorCol : 0
        self.cursorCol = oldCursorCol

        let start = line.index(line.startIndex, offsetBy: deleteFrom)
        let end = line.index(line.startIndex, offsetBy: oldCursorCol)
        line.removeSubrange(start..<end)
        self.lines[self.cursorLine] = line
        self.cursorCol = deleteFrom
    }

    public mutating func moveCursor(lineDelta: Int, columnDelta: Int) {
        let newLine = min(max(cursorLine + lineDelta, 0), self.lines.count - 1)
        let targetLine = self.lines[newLine]
        let newCol = min(max(cursorCol + columnDelta, 0), targetLine.count)
        self.cursorLine = newLine
        self.cursorCol = newCol
    }

    public mutating func moveByWord(_ direction: Int, isBoundary: (Character) -> Bool) {
        guard direction != 0 else { return }

        if direction < 0, self.cursorCol == 0 {
            if self.cursorLine > 0 {
                self.cursorLine -= 1
                self.cursorCol = self.lines[self.cursorLine].count
            }
            return
        }

        let currentLine = self.lines[self.cursorLine]
        let chars = Array(currentLine)

        if direction > 0, self.cursorCol >= chars.count {
            if self.cursorLine < self.lines.count - 1 {
                self.cursorLine += 1
                self.cursorCol = 0
            }
            return
        }

        var idx = self.cursorCol
        if direction > 0 {
            while idx < chars.count, chars[idx].isWhitespace {
                idx += 1
            }

            if idx < chars.count {
                let isPunctuation = isBoundary(chars[idx]) && !chars[idx].isWhitespace
                if isPunctuation {
                    while idx < chars.count, isBoundary(chars[idx]), !chars[idx].isWhitespace {
                        idx += 1
                    }
                } else {
                    while idx < chars.count, !chars[idx].isWhitespace,
                          !(isBoundary(chars[idx]) && !chars[idx].isWhitespace)
                    {
                        idx += 1
                    }
                }
            }
        } else {
            while idx > 0, chars[idx - 1].isWhitespace {
                idx -= 1
            }

            if idx > 0 {
                let isPunctuation = isBoundary(chars[idx - 1]) && !chars[idx - 1].isWhitespace
                if isPunctuation {
                    while idx > 0, isBoundary(chars[idx - 1]), !chars[idx - 1].isWhitespace {
                        idx -= 1
                    }
                } else {
                    while idx > 0, !chars[idx - 1].isWhitespace,
                          !(isBoundary(chars[idx - 1]) && !chars[idx - 1].isWhitespace)
                    {
                        idx -= 1
                    }
                }
            }
        }

        self.cursorCol = max(0, min(chars.count, idx))
    }
}
