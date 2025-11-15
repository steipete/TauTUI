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
}
