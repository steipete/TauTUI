import Foundation
import TauTUI

final class KeyLogger: Component {
    private let maxLines = 20
    private var log: [String] = []
    private let requestRender: @MainActor () -> Void

    init(requestRender: @escaping @MainActor () -> Void) {
        self.requestRender = requestRender
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []
        let banner = String(repeating: "=", count: width)
        lines.append(banner)
        let subtitle = "Key Code Tester - Press keys to inspect their events"
        lines.append(subtitle.padding(toLength: width, withPad: " ", startingAt: 0))
        lines.append(banner)
        lines.append("")

        for entry in self.log.suffix(self.maxLines) {
            let padded = if entry.count > width {
                String(entry.prefix(width))
            } else {
                entry.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            lines.append(padded)
        }

        let remaining = max(0, self.maxLines - self.log.count)
        for _ in 0..<remaining {
            lines.append(String(repeating: " ", count: width))
        }

        lines.append(banner)
        let tip = "Try Option+Backspace, Ctrl+Arrows, bracketed paste."
        lines.append(tip.padding(toLength: width, withPad: " ", startingAt: 0))
        lines.append("Press Ctrl+C to exit.".padding(toLength: width, withPad: " ", startingAt: 0))
        lines.append(banner)
        return lines
    }

    func handle(input: TerminalInput) {
        switch input {
        case let .raw(data):
            self.append("RAW  | " + self.describe(data: data))
        case let .paste(text):
            self.append("PASTE| \(text.count) chars")
        case let .key(key, modifiers):
            self.append("KEY  | \(self.describe(key: key, modifiers: modifiers))")
        case let .terminalCellSize(widthPx, heightPx):
            self.append("TERM | cellSize=\(widthPx)x\(heightPx)px")
        }
        let notifier = self.requestRender
        Task { await notifier() }
    }

    private func append(_ text: String) {
        self.log.append(text)
        if self.log.count > self.maxLines {
            self.log.removeFirst(self.log.count - self.maxLines)
        }
    }

    private func describe(data: String) -> String {
        let hex = data.unicodeScalars.map { String(format: "%02x", $0.value) }.joined(separator: " ")
        let codes = data.unicodeScalars.map { String($0.value) }.joined(separator: ",")
        return "hex:[\(hex)] codes:[\(codes)]"
    }

    private func describe(key: TerminalKey, modifiers: KeyModifiers) -> String {
        var parts: [String] = []
        parts.append("\(key)")
        if !modifiers.isEmpty {
            parts.append("mods=\(self.describe(modifiers: modifiers))")
        }
        return parts.joined(separator: " ")
    }

    private func describe(modifiers: KeyModifiers) -> String {
        var comps: [String] = []
        if modifiers.contains(.shift) { comps.append("shift") }
        if modifiers.contains(.option) { comps.append("option") }
        if modifiers.contains(.control) { comps.append("control") }
        if modifiers.contains(.command) { comps.append("command") }
        if modifiers.contains(.meta) { comps.append("meta") }
        return comps.joined(separator: "+")
    }
}

@main
struct KeyTester {
    static func main() {
        let terminal = ProcessTerminal()
        terminal.emitsRawInputEvents = true
        let tui = TUI(terminal: terminal)
        tui.apply(theme: ThemePalette.light())
        let logger = KeyLogger(requestRender: { @MainActor in
            tui.requestRender()
        })
        tui.addChild(logger)
        tui.setFocus(logger)

        do {
            try tui.start()
            RunLoop.main.run()
        } catch {
            let message = "Failed to start key tester: \(error)\n"
            if let data = message.data(using: .utf8) {
                try? FileHandle.standardError.write(contentsOf: data)
            }
            exit(1)
        }
    }
}
