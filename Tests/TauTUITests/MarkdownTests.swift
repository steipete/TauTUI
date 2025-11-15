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
        #expect(plain.contains(where: { $0.contains("│ longer │ mid    │ 123   │") }))
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
}
