import Foundation
import Testing
@testable import TauTUI

@Suite("TTY replayer")
struct TTYReplayerTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TauTUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    private func loadScript(_ name: String) throws -> TTYScript {
        let url = self.repoRoot()
            .appendingPathComponent("Examples/TTYSampler/\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TTYScript.self, from: data)
    }

    private func loadSnapshot(_ name: String) throws -> [String] {
        let url = self.repoRoot()
            .appendingPathComponent("Tests/Fixtures/TTY/\(name).snapshot")
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

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

        let log = result.outputLog.joined()
        #expect(log.contains("Hi"))
        #expect(log.contains("there"))
    }

    @Test
    func selectSnapshotMatchesGolden() async throws {
        let script = try self.loadScript("select")
        let expected = try self.loadSnapshot("select")

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let list = SelectList(items: [
                    SelectItem(value: "clear", label: "Clear", description: "Remove messages"),
                    SelectItem(value: "delete", label: "Delete", description: "Delete last item"),
                    SelectItem(value: "theme", label: "Toggle Theme", description: "Flip between dark/light"),
                ])
                tui.addChild(list)
                tui.setFocus(list)
                return tui
            }
        }

        #expect(result.snapshot == expected)
    }

    @Test
    func markdownSnapshotMatchesGolden() async throws {
        let script = try self.loadScript("markdown")
        let expected = try self.loadSnapshot("markdown")

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let md = MarkdownComponent(text: """
                # TauTUI Sampler
                - Supports **bold**, _italic_, and `code`.
                - Resize + theme events show wrapping + palette.
                """.trimmingCharacters(in: .whitespacesAndNewlines))
                tui.addChild(md)
                return tui
            }
        }

        #expect(result.snapshot == expected)
    }

    @Test
    func markdownTableSnapshotMatchesGolden() async throws {
        let script = try self.loadScript("markdown-table")
        let expected = try self.loadSnapshot("markdown-table")

        let result = try await MainActor.run {
            try replayTTY(script: script) { vt in
                let tui = TUI(terminal: vt)
                let md = MarkdownComponent(text: """
                | Col A | Col B |
                | ----- | ----- |
                | Long cell value that wraps | Short |
                | αβγδεζηθ | 😃 emoji cell |
                """.trimmingCharacters(in: .whitespacesAndNewlines))
                tui.addChild(md)
                return tui
            }
        }

        #expect(result.snapshot == expected)
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
