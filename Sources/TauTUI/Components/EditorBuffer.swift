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

        var deleteTo = self.cursorCol
        while deleteTo < line.count {
            let ch = line[line.index(line.startIndex, offsetBy: deleteTo)]
            if isBoundary(ch) { deleteTo += 1 } else { break }
        }
        while deleteTo < line.count {
            let ch = line[line.index(line.startIndex, offsetBy: deleteTo)]
            if isBoundary(ch) { break }
            deleteTo += 1
        }

        let start = line.index(line.startIndex, offsetBy: self.cursorCol)
        let end = line.index(line.startIndex, offsetBy: deleteTo)
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
        var deleteFrom = self.cursorCol
        while deleteFrom > 0 {
            let prevIndex = line.index(line.startIndex, offsetBy: deleteFrom - 1)
            let ch = line[prevIndex]
            if isBoundary(ch) { break }
            deleteFrom -= 1
        }
        let start = line.index(line.startIndex, offsetBy: deleteFrom)
        let end = line.index(line.startIndex, offsetBy: self.cursorCol)
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
        let line = self.lines[self.cursorLine]
        var idx = self.cursorCol
        if direction > 0 {
            while idx < line.count {
                let ch = line[line.index(line.startIndex, offsetBy: idx)]
                if isBoundary(ch) { idx += 1 } else { break }
            }
            while idx < line.count {
                let ch = line[line.index(line.startIndex, offsetBy: idx)]
                if isBoundary(ch) { break }
                idx += 1
            }
        } else {
            while idx > 0 {
                let ch = line[line.index(line.startIndex, offsetBy: idx - 1)]
                if isBoundary(ch) { idx -= 1 } else { break }
            }
            while idx > 0 {
                let ch = line[line.index(line.startIndex, offsetBy: idx - 1)]
                if isBoundary(ch) { break }
                idx -= 1
            }
        }
        self.cursorCol = max(0, min(line.count, idx))
    }
}
