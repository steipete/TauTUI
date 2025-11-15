import Testing
@testable import TauTUI
@testable import TauTUIInternal

@Suite("Renderer snapshots")
struct RendererSnapshotTests {
    @MainActor @Test
    func markdownSnapshot() throws {
        let terminal = VirtualTerminal(columns: 30, rows: 10)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let markdown = MarkdownComponent(text: """
        # Title
        - item
        ```
        code
        ```
        """, padding: .init(horizontal: 0, vertical: 0))
        tui.addChild(markdown)
        try tui.start()
        let output = terminal.outputLog.joined(separator: "\n")
        #expect(output.contains("Title"))
        #expect(output.contains("item"))
        #expect(output.contains("code"))
    }

    @MainActor @Test
    func selectListSnapshot() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 6)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let list = SelectList(items: [
            SelectItem(value: "a", label: "Alpha", description: "first"),
            SelectItem(value: "b", label: "Beta", description: "second"),
            SelectItem(value: "c", label: "Gamma", description: "third"),
        ], maxVisible: 2)
        tui.addChild(list)
        try tui.start()
        let output = terminal.outputLog.joined(separator: "\n")
        #expect(output.contains("Alpha"))
        #expect(output.contains("Beta"))
        #expect(!output.contains("Gamma")) // clipped to maxVisible
    }
}
