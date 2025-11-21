import Foundation
import TauTUI

struct CLIConfig {
    let scriptPath: String
    let scenario: Scenario
    let outputPath: String?
}

enum Scenario: String {
    case editor
    case select
    case markdown
}

func parseArgs() -> CLIConfig? {
    var scriptPath: String?
    var scenario: Scenario = .editor
    var output: String?

    var idx = 1
    let args = CommandLine.arguments
    while idx < args.count {
        let arg = args[idx]
        switch arg {
        case "--script":
            idx += 1; if idx < args.count { scriptPath = args[idx] }
        case "--scenario":
            idx += 1; if idx < args.count, let sc = Scenario(rawValue: args[idx]) { scenario = sc }
        case "--output":
            idx += 1; if idx < args.count { output = args[idx] }
        default:
            scriptPath = arg
        }
        idx += 1
    }

    guard let scriptPath else { return nil }
    return CLIConfig(scriptPath: scriptPath, scenario: scenario, outputPath: output)
}

guard let config = parseArgs() else {
    print("Usage: TTYSampler --script <path> [--scenario editor|select|markdown] [--output <path>]")
    exit(1)
}

let data = try Data(contentsOf: URL(fileURLWithPath: config.scriptPath))
let script = try JSONDecoder().decode(TTYScript.self, from: data)

let result = try replayTTY(script: script) { vt in
    switch config.scenario {
    case .editor:
        let tui = TUI(terminal: vt)
        let editor = Editor()
        tui.addChild(editor)
        tui.setFocus(editor)
        return tui
    case .select:
        let tui = TUI(terminal: vt)
        let list = SelectList(items: [
            SelectItem(value: "clear", label: "Clear", description: "Remove messages"),
            SelectItem(value: "delete", label: "Delete", description: "Delete last item"),
            SelectItem(value: "theme", label: "Toggle Theme", description: "Flip between dark/light"),
        ])
        tui.addChild(list)
        tui.setFocus(list)
        return tui
    case .markdown:
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

let joined = result.snapshot.joined(separator: "\n")
if let output = config.outputPath {
    try joined.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
} else {
    print(joined)
}
