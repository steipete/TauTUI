import Testing
@testable import TauTUI

@Suite("Markdown component")
struct MarkdownTests {
    @Test
    func nestedLists() async throws {
        let source = """
        - Item 1
          - Nested 1.1
          - Nested 1.2
        - Item 2
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: 60).map { Ansi.stripCodes($0) }
        #expect(plain.contains(where: { $0.contains("- Item 1") }))
        #expect(plain.contains(where: { $0.contains("  - Nested 1.1") }))
        #expect(plain.contains(where: { $0.contains("  - Nested 1.2") }))
        #expect(plain.contains(where: { $0.contains("- Item 2") }))
    }

    @Test
    func orderedList() async throws {
        let source = """
        1. First
           1. Nested first
           2. Nested second
        2. Second
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: 60).map { Ansi.stripCodes($0) }
        #expect(plain.contains(where: { $0.contains("1. First") }))
        #expect(plain.contains(where: { $0.contains("2. Second") }))
    }

    @Test
    func tables() async throws {
        let source = """
        | Name | Age |
        | --- | --- |
        | Alice | 30 |
        | Bob | 25 |
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: 60).map { Ansi.stripCodes($0) }
        #expect(plain.contains(where: { $0.contains("Name") }))
        #expect(plain.contains(where: { $0.contains("Alice") }))
        #expect(plain.contains(where: { $0.contains("Bob") }))
    }

    @Test
    func tableAlignmentBaseline() async throws {
        let source = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        | longer | mid | 123 |
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: 80).map { Ansi.stripCodes($0) }
        // Baseline snapshot of current spacing; update if we change alignment logic.
        #expect(plain.contains(where: { $0.contains("│ Left   │ Center │ Right │") }))
        #expect(plain.contains(where: { $0.contains("│ a      │   b    │     c │") }))
        #expect(plain.contains(where: { $0.contains("│ longer │  mid   │   123 │") }))
    }

    @Test
    func combinedFeatures() async throws {
        let source = """
        # Test Document

        - Item 1
          - Nested item
        - Item 2

        | Col1 | Col2 |
        | --- | --- |
        | A | B |
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: 60).map { Ansi.stripCodes($0) }
        #expect(plain.contains(where: { $0.contains("Test Document") }))
        #expect(plain.contains(where: { $0.contains("- Item 1") }))
        #expect(plain.contains(where: { $0.contains("Col1") }))
        #expect(plain.contains(where: { $0.contains("│") }))
    }

    @Test
    func foregroundColorIsApplied() async throws {
        let component = MarkdownComponent(
            text: "colored",
            padding: .init(horizontal: 0, vertical: 0),
            theme: .default,
            defaultTextStyle: .init(color: AnsiStyling.rgb(10, 20, 30)))
        let rendered = component.render(width: 20)
        #expect(rendered.contains(where: { $0.contains("\u{001B}[38;2;10;20;30m") }))
    }

    @Test
    func wrapsLongUnbrokenTokensInsideTableCells() async throws {
        let url = "https://example.com/this/is/a/very/long/url/that/should/wrap"
        let source = """
        | Value |
        | --- |
        | prefix \(url) |
        """
        let width = 30
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: width)
        let plain = lines.map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }

        for line in plain {
            #expect(VisibleWidth.measure(line) <= width)
        }

        let tableLines = plain.filter { $0.hasPrefix("│") }
        for line in tableLines {
            let borderCount = line.filter { $0 == "│" }.count
            #expect(borderCount == 2)
        }

        let extracted = plain.joined().replacingOccurrences(of: "│", with: "")
            .replacingOccurrences(of: "─", with: "")
            .replacingOccurrences(of: " ", with: "")
        #expect(extracted.contains("prefix"))
        #expect(extracted.contains(url))
    }

    @Test
    func wrapsStyledInlineCodeInsideTableCells() async throws {
        let source = """
        | Code |
        | --- |
        | `averyveryveryverylongidentifier` |
        """
        let width = 20
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: width)
        #expect(lines.joined(separator: "\n").contains("\u{001B}[33m"))

        let plain = lines.map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }
        for line in plain {
            #expect(VisibleWidth.measure(line) <= width)
        }
    }

    @Test
    func extremelyNarrowTableDoesNotCrash() async throws {
        let source = """
        | A | B | C |
        | --- | --- | --- |
        | 1 | 2 | 3 |
        """
        let width = 15
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let plain = component.render(width: width).map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }
        #expect(!plain.isEmpty)
        for line in plain {
            #expect(VisibleWidth.measure(line) <= width)
        }
    }
}
