import Testing
@testable import TauTUI

@Suite("TTY replayer")
struct TTYReplayerTests {
    @Test
    func replaysEditorScript() async throws {
        let script = TTYScript(
            columns: 40,
            rows: 10,
            events: [
                TTYEvent(type: .key, data: "H", modifiers: nil, columns: nil, rows: nil, ms: nil),
                TTYEvent(type: .key, data: "i", modifiers: nil, columns: nil, rows: nil, ms: nil),
                TTYEvent(type: .key, data: "enter", modifiers: nil, columns: nil, rows: nil, ms: nil),
                TTYEvent(type: .paste, data: "there", modifiers: nil, columns: nil, rows: nil, ms: nil),
            ])

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let editor = Editor()
                tui.addChild(editor)
                tui.setFocus(editor)
                return tui
            }
        }

        let log = result.outputLog.joined(separator: "")
        #expect(log.contains("Hi"))
        #expect(log.contains("there"))
    }

    @Test
    func appliesThemeEvents() async throws {
        let script = TTYScript(
            columns: 20,
            rows: 4,
            events: [
                .init(type: .theme, data: "dark", modifiers: nil, columns: nil, rows: nil, ms: nil),
            ])

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let title = TruncatedText(text: "TTY Sampler", paddingX: 1, paddingY: 0)
                tui.addChild(title)
                return tui
            }
        }

        let snapshot = result.snapshot.joined(separator: "\n")
        #expect(snapshot.contains("[48;2;24;26;32m"))
    }

    @Test
    func resizesEditorAndKeepsWidth() async throws {
        let script = TTYScript(
            columns: 14,
            rows: 6,
            events: [
                .init(type: .key, data: "H", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "e", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "l", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "l", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "o", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "space", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "w", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "o", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "r", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "l", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .key, data: "d", modifiers: nil, columns: nil, rows: nil, ms: nil),
                .init(type: .resize, data: nil, modifiers: nil, columns: 8, rows: 6, ms: nil),
            ])

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let editor = Editor()
                tui.addChild(editor)
                tui.setFocus(editor)
                return tui
            }
        }

        let widest = result.snapshot.map { VisibleWidth.measure($0) }.max() ?? 0
        #expect(widest <= 8)
    }
}
