import Foundation
import Testing
@testable import TauTUI
@testable import TauTUIInternal

private final class DummyComponent: Component {
    var lines: [String]
    init(lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { self.lines }
}

private final class CapturingInputComponent: Component {
    private(set) var inputs: [TerminalInput] = []

    func render(width: Int) -> [String] { [""] }

    func handle(input: TerminalInput) {
        self.inputs.append(input)
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
        #expect(!last.contains("\u{001B}[3J"))
        #expect(last.contains("\u{001B}[?2026h"))
    }

    @MainActor @Test
    func controlCInvokesHandlerAndSkipsFocusedComponent() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = CapturingInputComponent()
        tui.addChild(component)
        tui.setFocus(component)

        var called = false
        tui.onControlC = {
            called = true
            tui.stop()
        }

        try tui.start()
        terminal.sendInput(.key(.character("c"), modifiers: [.control]))

        #expect(called)
        #expect(component.inputs.isEmpty)
        #expect(terminal.outputLog.contains("\u{001B}[?25h"))
    }

    @MainActor @Test
    func controlCCanBeForwardedToFocusedComponent() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = CapturingInputComponent()
        tui.addChild(component)
        tui.setFocus(component)

        var called = false
        tui.onControlC = { called = true }
        tui.handlesControlC = false

        try tui.start()
        terminal.sendInput(.key(.character("c"), modifiers: [.control]))

        #expect(!called)
        #expect(component.inputs.count == 1)
    }

    @Test
    func keyEventNormalization_metaPrefix() throws {
        // ESC b -> Option+Left, ESC f -> Option+Right, ESC d -> Option+Delete, ESC DEL -> Option+Backspace
        let parser = ProcessTerminal()
        let events = parser.parseForTests("\u{001B}b\u{001B}f\u{001B}d" + String(bytes: [0x1B, 0x7F], encoding: .utf8)!)
        #expect(events
            .contains(where: { if case let .key(.arrowLeft, m) = $0 { return m.contains(.option) }; return false }))
        #expect(events
            .contains(where: { if case let .key(.arrowRight, m) = $0 { return m.contains(.option) }; return false }))
        #expect(events
            .contains(where: { if case let .key(.delete, m) = $0 { return m.contains(.option) }; return false }))
        #expect(events
            .contains(where: { if case let .key(.backspace, m) = $0 { return m.contains(.option) }; return false }))

        // Option+Enter via ESC CR and via CSI 13;3~
        let enterMeta = parser.parseForTests("\u{001B}\r")
        #expect(enterMeta
            .contains(where: { if case let .key(.enter, m) = $0 { return m.contains(.option) }; return false }))

        let enterCsi = parser.parseForTests("\u{001B}[13;3~")
        #expect(enterCsi
            .contains(where: { if case let .key(.enter, m) = $0 { return m.contains(.option) }; return false }))
    }

    @Test
    func keyEventNormalization_csiModifiers() throws {
        let parser = ProcessTerminal()
        let payload = "\u{001B}[1;3D\u{001B}[1;5C\u{001B}[Z\u{001B}[13;2~"
        let events = parser.parseForTests(payload)
        #expect(events
            .contains(where: { if case let .key(.arrowLeft, m) = $0 { return m == [.option] }; return false }))
        #expect(events
            .contains(where: { if case let .key(.arrowRight, m) = $0 { return m == [.control] }; return false }))
        #expect(events.contains(where: { if case let .key(.tab, m) = $0 { return m.contains(.shift) }; return false }))
        #expect(events
            .contains(where: { if case let .key(.enter, m) = $0 { return m.contains(.shift) }; return false }))
    }
}
