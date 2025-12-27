import Foundation

struct EditorLayoutLine: Sendable {
    let text: String
    let hasCursor: Bool
    let cursorPos: Int?
}

struct EditorVisualLine: Sendable {
    let logicalLine: Int
    let startCol: Int
    let length: Int
}

enum EditorLayoutEngine {
    static func renderContent(lines: [String], cursorLine: Int, cursorCol: Int, width: Int) -> [String] {
        let layout = self.layoutText(lines: lines, cursorLine: cursorLine, cursorCol: cursorCol, contentWidth: width)
        return layout.map { self.renderLayoutLine($0, width: width) }
    }

    static func layoutText(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        contentWidth: Int) -> [EditorLayoutLine]
    {
        guard contentWidth > 0 else { return [] }

        if lines.isEmpty || (lines.count == 1 && lines[0].isEmpty) {
            return [
                EditorLayoutLine(text: "", hasCursor: true, cursorPos: 0),
            ]
        }

        var layoutLines: [EditorLayoutLine] = []
        for logicalLineIndex in 0..<lines.count {
            let line = lines[logicalLineIndex]
            let isCurrentLine = logicalLineIndex == cursorLine

            if VisibleWidth.measure(line) <= contentWidth {
                if isCurrentLine {
                    layoutLines.append(
                        EditorLayoutLine(
                            text: line,
                            hasCursor: true,
                            cursorPos: cursorCol))
                } else {
                    layoutLines.append(EditorLayoutLine(text: line, hasCursor: false, cursorPos: nil))
                }
                continue
            }

            let chunks = self.chunkLogicalLine(line, width: contentWidth)
            for (chunkIndex, chunk) in chunks.enumerated() {
                let isLastChunk = chunkIndex == chunks.count - 1
                let hasCursorInChunk = isCurrentLine
                    && cursorCol >= chunk.startCol
                    && (isLastChunk ? cursorCol <= chunk.endCol : cursorCol < chunk.endCol)

                if hasCursorInChunk {
                    layoutLines.append(
                        EditorLayoutLine(
                            text: chunk.text,
                            hasCursor: true,
                            cursorPos: cursorCol - chunk.startCol))
                } else {
                    layoutLines.append(EditorLayoutLine(text: chunk.text, hasCursor: false, cursorPos: nil))
                }
            }
        }

        return layoutLines
    }

    static func buildVisualLineMap(lines: [String], width: Int) -> [EditorVisualLine] {
        guard width > 0 else { return [] }
        var visualLines: [EditorVisualLine] = []

        for logicalLineIndex in 0..<lines.count {
            let line = lines[logicalLineIndex]
            let chunks = self.chunkLogicalLine(line, width: width)
            if chunks.isEmpty {
                visualLines.append(.init(logicalLine: logicalLineIndex, startCol: 0, length: 0))
                continue
            }
            for chunk in chunks {
                visualLines.append(.init(
                    logicalLine: logicalLineIndex,
                    startCol: chunk.startCol,
                    length: max(0, chunk.endCol - chunk.startCol)))
            }
        }

        return visualLines
    }

    static func findCurrentVisualLine(visualLines: [EditorVisualLine], cursorLine: Int, cursorCol: Int) -> Int {
        guard !visualLines.isEmpty else { return 0 }
        for i in 0..<visualLines.count {
            let vl = visualLines[i]
            guard vl.logicalLine == cursorLine else { continue }

            let colInSegment = cursorCol - vl.startCol
            let isLastSegmentOfLine = (i == visualLines.count - 1) || (visualLines[i + 1].logicalLine != vl.logicalLine)

            if colInSegment >= 0 && (colInSegment < vl.length || (isLastSegmentOfLine && colInSegment <= vl.length)) {
                return i
            }
        }
        return visualLines.count - 1
    }

    static func isOnFirstVisualLine(lines: [String], width: Int, cursorLine: Int, cursorCol: Int) -> Bool {
        let visualLines = self.buildVisualLineMap(lines: lines, width: width)
        let current = self.findCurrentVisualLine(visualLines: visualLines, cursorLine: cursorLine, cursorCol: cursorCol)
        return current == 0
    }

    static func isOnLastVisualLine(lines: [String], width: Int, cursorLine: Int, cursorCol: Int) -> Bool {
        let visualLines = self.buildVisualLineMap(lines: lines, width: width)
        let current = self.findCurrentVisualLine(visualLines: visualLines, cursorLine: cursorLine, cursorCol: cursorCol)
        return current == max(visualLines.count - 1, 0)
    }

