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

    public var text: String { didSet { invalidateCache() } }
    public var padding: Padding { didSet { invalidateCache() } }
    public var background: Text.Background? { didSet { invalidateCache() } }

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(text: String = "", padding: Padding = Padding(), background: Text.Background? = nil) {
        self.text = text
        self.padding = padding
        self.background = background
    }

    public func render(width: Int) -> [String] {
        if let cachedWidth, cachedWidth == width, let cachedLines { return cachedLines }
        guard width > 0 else { cache(width: width, lines: []); return [] }

        let contentWidth = max(1, width - padding.horizontal * 2)
        let renderer = Renderer(maxWidth: contentWidth)
        let document = Document(parsing: text)
        document.children.forEach { renderer.visit($0) }

        let leftPad = String(repeating: " ", count: padding.horizontal)
        let emptyLine = String(repeating: " ", count: width)
        var result: [String] = []

        for _ in 0..<padding.vertical { result.append(applyBackground(to: emptyLine)) }
        for line in renderer.lines {
            let visible = VisibleWidth.measure(line)
            let right = max(0, width - padding.horizontal - visible)
            let padded = leftPad + line + String(repeating: " ", count: right)
            result.append(applyBackground(to: padded))
        }
        for _ in 0..<padding.vertical { result.append(applyBackground(to: emptyLine)) }

        cache(width: width, lines: result)
        return result
    }

    private func applyBackground(to line: String) -> String {
        guard let background else { return line }
        return background.ansiPrefix + line + "\u{001B}[0m"
    }

    private func invalidateCache() {
        cachedWidth = nil
        cachedLines = nil
    }

    private func cache(width: Int, lines: [String]) {
        cachedWidth = width
        cachedLines = lines
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
            renderHeading(heading)
        case let paragraph as Paragraph:
            renderParagraph(paragraph)
        case let list as UnorderedList:
            listDepth += 1
            renderListItems(Array(list.listItems), ordered: false)
            listDepth -= 1
        case let list as OrderedList:
            listDepth += 1
            renderListItems(Array(list.listItems), ordered: true)
            listDepth -= 1
        case let blockQuote as BlockQuote:
            renderBlockQuote(blockQuote)
        case let code as CodeBlock:
            renderCodeBlock(code)
        case let thematic as ThematicBreak:
            renderThematicBreak(thematic)
        case let table as Table:
            renderTable(table)
        case let html as HTMLBlock:
            wrap(line: html.rawHTML)
        default:
            markup.children.forEach { visit($0) }
        }
    }

    private func renderHeading(_ heading: Heading) {
        let text = renderInline(heading.inlineChildren)
        let decorated: String
        switch heading.level {
        case 1:
            decorated = "\u{001B}[1;4;33m\(text)\u{001B}[0m"
        case 2:
            decorated = "\u{001B}[1;33m\(text)\u{001B}[0m"
        default:
            decorated = "\u{001B}[1m\(String(repeating: "#", count: heading.level)) \(text)\u{001B}[0m"
        }
        wrap(line: decorated)
        lines.append("")
    }

    private func renderParagraph(_ paragraph: Paragraph) {
        wrap(line: renderInline(paragraph.inlineChildren))
        lines.append("")
    }

    private func renderListItems(_ items: [ListItem], ordered: Bool) {
        let indentPrefix = String(repeating: "  ", count: max(listDepth - 1, 0))
        for (index, item) in items.enumerated() {
            let bullet = indentPrefix + (ordered ? "\(index + 1). " : "- ")
            let children = Array(item.children)
            if let firstChild = children.first {
                if let paragraph = firstChild as? Paragraph {
                    let inline = renderInline(paragraph.inlineChildren)
                    wrap(line: "\u{001B}[36m\(bullet)\u{001B}[0m\(inline)")
                } else {
                    wrap(line: bullet + firstChild.format())
                }
                if children.count > 1 {
                    children.dropFirst().forEach { visit($0) }
                }
            } else {
                wrap(line: bullet)
            }
        }
        lines.append("")
    }

    private func renderBlockQuote(_ quote: BlockQuote) {
        let innerRenderer = Renderer(maxWidth: max(maxWidth - 2, 1))
        quote.children.forEach { innerRenderer.visit($0) }
        innerRenderer.lines.forEach { line in
            lines.append("\u{001B}[90m│ \u{001B}[3m\(line)\u{001B}[0m")
        }
        lines.append("")
    }

    private func renderCodeBlock(_ code: CodeBlock) {
        lines.append("\u{001B}[90m```\(code.language ?? "")\u{001B}[0m")
        code.code.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
            lines.append("\u{001B}[2m  \u{001B}[0m\u{001B}[32m\(line)\u{001B}[0m")
        }
        lines.append("\u{001B}[90m```\u{001B}[0m")
        lines.append("")
    }

    private func renderThematicBreak(_ breakNode: ThematicBreak) {
        let width = min(maxWidth, 80)
        lines.append("\u{001B}[90m\(String(repeating: "─", count: width))\u{001B}[0m")
        lines.append("")
    }

    private func renderTable(_ table: Table) {
        let columnCount = table.columnAlignments.count
        var widths = Array(repeating: 0, count: max(columnCount, 1))

        func measure(cells: [Table.Cell]) {
            for (index, cell) in cells.enumerated() {
                guard index < widths.count else { continue }
                let text = renderInline(cell.inlineChildren)
                widths[index] = min(max(widths[index], VisibleWidth.measure(text)), maxWidth)
            }
        }

        measure(cells: Array(table.head.cells))
        table.body.rows.forEach { measure(cells: Array($0.cells)) }

        func renderRow(cells: [Table.Cell]) {
            var line = "│ "
            for (index, cell) in cells.enumerated() {
                guard index < widths.count else { continue }
                let text = renderInline(cell.inlineChildren)
                let vis = VisibleWidth.measure(text)
                let padding = max(0, widths[index] - vis)
                line += text + String(repeating: " ", count: padding)
                line += index == widths.count - 1 ? " │" : " │ "
            }
            lines.append(line)
        }

        renderRow(cells: Array(table.head.cells))
        let separators = widths.map { String(repeating: "─", count: max(1, $0)) }
        lines.append("├─" + separators.joined(separator: "─┼─") + "─┤")
        table.body.rows.forEach { renderRow(cells: Array($0.cells)) }
        lines.append("")
    }

    private func renderInline(_ children: LazyMapSequence<MarkupChildren, InlineMarkup>) -> String {
        renderInlineSequence(children)
    }

    private func renderInlineSequence<S: Sequence>(_ sequence: S) -> String where S.Element == InlineMarkup {
        var result = ""
        for child in sequence {
            switch child {
            case let text as Markdown.Text:
                result += text.string
            case let strong as Strong:
                result += "\u{001B}[1m\(renderInlineSequence(strong.inlineChildren))\u{001B}[0m"
            case let emphasis as Emphasis:
                result += "\u{001B}[3m\(renderInlineSequence(emphasis.inlineChildren))\u{001B}[0m"
            case let code as InlineCode:
                result += "\u{001B}[90m`\u{001B}[36m\(code.code)\u{001B}[90m`\u{001B}[0m"
            case let link as Link:
                let label = renderInlineSequence(link.inlineChildren)
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
                    if VisibleWidth.measure(wordString) <= maxWidth {
                        current = wordString
                    } else {
                        lines.append(contentsOf: breakLongWord(wordString))
                    }
                    continue
                }
                let candidate = current + " " + wordString
                if VisibleWidth.measure(candidate) <= maxWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    if VisibleWidth.measure(wordString) <= maxWidth {
                        current = wordString
                    } else {
                        lines.append(contentsOf: breakLongWord(wordString))
                        current = ""
                    }
                }
            }
            if !current.isEmpty { lines.append(current) }
        }
    }

    private func breakLongWord(_ word: String) -> [String] {
        var result: [String] = []
        var current = ""
        for char in word {
            let candidate = current + String(char)
            if VisibleWidth.measure(candidate) > maxWidth {
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
