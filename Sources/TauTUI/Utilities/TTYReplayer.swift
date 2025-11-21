import Foundation

public struct TTYEvent: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case key
        case paste
        case raw
        case resize
        case sleep
        case theme // data: "dark" | "light"
    }

    public let type: Kind
    public let data: String?
    public let modifiers: [String]?
    public let columns: Int?
    public let rows: Int?
    public let ms: Int?
}

public struct TTYScript: Decodable, Sendable {
    public let columns: Int?
    public let rows: Int?
    public let events: [TTYEvent]
}

public struct TTYReplayResult: Sendable {
    public let snapshot: [String]
    public let outputLog: [String]
}

/// Replay a scripted sequence of terminal events against the provided TUI builder.
/// The builder receives a VirtualTerminal configured with the script dimensions.
@MainActor
public func replayTTY(
    script: TTYScript,
    buildTUI: (VirtualTerminal) throws -> TUI
) throws -> TTYReplayResult {
    let vt = VirtualTerminal(columns: script.columns ?? 80, rows: script.rows ?? 24)
    let tui = try buildTUI(vt)
    try tui.start()

    for event in script.events {
        switch event.type {
        case .sleep:
            if let ms = event.ms, ms > 0 {
                usleep(useconds_t(ms * 1000))
            }
        case .resize:
            vt.resize(columns: event.columns ?? vt.columns, rows: event.rows ?? vt.rows)
        case .paste:
            if let data = event.data {
                vt.sendInput(.paste(data))
            }
        case .raw:
            if let data = event.data {
                vt.sendInput(.raw(data))
            }
        case .key:
            if let data = event.data {
                let key = parseKey(data)
                let mods = parseModifiers(event.modifiers)
                vt.sendInput(.key(key, modifiers: mods))
            }
        case .theme:
            let palette: ThemePalette = {
                if let data = event.data?.lowercased(), data == "light" { return .light() }
                return .dark()
            }()
            tui.apply(theme: palette)
        }
        tui.renderNow()
    }

    tui.renderNow()
    tui.stop()
    return TTYReplayResult(snapshot: vt.snapshotLines(), outputLog: vt.outputLog)
}

private func parseKey(_ token: String) -> TerminalKey {
    switch token.lowercased() {
    case "enter", "return": return .enter
    case "tab": return .tab
    case "backspace", "bs": return .backspace
    case "delete", "del": return .delete
    case "left": return .arrowLeft
    case "right": return .arrowRight
    case "up": return .arrowUp
    case "down": return .arrowDown
    case "home": return .home
    case "end": return .end
    case "space": return .character(" ")
    default:
        if token.count == 1, let first = token.first {
            return .character(first)
        }
        return .unknown(sequence: token)
    }
}

private func parseModifiers(_ tokens: [String]?) -> KeyModifiers {
    guard let tokens else { return [] }
    var mods: KeyModifiers = []
    for t in tokens {
        switch t.lowercased() {
        case "shift": mods.insert(.shift)
        case "ctrl", "control": mods.insert(.control)
        case "alt", "option": mods.insert(.option)
        case "cmd", "command": mods.insert(.command)
        case "meta": mods.insert(.meta)
        default: break
        }
    }
    return mods
}