    static func moveCursorVertically(
        lines: [String],
        width: Int,
        cursorLine: Int,
        cursorCol: Int,
        deltaLine: Int) -> (line: Int, col: Int)
    {
        guard deltaLine != 0 else { return (cursorLine, cursorCol) }

        let visualLines = self.buildVisualLineMap(lines: lines, width: width)
        if visualLines.isEmpty { return (cursorLine, cursorCol) }

        let currentVisualLine = self.findCurrentVisualLine(
            visualLines: visualLines,
            cursorLine: cursorLine,
            cursorCol: cursorCol)
        let currentVL = visualLines[currentVisualLine]
        let visualCol = cursorCol - currentVL.startCol

        let targetVisualLine = currentVisualLine + deltaLine
        guard targetVisualLine >= 0, targetVisualLine < visualLines.count else { return (cursorLine, cursorCol) }

        let targetVL = visualLines[targetVisualLine]
        let logicalLine = lines[targetVL.logicalLine]
        let targetCol = targetVL.startCol + min(max(visualCol, 0), targetVL.length)
        return (line: targetVL.logicalLine, col: min(targetCol, logicalLine.count))
    }

    static func moveCursorHorizontally(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        deltaCol: Int) -> (line: Int, col: Int)
    {
        guard deltaCol != 0 else { return (cursorLine, cursorCol) }
        guard !lines.isEmpty else { return (0, 0) }

        var line = cursorLine
        var col = cursorCol

        if deltaCol > 0 {
            let current = lines[line]
            if col < current.count {
                col += 1
            } else if line < lines.count - 1 {
                line += 1
                col = 0
            }
        } else {
            if col > 0 {
                col -= 1
            } else if line > 0 {
                line -= 1
                col = lines[line].count
            }
        }

        return (line: line, col: col)
    }

    // MARK: - Helpers

    private struct Chunk {
        let text: String
        let startCol: Int
        let endCol: Int
    }

    private static func chunkLogicalLine(_ line: String, width: Int) -> [Chunk] {
        guard width > 0 else { return [] }
        if line.isEmpty {
            return [Chunk(text: "", startCol: 0, endCol: 0)]
        }

        if VisibleWidth.measure(line) <= width {
            return [Chunk(text: line, startCol: 0, endCol: line.count)]
        }

        var chunks: [Chunk] = []
        var current = ""
        var currentWidth = 0
        var chunkStartCol = 0
        var currentIndex = 0

        for ch in line {
            let chWidth = VisibleWidth.measure(String(ch))
            if currentWidth + chWidth > width, !current.isEmpty {
                chunks.append(.init(text: current, startCol: chunkStartCol, endCol: currentIndex))
                current = String(ch)
                currentWidth = chWidth
                chunkStartCol = currentIndex
            } else {
                current.append(ch)
                currentWidth += chWidth
            }
            currentIndex += 1
        }

        if !current.isEmpty {
            chunks.append(.init(text: current, startCol: chunkStartCol, endCol: currentIndex))
        }

        return chunks
    }

    private static func renderLayoutLine(_ layoutLine: EditorLayoutLine, width: Int) -> String {
        var displayText = layoutLine.text
        var lineVisibleWidth = VisibleWidth.measure(displayText)

        if layoutLine.hasCursor, let cursorPos = layoutLine.cursorPos {
            let before = displayText.prefixCharacters(cursorPos)
            let after = displayText.dropCharacters(cursorPos)

            if let first = after.first {
                let rest = String(after.dropFirst())
                let cursor = "\u{001B}[7m\(first)\u{001B}[0m"
                displayText = before + cursor + rest
            } else {
                if lineVisibleWidth < width {
                    displayText = before + "\u{001B}[7m \u{001B}[0m"
                    lineVisibleWidth += 1
                } else {
                    if let last = before.last {
                        let beforeWithoutLast = String(before.dropLast())
                        displayText = beforeWithoutLast + "\u{001B}[7m\(last)\u{001B}[0m"
                    }
                }
            }
        }

        let padding = String(repeating: " ", count: max(0, width - VisibleWidth.measure(displayText)))
        return displayText + padding
    }
}

private extension String {
    func prefixCharacters(_ count: Int) -> String {
        guard count > 0 else { return "" }
        let idx = self.index(self.startIndex, offsetBy: min(count, self.count))
        return String(self[..<idx])
    }

    func dropCharacters(_ count: Int) -> String {
        guard count > 0 else { return self }
        let idx = self.index(self.startIndex, offsetBy: min(count, self.count))
        return String(self[idx...])
    }
}
