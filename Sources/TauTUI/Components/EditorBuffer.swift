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
        lines.joined(separator: "\n")
    }

    public mutating func setText(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.isEmpty { lines = [""] }
        cursorLine = lines.count - 1
        cursorCol = lines[cursorLine].count
    }

    // MARK: - Mutations

    public mutating func insertCharacter(_ character: String) {
        var line = lines[cursorLine]
        let index = line.index(line.startIndex, offsetBy: cursorCol)
        line.insert(contentsOf: character, at: index)
        lines[cursorLine] = line
        cursorCol += character.count
    }

    public mutating func insertNewLine() {
        let line = lines[cursorLine]
        let index = line.index(line.startIndex, offsetBy: cursorCol)
        let before = String(line[..<index])
        let after = String(line[index...])
        lines[cursorLine] = before
        lines.insert(after, at: cursorLine + 1)
        cursorLine += 1
        cursorCol = 0
    }

    public mutating func backspace() {
        if cursorCol > 0 {
            var line = lines[cursorLine]
            let index = line.index(line.startIndex, offsetBy: cursorCol - 1)
            line.remove(at: index)
            lines[cursorLine] = line
            cursorCol -= 1
        } else if cursorLine > 0 {
            let current = lines.remove(at: cursorLine)
            cursorLine -= 1
            cursorCol = lines[cursorLine].count
            lines[cursorLine] += current
        }
    }

    public mutating func deleteForward() {
        var line = lines[cursorLine]
        guard cursorCol < line.count else {
            if cursorLine < lines.count - 1 {
                line += lines.remove(at: cursorLine + 1)
                lines[cursorLine] = line
            }
            return
        }
        let index = line.index(line.startIndex, offsetBy: cursorCol)
        line.remove(at: index)
        lines[cursorLine] = line
    }

    public mutating func deleteWordForward(isBoundary: (Character) -> Bool) {
        var line = lines[cursorLine]
        guard cursorCol < line.count else {
            if cursorLine < lines.count - 1 {
                line += lines.remove(at: cursorLine + 1)
                lines[cursorLine] = line
            }
            return
        }

        var deleteTo = cursorCol
        while deleteTo < line.count {
            let ch = line[line.index(line.startIndex, offsetBy: deleteTo)]
            if isBoundary(ch) { deleteTo += 1 } else { break }
        }
        while deleteTo < line.count {
            let ch = line[line.index(line.startIndex, offsetBy: deleteTo)]
            if isBoundary(ch) { break }
            deleteTo += 1
        }

        let start = line.index(line.startIndex, offsetBy: cursorCol)
        let end = line.index(line.startIndex, offsetBy: deleteTo)
        line.removeSubrange(start..<end)
        lines[cursorLine] = line
    }

    public mutating func deleteToStartOfLine() {
        let line = lines[cursorLine]
        let index = line.index(line.startIndex, offsetBy: cursorCol)
        lines[cursorLine] = String(line[index...])
        cursorCol = 0
    }

    public mutating func deleteToEndOfLine() {
        let line = lines[cursorLine]
        let index = line.index(line.startIndex, offsetBy: cursorCol)
        lines[cursorLine] = String(line[..<index])
    }

    public mutating func moveToLineStart() {
        cursorCol = 0
    }

    public mutating func moveToLineEnd() {
        cursorCol = lines[cursorLine].count
    }

    public mutating func deleteWordBackwards(isBoundary: (Character) -> Bool) {
        var line = lines[cursorLine]
        guard !line.isEmpty, cursorCol > 0 else {
            backspace()
            return
        }
        var deleteFrom = cursorCol
        while deleteFrom > 0 {
            let prevIndex = line.index(line.startIndex, offsetBy: deleteFrom - 1)
            let ch = line[prevIndex]
            if isBoundary(ch) { break }
            deleteFrom -= 1
        }
        let start = line.index(line.startIndex, offsetBy: deleteFrom)
        let end = line.index(line.startIndex, offsetBy: cursorCol)
        line.removeSubrange(start..<end)
        lines[cursorLine] = line
        cursorCol = deleteFrom
    }

    public mutating func moveCursor(lineDelta: Int, columnDelta: Int) {
        let newLine = min(max(cursorLine + lineDelta, 0), lines.count - 1)
        let targetLine = lines[newLine]
        let newCol = min(max(cursorCol + columnDelta, 0), targetLine.count)
        cursorLine = newLine
        cursorCol = newCol
    }

    public mutating func moveByWord(_ direction: Int, isBoundary: (Character) -> Bool) {
        guard direction != 0 else { return }
        let line = lines[cursorLine]
        var idx = cursorCol
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
        cursorCol = max(0, min(line.count, idx))
    }
}
