import Testing
@testable import TauTUI

@Suite("Markdown code & quotes")
struct MarkdownCodeTests {
    @Test
    func `code block renders fence and content`() {
        let source = """
        ```swift
        print("hello")
        ```
        """
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 40).map { Ansi.stripCodes($0) }
        #expect(lines.contains(where: { $0.contains("```swift") }))
        #expect(lines.contains(where: { $0.contains("  print(\"hello\")") }))
    }

    @Test
    func `block quote prefixes with bar`() {
        let source = "> quoted line\n> second"
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 40).map { Ansi.stripCodes($0) }
        #expect(lines.contains(where: { $0.contains("│ quoted line") }))
        #expect(lines.contains(where: { $0.contains("│ second") || $0.contains("│ quoted line second") }))
    }

    @Test
    func `streaming code blocks stay within the render width`() {
        let component = MarkdownComponent(
            text: "```swift\n\(String(repeating: "abcdefghij", count: 8))",
            padding: .init(horizontal: 0, vertical: 0))

        let partial = component.render(width: 20)
        #expect(partial.allSatisfy { VisibleWidth.measure($0) <= 20 })

        component.text += "\nprint(\"done\")\n```"
        let completed = component.render(width: 20)
        #expect(completed.allSatisfy { VisibleWidth.measure($0) <= 20 })
        #expect(completed.map { Ansi.stripCodes($0) }.contains(where: { $0.contains("done") }))
    }
}
