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

    public struct DefaultTextStyle: Sendable {
        public var color: AnsiStyling.Style?
        public var background: AnsiStyling.Background?
        public var bold: Bool
        public var italic: Bool
        public var strikethrough: Bool
        public var underline: Bool

        public init(
            color: AnsiStyling.Style? = nil,
            background: AnsiStyling.Background? = nil,
            bold: Bool = false,
            italic: Bool = false,
            strikethrough: Bool = false,
            underline: Bool = false)
        {
            self.color = color
            self.background = background
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.underline = underline
        }
    }

    public struct MarkdownTheme: Sendable {
        public var heading: AnsiStyling.Style
        public var link: AnsiStyling.Style
        public var linkUrl: AnsiStyling.Style
        public var code: AnsiStyling.Style
        public var codeBlock: AnsiStyling.Style
        public var codeBlockBorder: AnsiStyling.Style
        public var quote: AnsiStyling.Style
        public var quoteBorder: AnsiStyling.Style
        public var hr: AnsiStyling.Style
        public var listBullet: AnsiStyling.Style
        public var bold: AnsiStyling.Style
        public var italic: AnsiStyling.Style
        public var strikethrough: AnsiStyling.Style
        public var underline: AnsiStyling.Style

        public init(
            heading: @escaping AnsiStyling.Style,
            link: @escaping AnsiStyling.Style,
            linkUrl: @escaping AnsiStyling.Style,
            code: @escaping AnsiStyling.Style,
            codeBlock: @escaping AnsiStyling.Style,
            codeBlockBorder: @escaping AnsiStyling.Style,
            quote: @escaping AnsiStyling.Style,
            quoteBorder: @escaping AnsiStyling.Style,
            hr: @escaping AnsiStyling.Style,
            listBullet: @escaping AnsiStyling.Style,
            bold: @escaping AnsiStyling.Style,
            italic: @escaping AnsiStyling.Style,
            strikethrough: @escaping AnsiStyling.Style,
            underline: @escaping AnsiStyling.Style)
        {
            self.heading = heading
            self.link = link
            self.linkUrl = linkUrl
            self.code = code
            self.codeBlock = codeBlock
            self.codeBlockBorder = codeBlockBorder
            self.quote = quote
            self.quoteBorder = quoteBorder
            self.hr = hr
            self.listBullet = listBullet
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.underline = underline
        }

        public static let `default` = MarkdownTheme(
            heading: AnsiStyling.color(36),
            link: { AnsiStyling.color(34)(AnsiStyling.underline($0)) },
            linkUrl: { "\u{001B}[90m\($0)\u{001B}[0m" },
            code: AnsiStyling.color(33),
            codeBlock: AnsiStyling.color(32),
            codeBlockBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },
            quote: AnsiStyling.italic,
            quoteBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },
            hr: { "\u{001B}[90m\($0)\u{001B}[0m" },
            listBullet: AnsiStyling.color(36),
            bold: AnsiStyling.bold,
            italic: AnsiStyling.italic,
            strikethrough: AnsiStyling.strikethrough,
            underline: AnsiStyling.underline)
    }

    public var text: String { didSet { self.invalidateCache() } }
    public var padding: Padding { didSet { self.invalidateCache() } }
    public var defaultTextStyle: DefaultTextStyle? { didSet { self.invalidateCache() } }
    public var theme: MarkdownTheme { didSet { self.invalidateCache() } }

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(
        text: String = "",
        padding: Padding = Padding(),
        theme: MarkdownTheme = .default,
        defaultTextStyle: DefaultTextStyle? = nil)
    {
        self.text = text
        self.padding = padding
        self.theme = theme
        self.defaultTextStyle = defaultTextStyle
    }

    public func render(width: Int) -> [String] {
        if let cachedWidth, cachedWidth == width, let cachedLines { return cachedLines }
        guard width > 0 else { self.cache(width: width, lines: []); return [] }

        let contentWidth = max(1, width - self.padding.horizontal * 2)
        let renderer = Renderer(maxWidth: contentWidth, theme: self.theme)
        let document = Document(parsing: text)
        document.children.forEach { renderer.visit($0) }

        let leftPad = String(repeating: " ", count: padding.horizontal)
        let emptyLine = String(repeating: " ", count: width)
        var result: [String] = []

        for _ in 0..<self.padding.vertical {
            result.append(self.applyColors(to: emptyLine))
        }
        for line in renderer.lines {
            let visible = VisibleWidth.measure(line)
            let right = max(0, width - self.padding.horizontal - visible)
            let padded = leftPad + line + String(repeating: " ", count: right)
            result.append(self.applyColors(to: padded))
        }
        for _ in 0..<self.padding.vertical {
            result.append(self.applyColors(to: emptyLine))
        }

        self.cache(width: width, lines: result)
        return result
    }

    private func applyColors(to line: String) -> String {
        guard let style = self.defaultTextStyle else { return line }
        var styled = line

        if let color = style.color {
            styled = color(styled)
        }
        if style.bold {
            styled = AnsiStyling.bold(styled)
        }
        if style.italic {
            styled = AnsiStyling.italic(styled)
        }
        if style.strikethrough {
            styled = AnsiStyling.strikethrough(styled)
        }
        if style.underline {
            styled = AnsiStyling.underline(styled)
        }

        if let background = style.background {
            styled = AnsiWrapping.applyBackgroundToLine(
                styled,
                width: VisibleWidth.measure(line),
                background: background)
        }

        return styled
    }

    private func invalidateCache() {
        self.cachedWidth = nil
        self.cachedLines = nil
    }

    private func cache(width: Int, lines: [String]) {
        self.cachedWidth = width
        self.cachedLines = lines
    }

    public func invalidate() {
        self.invalidateCache()
    }

    @MainActor public func apply(theme: ThemePalette) {
        self.theme = theme.markdown
        self.invalidateCache()
    }
}

