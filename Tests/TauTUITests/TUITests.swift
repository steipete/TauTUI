import Foundation
import Testing
@testable import TauTUI
@testable import TauTUIInternal

private final class DummyComponent: Component {
    var lines: [String]
    init(lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        self.lines
    }
}

private final class CapturingInputComponent: Component {
    private(set) var inputs: [TerminalInput] = []

    func render(width: Int) -> [String] {
        [""]
    }

    func handle(input: TerminalInput) {
        self.inputs.append(input)
    }
}

@Suite("TUI Rendering")
struct TUIRenderingTests {
    @MainActor @Test
    func `first render produces full sync frame`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["Hello"])
        tui.addChild(component)
        try tui.start()
        #expect(terminal.outputLog.contains(where: { $0.contains("\u{001B}[?2026hHello") }))
    }

    @MainActor @Test
    func `resize forces full render and clear`() throws {
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
    func `height resize forces full render and clear`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["hello", "world"])
        tui.addChild(component)
        try tui.start()

        terminal.resize(columns: 20, rows: 8)

        let last = terminal.outputLog.last ?? ""
        #expect(last.contains("\u{001B}[?2026h"))
        #expect(last.contains("\u{001B}[3J\u{001B}[2J\u{001B}[H"))
        #expect(last.contains("hello\r\nworld"))
    }

    @MainActor @Test
    func `partial diff writes only changed lines`() throws {
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

    @Test
    func `full and partial render ranges report the same width violation`() {
        let lines = ["fits", "\u{001B}[31m123456\u{001B}[0m"]
        let expected = TUI.RenderWidthViolation(lineIndex: 1, visibleWidth: 6, maximumWidth: 5)

        #expect(TUI.firstRenderWidthViolation(in: lines, width: 5) == expected)
        #expect(TUI.firstRenderWidthViolation(in: lines, width: 5, from: 1) == expected)
    }

    @Test
    func `render width validation exempts embedded image payloads`() {
        let kitty = "prefix\u{001B}_Ga=t,f=100;AAAA\u{001B}\\suffix"
        let iTerm = "prefix\u{001B}]1337;File=inline=1:AAAA\u{0007}suffix"

        #expect(TUI.firstRenderWidthViolation(in: [kitty, iTerm], width: 1) == nil)
    }

    @MainActor @Test
    func `partial diff clears extra old lines`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["one", "two", "three"])
        tui.addChild(component)
        try tui.start()

        component.lines = ["one"]
        tui.requestRender()

        let last = terminal.outputLog.last ?? ""
        let expectedClear = ANSI.carriageReturn + ANSI.clearLine + "\r\n" + ANSI.clearLine + ANSI.cursorUp(2)
        #expect(last.contains(expectedClear))
    }

    @MainActor @Test
    func `partial diff clears a removed trailing empty line`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["one", ""])
        tui.addChild(component)
        try tui.start()
        let writesBeforeRemoval = terminal.outputLog.count

        component.lines = ["one"]
        tui.requestRender()

        #expect(terminal.outputLog.count == writesBeforeRemoval + 1)
        let last = terminal.outputLog.last ?? ""
        let expectedClear = ANSI.carriageReturn + ANSI.clearLine + ANSI.cursorUp(1)
        #expect(last.contains(expectedClear))
    }

    @MainActor @Test
    func `rendering no lines clears all previous lines`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        let tui = TUI(terminal: terminal, renderScheduler: { $0() })
        let component = DummyComponent(lines: ["one", "two", "three"])
        tui.addChild(component)
        try tui.start()

        component.lines = []
        tui.requestRender()

        let last = terminal.outputLog.last ?? ""
        #expect(last.components(separatedBy: "\u{001B}[2K").count - 1 == 3)
    }

    @MainActor @Test
    func `queued render does not write after stop`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        var scheduledRenders: [@MainActor @Sendable () -> Void] = []
        let tui = TUI(terminal: terminal, renderScheduler: { scheduledRenders.append($0) })
        tui.addChild(DummyComponent(lines: ["Hello"]))
        try tui.start()
        #expect(scheduledRenders.count == 1)

        tui.stop()
        let outputAfterStop = terminal.outputLog
        scheduledRenders.removeFirst()()

        #expect(terminal.outputLog == outputAfterStop)
    }

    @MainActor @Test
    func `restart ignores a queued render from the previous session`() throws {
        let terminal = VirtualTerminal(columns: 20, rows: 5)
        var scheduledRenders: [@MainActor @Sendable () -> Void] = []
        let tui = TUI(terminal: terminal, renderScheduler: { scheduledRenders.append($0) })
        tui.addChild(DummyComponent(lines: ["Hello"]))
        try tui.start()
        tui.stop()
        try tui.start()
        #expect(scheduledRenders.count == 2)

        scheduledRenders.removeFirst()()
        #expect(!terminal.outputLog.contains(where: { $0.contains("Hello") }))

        scheduledRenders.removeFirst()()
        #expect(terminal.outputLog.contains(where: { $0.contains("Hello") }))
    }

    @MainActor @Test
    func `control C invokes handler and skips focused component`() throws {
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
    func `control C can be forwarded to focused component`() throws {
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
    func `key event normalization meta prefix`() {
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
    func `key event normalization csi modifiers`() {
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

    @Test
    func `key event normalization kitty CSIU`() {
        let parser = ProcessTerminal()
        let payload = "\u{001B}[13;2u\u{001B}[27u\u{001B}[119;5u\u{001B}[127;3u"
        let events = parser.parseForTests(payload)

        #expect(events
            .contains(where: { if case let .key(.enter, m) = $0 { return m.contains(.shift) }; return false }))
        #expect(events.contains(where: { if case .key(.escape, _) = $0 { return true }; return false }))
        #expect(events
            .contains(where: { if case let .key(.character("w"), m) = $0 { return m.contains(.control) }; return false
            }))
        #expect(events
            .contains(where: { if case let .key(.backspace, m) = $0 { return m.contains(.option) }; return false }))
    }

    @Test
    func `CSI parsing survives every byte split`() {
        let payload = Array("\u{001B}[1;3D".utf8)

        for split in 0...payload.count {
            let parser = ProcessTerminal()
            let events = parser.parseBytesForTests([
                Array(payload[..<split]),
                Array(payload[split...]),
            ])

            #expect(events.count == 1, "split at byte \(split)")
            guard events.count == 1,
                  case let .key(.arrowLeft, modifiers) = events[0]
            else {
                Issue.record("expected Option-Left when split at byte \(split)")
                continue
            }
            #expect(modifiers == [.option], "split at byte \(split)")
        }
    }

    @Test
    func `Kitty parsing survives every byte split`() {
        let payload = Array("\u{001B}[119;5u".utf8)

        for split in 0...payload.count {
            let parser = ProcessTerminal()
            let events = parser.parseBytesForTests([
                Array(payload[..<split]),
                Array(payload[split...]),
            ])

            #expect(events.count == 1, "split at byte \(split)")
            guard events.count == 1,
                  case let .key(.character("w"), modifiers) = events[0]
            else {
                Issue.record("expected Control-W when split at byte \(split)")
                continue
            }
            #expect(modifiers == [.control], "split at byte \(split)")
        }
    }

    @Test
    func `bracketed paste delimiters survive every byte split`() {
        let pasted = "hello 😀"
        let payload = Array("\u{001B}[200~\(pasted)\u{001B}[201~".utf8)

        for split in 0...payload.count {
            let parser = ProcessTerminal()
            let events = parser.parseBytesForTests([
                Array(payload[..<split]),
                Array(payload[split...]),
            ])

            #expect(events.count == 1, "split at byte \(split)")
            guard events.count == 1, case let .paste(value) = events[0] else {
                Issue.record("expected one paste event when split at byte \(split)")
                continue
            }
            #expect(value == pasted, "split at byte \(split)")
        }
    }

    @Test
    func `UTF8 input survives every byte split`() {
        let text = "Aé😀B"
        let payload = Array(text.utf8)

        for split in 0...payload.count {
            let parser = ProcessTerminal()
            let events = parser.parseBytesForTests([
                Array(payload[..<split]),
                Array(payload[split...]),
            ])
            let characters = events.compactMap { event -> Character? in
                guard case let .key(.character(character), modifiers) = event,
                      modifiers.isEmpty
                else { return nil }
                return character
            }

            #expect(events.count == text.count, "split at byte \(split)")
            #expect(String(characters) == text, "split at byte \(split)")
        }
    }

    @Test
    func `malformed UTF8 lead does not suppress following ASCII`() {
        let parser = ProcessTerminal()
        let events = parser.parseBytesForTests([[0xE2, 0x41]])
        let characters = events.compactMap { event -> Character? in
            guard case let .key(.character(character), modifiers) = event,
                  modifiers.isEmpty
            else { return nil }
            return character
        }

        #expect(String(characters) == "\u{FFFD}A")
    }

    @Test
    func `malformed UTF8 prefix releases ASCII across read boundaries`() {
        let chunks: [[[UInt8]]] = [
            [[0xE2], [0x41]],
            [[0xF0], [0x41]],
            [[0xF0, 0x9F], [0x41]],
        ]

        for chunks in chunks {
            let parser = ProcessTerminal()
            let events = parser.parseBytesForTests(chunks)
            let characters = events.compactMap { event -> Character? in
                guard case let .key(.character(character), modifiers) = event,
                      modifiers.isEmpty
                else { return nil }
                return character
            }

            #expect(String(characters) == "\u{FFFD}A", "chunks: \(chunks)")
        }
    }

    @Test
    func `valid partial UTF8 scalar remains buffered at a read boundary`() {
        let parser = ProcessTerminal()

        #expect(parser.parseBytesForTests([[0xE2, 0x82]]).isEmpty)

        let events = parser.parseBytesForTests([[0xAC, 0x41]])
        let characters = events.compactMap { event -> Character? in
            guard case let .key(.character(character), modifiers) = event,
                  modifiers.isEmpty
            else { return nil }
            return character
        }
        #expect(String(characters) == "€A")
    }

    @Test
    func `key event normalization line feed treats as enter`() {
        let parser = ProcessTerminal()
        let events = parser.parseForTests("\n")
        #expect(events.contains(where: { if case .key(.enter, _) = $0 { return true }; return false }))
    }

    @Test
    func `stopping an unstarted process terminal does not write terminal control sequences`() throws {
        let outputPipe = Pipe()
        do {
            let terminal = ProcessTerminal(
                inputFileDescriptor: FileHandle.standardInput.fileDescriptor,
                outputFileDescriptor: outputPipe.fileHandleForWriting.fileDescriptor)
            terminal.stop()
        }
        try outputPipe.fileHandleForWriting.close()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        #expect(output.isEmpty)
    }
}
