import Markdown

/// Renders Markdown content with ANSI styling similar to pi-tui.
public final class MarkdownComponent: Component {
    public struct Padding {
        public var horizontal: Int
        public var vertical: Int

        public init(horizontal: Int = 1, vertical: Int = 1) {
            self.horizontal = max(0, horizontal)
            self.vertical = max(0, vertical)
        }
    }

    public var text: String { didSet { self.invalidateCache() } }
    public var padding: Padding { didSet { self.invalidateCache() } }
    public var background: Text.Background? { didSet { self.invalidateCache() } }

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(text: String = "", padding: Padding = Padding(), background: Text.Background? = nil) {
        self.text = text
        self.padding = padding
        self.background = background
    }

    public func render(width: Int) -> [String] {
        if let cachedWidth, cachedWidth == width, let cachedLines { return cachedLines }
        guard width > 0 else { self.cache(width: width, lines: []); return [] }

        let contentWidth = max(1, width - self.padding.horizontal * 2)
        let renderer = Renderer(maxWidth: contentWidth)
        let document = Document(parsing: text)
        document.children.forEach { renderer.visit($0) }

        let leftPad = String(repeating: " ", count: padding.horizontal)
        let emptyLine = String(repeating: " ", count: width)
        var result: [String] = []

        for _ in 0..<self.padding.vertical {
            result.append(self.applyBackground(to: emptyLine))
        }
        for line in renderer.lines {
            let visible = VisibleWidth.measure(line)
            let right = max(0, width - self.padding.horizontal - visible)
            let padded = leftPad + line + String(repeating: " ", count: right)
            result.append(self.applyBackground(to: padded))
        }
        for _ in 0..<self.padding.vertical {
            result.append(self.applyBackground(to: emptyLine))
        }

        self.cache(width: width, lines: result)
        return result
    }

    private func applyBackground(to line: String) -> String {
        guard let background else { return line }
        return background.ansiPrefix + line + "\u{001B}[0m"
    }

    private func invalidateCache() {
        self.cachedWidth = nil
        self.cachedLines = nil
    }

    private func cache(width: Int, lines: [String]) {
        self.cachedWidth = width
        self.cachedLines = lines
    }
}

private final class Renderer {
    let maxWidth: Int
    var lines: [String] = []
    private var listDepth: Int = 0

    init(maxWidth: Int) {
        self.maxWidth = max(1, maxWidth)
    }

    func visit(_ markup: Markup) {
        switch markup {
        case let heading as Heading:
            self.renderHeading(heading)
        case let paragraph as Paragraph:
            self.renderParagraph(paragraph)
        case let list as UnorderedList:
            self.listDepth += 1
            self.renderListItems(Array(list.listItems), ordered: false)
            self.listDepth -= 1
        case let list as OrderedList:
            self.listDepth += 1
            self.renderListItems(Array(list.listItems), ordered: true)
            self.listDepth -= 1
        case let blockQuote as BlockQuote:
            self.renderBlockQuote(blockQuote)
        case let code as CodeBlock:
            self.renderCodeBlock(code)
        case let thematic as ThematicBreak:
            self.renderThematicBreak(thematic)
        case let table as Table:
            self.renderTable(table)
        case let html as HTMLBlock:
            self.wrap(line: html.rawHTML)
        default:
            markup.children.forEach { self.visit($0) }
        }
    }

    private func renderHeading(_ heading: Heading) {
        let text = self.renderInline(heading.inlineChildren)
        let decorated = switch heading.level {
        case 1:
            "\u{001B}[1;4;33m\(text)\u{001B}[0m"
        case 2:
            "\u{001B}[1;33m\(text)\u{001B}[0m"
        default:
            "\u{001B}[1m\(String(repeating: "#", count: heading.level)) \(text)\u{001B}[0m"
        }
        self.wrap(line: decorated)
        self.lines.append("")
    }

    private func renderParagraph(_ paragraph: Paragraph) {
        self.wrap(line: self.renderInline(paragraph.inlineChildren))
        self.lines.append("")
    }

    private func renderListItems(_ items: [ListItem], ordered: Bool) {
        let indentPrefix = String(repeating: "  ", count: max(listDepth - 1, 0))
        for (index, item) in items.enumerated() {
            let bullet = indentPrefix + (ordered ? "\(index + 1). " : "- ")
            let children = Array(item.children)
            if let firstChild = children.first {
                if let paragraph = firstChild as? Paragraph {
                    let inline = self.renderInline(paragraph.inlineChildren)
                    self.wrap(line: "\u{001B}[36m\(bullet)\u{001B}[0m\(inline)")
                } else {
                    self.wrap(line: bullet + firstChild.format())
                }
                if children.count > 1 {
                    children.dropFirst().forEach { self.visit($0) }
                }
            } else {
                self.wrap(line: bullet)
            }
        }
        self.lines.append("")
    }

    private func renderBlockQuote(_ quote: BlockQuote) {
        let innerRenderer = Renderer(maxWidth: max(maxWidth - 2, 1))
        quote.children.forEach { innerRenderer.visit($0) }
        for line in innerRenderer.lines {
            self.lines.append("\u{001B}[90m│ \u{001B}[3m\(line)\u{001B}[0m")
        }
        self.lines.append("")
    }

