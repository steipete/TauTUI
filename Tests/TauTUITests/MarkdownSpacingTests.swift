import Testing
@testable import TauTUI

@Suite("Markdown spacing")
struct MarkdownSpacingTests {
    @Test
    func oneBlankLineBetweenCodeBlockAndFollowingParagraph() throws {
        let source = """
        ```ts
        console.log("<div>hello</div>")
        ```

        after
        """

        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 50).map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }

        guard let fenceCloseIndex = lines.lastIndex(where: { $0 == "```" }) else {
            Issue.record("Missing closing fence")
            return
        }
        guard let afterIndex = lines.firstIndex(where: { $0 == "after" }) else {
            Issue.record("Missing paragraph after code block")
            return
        }

        let between = lines[(fenceCloseIndex + 1)..<afterIndex]
        #expect(between.filter { $0.isEmpty }.count == 1)
    }

    @Test
    func oneBlankLineBetweenDividerAndFollowingParagraph() throws {
        let source = """
        before

        ---

        after
        """

        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 30).map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }

        guard let hrIndex = lines.firstIndex(where: { $0.allSatisfy { $0 == "─" } }) else {
            Issue.record("Missing HR")
            return
        }
        guard let afterIndex = lines.firstIndex(where: { $0 == "after" }) else {
            Issue.record("Missing paragraph after HR")
            return
        }

        let between = lines[(hrIndex + 1)..<afterIndex]
        #expect(between.filter { $0.isEmpty }.count == 1)
    }

    @Test
    func oneBlankLineBetweenHeadingAndFollowingParagraph() throws {
        let source = """
        # Title
        after
        """

        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 30).map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }

        guard let titleIndex = lines.firstIndex(where: { $0.contains("Title") }) else {
            Issue.record("Missing heading")
            return
        }
        guard let afterIndex = lines.firstIndex(where: { $0 == "after" }) else {
            Issue.record("Missing paragraph after heading")
            return
        }

        let between = lines[(titleIndex + 1)..<afterIndex]
        #expect(between.filter { $0.isEmpty }.count == 1)
    }

    @Test
    func oneBlankLineBetweenBlockquoteAndFollowingParagraph() throws {
        let source = """
        > quoted

        after
        """

        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 30).map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }

        guard let quoteIndex = lines.firstIndex(where: { $0.contains("│") && $0.contains("quoted") }) else {
            Issue.record("Missing blockquote")
            return
        }
        guard let afterIndex = lines.firstIndex(where: { $0 == "after" }) else {
            Issue.record("Missing paragraph after blockquote")
            return
        }

        let between = lines[(quoteIndex + 1)..<afterIndex]
        #expect(between.filter { $0.isEmpty }.count == 1)
    }

    @Test
    func htmlBlockIsRenderedAsText() throws {
        let source = "<div class=\"x\">hello</div>"
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 40).map { Ansi.stripCodes($0) }
        #expect(lines.joined(separator: "\n").contains(source))
    }

    @Test
    func tableRespectsHorizontalPaddingInWidthBudget() throws {
        let source = """
        | Col1 | Col2 |
        | --- | --- |
        | aaaaaa | bbbbbb |
        """

        let width = 20
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 2, vertical: 0))
        let lines = component.render(width: width).map { Ansi.stripCodes($0) }
        for line in lines {
            #expect(VisibleWidth.measure(line) <= width)
        }
    }
}