private final class Renderer {
    let maxWidth: Int
    let theme: MarkdownComponent.MarkdownTheme
    var lines: [String] = []
    private var listDepth: Int = 0

    init(maxWidth: Int, theme: MarkdownComponent.MarkdownTheme) {
        self.maxWidth = max(1, maxWidth)
        self.theme = theme
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
        let decorated: String
        switch heading.level {
        case 1:
            decorated = self.theme.heading(self.theme.bold(self.theme.underline(text)))
        case 2:
            decorated = self.theme.heading(self.theme.bold(text))
        default:
            let prefix = String(repeating: "#", count: heading.level) + " "
            decorated = self.theme.heading(self.theme.bold(prefix + text))
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
                    self.wrap(line: self.theme.listBullet(bullet) + inline)
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
        let innerRenderer = Renderer(maxWidth: max(maxWidth - 2, 1), theme: self.theme)
        quote.children.forEach { innerRenderer.visit($0) }
        for line in innerRenderer.lines {
            self.lines.append(self.theme.quoteBorder("│ ") + self.theme.quote(self.theme.italic(line)))
        }
        self.lines.append("")
    }

    private func renderCodeBlock(_ code: CodeBlock) {
        self.lines.append(self.theme.codeBlockBorder("```\(code.language ?? "")"))
        for line in code.code.split(separator: "\n", omittingEmptySubsequences: false) {
            self.lines.append("  " + self.theme.codeBlock(String(line)))
        }
        self.lines.append(self.theme.codeBlockBorder("```"))
        self.lines.append("")
    }

    private func renderThematicBreak(_ breakNode: ThematicBreak) {
        let width = min(maxWidth, 80)
        self.lines.append(self.theme.hr(String(repeating: "─", count: width)))
        self.lines.append("")
    }

    private func renderTable(_ table: Table) {
        let headCells = Array(table.head.cells)
        let numCols = headCells.count
        guard numCols > 0 else { return }
        let alignments = table.columnAlignments

        // Border overhead for: "│ " + (n-1) * " │ " + " │" = 3n + 1
        let borderOverhead = 3 * numCols + 1
        let minTableWidth = borderOverhead + numCols // at least 1 char per column

        if self.maxWidth < minTableWidth {
            self.wrap(line: table.format())
            self.lines.append("")
            return
        }

        func wrapCellText(_ text: String, maxWidth: Int) -> [String] {
            AnsiWrapping.wrapText(text, width: max(1, maxWidth))
        }

        var naturalWidths = Array(repeating: 0, count: numCols)

        func measure(cells: [Table.Cell]) {
            for (index, cell) in cells.enumerated() where index < numCols {
                let text = self.renderInline(cell.inlineChildren)
                naturalWidths[index] = max(naturalWidths[index], VisibleWidth.measure(text))
            }
        }

        measure(cells: headCells)
        table.body.rows.forEach { measure(cells: Array($0.cells)) }

        let totalNaturalWidth = naturalWidths.reduce(0, +) + borderOverhead
        let columnWidths: [Int]

        if totalNaturalWidth <= self.maxWidth {
            columnWidths = naturalWidths
        } else {
            let availableForCells = self.maxWidth - borderOverhead
            let totalNatural = max(1, naturalWidths.reduce(0, +))

            var widths = naturalWidths.map { w in
                let proportion = Double(w) / Double(totalNatural)
                return max(1, Int((proportion * Double(availableForCells)).rounded(.down)))
            }

            let allocated = widths.reduce(0, +)
            var remaining = max(0, availableForCells - allocated)
            var i = 0
            while remaining > 0, i < numCols {
                widths[i] += 1
                remaining -= 1
                i += 1
            }

            columnWidths = widths
        }

        func horizontal(_ left: String, _ mid: String, _ right: String) -> String {
            let cells = columnWidths.map { String(repeating: "─", count: $0) }
            return left + "─" + cells.joined(separator: "─" + mid + "─") + "─" + right
        }

        self.lines.append(horizontal("┌", "┬", "┐"))

        let headerCellLines: [[String]] = headCells.enumerated().map { i, cell in
            let text = self.renderInline(cell.inlineChildren)
            return wrapCellText(text, maxWidth: columnWidths[i])
        }
        let headerLineCount = headerCellLines.map(\.count).max() ?? 1

        for lineIndex in 0..<headerLineCount {
            let parts: [String] = headerCellLines.enumerated().map { col, lines in
                let text = lineIndex < lines.count ? lines[lineIndex] : ""
                let vis = VisibleWidth.measure(text)
                let padding = max(0, columnWidths[col] - vis)
                let alignment: Table.ColumnAlignment = if col < alignments.count {
                    alignments[col] ?? .left
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

                let padded = String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
                return self.theme.bold(padded)
            }
            self.lines.append("│ " + parts.joined(separator: " │ ") + " │")
        }

        self.lines.append(horizontal("├", "┼", "┤"))

        for row in table.body.rows {
            let cells = Array(row.cells)
            let rowCellLines: [[String]] = cells.enumerated().map { i, cell in
                let text = self.renderInline(cell.inlineChildren)
                return wrapCellText(text, maxWidth: columnWidths[i])
            }
            let rowLineCount = rowCellLines.map(\.count).max() ?? 1

            for lineIndex in 0..<rowLineCount {
                let parts: [String] = rowCellLines.enumerated().map { col, lines in
                    let text = lineIndex < lines.count ? lines[lineIndex] : ""
                    let vis = VisibleWidth.measure(text)
                    let padding = max(0, columnWidths[col] - vis)
                    let alignment: Table.ColumnAlignment = if col < alignments.count {
                        alignments[col] ?? .left
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

                    return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
                }
                self.lines.append("│ " + parts.joined(separator: " │ ") + " │")
            }
        }

        self.lines.append(horizontal("└", "┴", "┘"))
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
                result += self.theme.bold(self.renderInlineSequence(strong.inlineChildren))
            case let emphasis as Emphasis:
                result += self.theme.italic(self.renderInlineSequence(emphasis.inlineChildren))
            case let code as InlineCode:
                result += self.theme.code(code.code)
            case let link as Link:
                let label = self.renderInlineSequence(link.inlineChildren)
                if let destination = link.destination {
                    result += self.theme.link(label) + self.theme.linkUrl(" (\(destination))")
                } else {
                    result += self.theme.link(label)
                }
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
        let wrapped = AnsiWrapping.wrapText(line, width: self.maxWidth)
        self.lines.append(contentsOf: wrapped)
    }
}