    private func renderCodeBlock(_ code: CodeBlock) {
        self.lines.append("\u{001B}[90m```\(code.language ?? "")\u{001B}[0m")
        for line in code.code.split(separator: "\n", omittingEmptySubsequences: false) {
            self.lines.append("\u{001B}[2m  \u{001B}[0m\u{001B}[32m\(line)\u{001B}[0m")
        }
        self.lines.append("\u{001B}[90m```\u{001B}[0m")
        self.lines.append("")
    }

    private func renderThematicBreak(_ breakNode: ThematicBreak) {
        let width = min(maxWidth, 80)
        self.lines.append("\u{001B}[90m\(String(repeating: "─", count: width))\u{001B}[0m")
        self.lines.append("")
    }

    private func renderTable(_ table: Table) {
        let columnCount = table.columnAlignments.count
        var widths = Array(repeating: 0, count: max(columnCount, 1))
        let alignments = table.columnAlignments

        func measure(cells: [Table.Cell]) {
            for (index, cell) in cells.enumerated() {
                guard index < widths.count else { continue }
                let text = self.renderInline(cell.inlineChildren)
                widths[index] = min(max(widths[index], VisibleWidth.measure(text)), self.maxWidth)
            }
        }

        measure(cells: Array(table.head.cells))
        table.body.rows.forEach { measure(cells: Array($0.cells)) }

        func renderRow(cells: [Table.Cell]) {
            var line = "│ "
            for (index, cell) in cells.enumerated() {
                guard index < widths.count else { continue }
                let text = self.renderInline(cell.inlineChildren)
                let vis = VisibleWidth.measure(text)
                let padding = max(0, widths[index] - vis)
                let alignment: Table.ColumnAlignment = if index < alignments.count {
                    alignments[index] ?? .left
                } else {
                    .left
                }

                let (leftPad, rightPad): (Int, Int)
                switch alignment {
                case .center:
                    leftPad = padding / 2
                    rightPad = padding - leftPad
                case .right:
                    leftPad = padding
                    rightPad = 0
                default:
                    leftPad = 0
                    rightPad = padding
                }

                line += String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
                line += index == widths.count - 1 ? " │" : " │ "
            }
            self.lines.append(line)
        }

        renderRow(cells: Array(table.head.cells))
        let separators = widths.map { String(repeating: "─", count: max(1, $0)) }
        self.lines.append("├─" + separators.joined(separator: "─┼─") + "─┤")
        table.body.rows.forEach { renderRow(cells: Array($0.cells)) }
        self.lines.append("")
    }

    private func renderInline(_ children: LazyMapSequence<MarkupChildren, InlineMarkup>) -> String {
        self.renderInlineSequence(children)
    }

    private func renderInlineSequence(_ sequence: some Sequence<InlineMarkup>) -> String {
        var result = ""
        for child in sequence {
            switch child {
            case let text as Markdown.Text:
                result += text.string
            case let strong as Strong:
                result += "\u{001B}[1m\(self.renderInlineSequence(strong.inlineChildren))\u{001B}[0m"
            case let emphasis as Emphasis:
                result += "\u{001B}[3m\(self.renderInlineSequence(emphasis.inlineChildren))\u{001B}[0m"
            case let code as InlineCode:
                result += "\u{001B}[90m`\u{001B}[36m\(code.code)\u{001B}[90m`\u{001B}[0m"
            case let link as Link:
                let label = self.renderInlineSequence(link.inlineChildren)
                result += "\u{001B}[4;34m\(label)\u{001B}[90m (\(link.destination ?? ""))\u{001B}[0m"
            case _ as SoftBreak:
                result += " "
            case _ as LineBreak:
                result += "\n"
            default:
                result += child.format()
            }
        }
        return result
    }

    private func wrap(line: String) {
        for segment in line.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in segment.split(separator: " ", omittingEmptySubsequences: false) {
                let wordString = String(word)
                if wordString.isEmpty {
                    current += " "
                    continue
                }
                if current.isEmpty {
                    if VisibleWidth.measure(wordString) <= self.maxWidth {
                        current = wordString
                    } else {
                        self.lines.append(contentsOf: self.breakLongWord(wordString))
                    }
                    continue
                }
                let candidate = current + " " + wordString
                if VisibleWidth.measure(candidate) <= self.maxWidth {
                    current = candidate
                } else {
                    self.lines.append(current)
                    if VisibleWidth.measure(wordString) <= self.maxWidth {
                        current = wordString
                    } else {
                        self.lines.append(contentsOf: self.breakLongWord(wordString))
                        current = ""
                    }
                }
            }
            if !current.isEmpty { self.lines.append(current) }
        }
    }

    private func breakLongWord(_ word: String) -> [String] {
        var result: [String] = []
        var current = ""
        for char in word {
            let candidate = current + String(char)
            if VisibleWidth.measure(candidate) > self.maxWidth {
                if !current.isEmpty {
                    result.append(current)
                    current = String(char)
                } else {
                    result.append(String(char))
                    current = ""
                }
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
