import Testing
@testable import TauTUI

private final class DummyComponent: Component {
    var lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        lines
    }
}

@Suite("TUI Rendering")
struct TUIRenderingTests {
    @MainActor @Test
    func firstRenderProducesFullSyncFrame() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["Hello"])
        tui.addChild(component)
        try tui.start()
        #expect(terminal.outputLog.contains(where: { $0.contains("\u{001B}[?2026hHello") }))
    }

    @MainActor @Test
    func resizeForcesFullRenderAndClear() throws {
        let terminal = VirtualTerminal(columns: 10, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["hello", "world"])
        tui.addChild(component)
        try tui.start()

        terminal.resize(columns: 20, rows: 5)

        // Last write should include sync start + full clear + content.
        let last = terminal.outputLog.last ?? ""
        #expect(last.contains("\u{001B}[?2026h"))
        #expect(last.contains("\u{001B}[3J\u{001B}[2J\u{001B}[H"))
        #expect(last.contains("hello\r\nworld"))
    }

    @MainActor @Test
    func partialDiffWritesOnlyChangedLines() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["hello", "world"])
        tui.addChild(component)
        try tui.start()

        component.lines = ["hello", "swift"]
        tui.requestRender()

        let last = terminal.outputLog.last ?? ""
        #expect(last.contains("swift"))
        #expect(!last.contains("\u{001B}[3J")) // no full clear
        #expect(last.contains("\u{001B}[?2026h"))
    }
}
