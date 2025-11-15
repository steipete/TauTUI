import Testing
@testable import TauTUI

@Suite("Markdown code & quotes")
struct MarkdownCodeTests {
    @Test
    func codeBlockRendersFenceAndContent() throws {
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
    func blockQuotePrefixesWithBar() throws {
        let source = "> quoted line\n> second"
        let component = MarkdownComponent(text: source, padding: .init(horizontal: 0, vertical: 0))
        let lines = component.render(width: 40).map { Ansi.stripCodes($0) }
        #expect(lines.contains(where: { $0.contains("│ quoted line") }))
        #expect(lines.contains(where: { $0.contains("│ second") || $0.contains("│ quoted line second") }))
    }
}
