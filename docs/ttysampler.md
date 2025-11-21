# TTYSampler & TTY Replayer

A small harness to replay scripted terminal events against TauTUI for debugging and regression tests.

## What it is
- **TTY script format:** JSON (or any Decodable payload) describing a viewport size and an ordered list of events (key, paste, raw escape, resize, sleep).
- **Replayer API:** `replayTTY(script:buildTUI:)` (in `Sources/TauTUI/Utilities/TTYReplayer.swift`) runs a script against a `VirtualTerminal`, builds a TUI via your closure, and returns a `TTYReplayResult` containing the final snapshot lines and the raw output log (ANSI included).
- **CLI sampler:** `TTYSampler` executable target (`Examples/TTYSampler`). It loads a script, spins up a simple editor-based TUI (scenario `editor`), replays events, and prints the rendered snapshot (or writes to a file).

## Script schema (JSON)
```jsonc
{
  "columns": 80,           // optional, default 80
  "rows": 24,              // optional, default 24
  "events": [
    { "type": "key",    "data": "H" },
    { "type": "key",    "data": "i" },
    { "type": "key",    "data": "enter" },
    { "type": "paste",  "data": "pasted text" },
    { "type": "sleep",  "ms": 10 },
    { "type": "resize", "columns": 60, "rows": 20 },
    { "type": "theme",  "data": "dark" }
  ]
}
```

Supported event types:
- `key`: `data` is a key token (`enter`, `tab`, `backspace`, `delete`, `left`, `right`, `up`, `down`, `home`, `end`, `space`, or a single character). Optional `modifiers`: `["shift"|"ctrl"|"alt"|"option"|"cmd"|"command"|"meta"]`.
- `paste`: `data` string is inserted via `.paste` event.
- `raw`: `data` is injected as raw input (escape sequences, etc.).
- `resize`: `columns`/`rows` adjust viewport and trigger resize.
- `sleep`: wait `ms` milliseconds.
- `theme`: swap the global `ThemePalette` (`data` is `"dark"` or `"light"`).

## CLI usage
```bash
# Run with sample script
swift run TTYSampler --script Examples/TTYSampler/sample.json

# Save snapshot to file
swift run TTYSampler --script /path/to/script.json --output /tmp/snapshot.txt

# Explicit scenario
swift run TTYSampler --script script.json --scenario editor
swift run TTYSampler --script script.json --scenario select
swift run TTYSampler --script script.json --scenario markdown
```

Output: snapshot lines printed (or saved) representing the final rendered state after replay. ANSI is preserved; pipe through `ansi2txt` if you want plain text.

Scenarios:
- `editor` – single `Editor` focused; great for typing/paste scripts and resize stress.
- `select` – a `SelectList` with a few items to test navigation, theming, and resize padding.
- `markdown` – renders a short Markdown block so you can flip themes and widths to inspect ANSI wrapping.

Bundled scripts (used by `swift run TTYSampler --script Examples/TTYSampler/<file>`):
- `sample.json` – editor typing + paste, resize, and dark theme toggle.
- `select.json` – SelectList navigation with resize + theme flip.
- `markdown.json` – Markdown block with theme flip then tight width to exercise wrapping.
- `markdown-table.json` – Markdown table with wide-cell wrapping and emoji.

Golden snapshots: the rendered output of `select`, `markdown`, and `markdown-table` lives in `Tests/Fixtures/TTY/*.snapshot` and is asserted in `TTYReplayerTests` to catch regressions.

## API usage in tests
```swift
import TauTUI

let script = TTYScript(
    columns: 40,
    rows: 10,
    events: [
        .init(type: .key, data: "H", modifiers: nil, columns: nil, rows: nil, ms: nil),
        .init(type: .key, data: "i", modifiers: nil, columns: nil, rows: nil, ms: nil),
        .init(type: .key, data: "enter", modifiers: nil, columns: nil, rows: nil, ms: nil),
        .init(type: .paste, data: "there", modifiers: nil, columns: nil, rows: nil, ms: nil)
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

// Assert on result.snapshot (rendered lines) or result.outputLog (raw ANSI)
```

## Notes
- `replayTTY` drives rendering synchronously via `renderNow()` to make tests deterministic; it still honors `sleep` events for basic timing gaps.
- `TTYReplayResult.snapshot` is scrollback-aware; `VirtualTerminal.snapshotLines()` includes pending line content.
- The CLI currently has one scenario (`editor`); add more by branching on `Scenario` in `Examples/TTYSampler/main.swift`.
- `Examples/TTYSampler/sample.json` is bundled with the executable target for quick smoke runs.

## Ideas / next steps
- Optional HTML export (ansi-to-html) for visual diffs.
- Script generator to capture real sessions and replay them.
- Add golden snapshots for the sampler scenarios to aid visual diffing in CI.
