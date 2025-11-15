# TauTUI Port Specification

## 1. Purpose & Scope
TauTUI is an idiomatic Swift 6 reimplementation of [@mariozechner/pi-tui](https://github.com/badlogic/pi-mono/tree/main/packages/tui). The goal is feature parity with the TypeScript library—differential rendering, synchronized output, bracketed paste handling, editor/autocomplete, and bundled components—while exposing APIs that feel natural to Swift developers. TauTUI targets macOS and Linux terminals; Windows consoles are explicitly out of scope for the first release.

## 2. Guiding Principles
- **Parity first, polish second**: every feature in pi-tui must exist before shipping, then we add Swift niceties.
- **Swift idioms**: use value types, enums, option sets, `@Sendable` closures, and type-safe colors/keys rather than stringly APIs.
- **Isolation for testability**: small files, focused types, protocol-based seams, and a VirtualTerminal harness allow exhaustive Swift Test coverage.
- **Zero flicker**: keep the three rendering strategies from pi-tui, always wrapping writes with CSI 2026 synchronized output.
- **Credits & licensing**: README and docs must thank Mario Zechner and link to pi-tui; major algorithmic ports should call this out in comments where appropriate.

## 3. Targets & Module Layout
```
TauTUI/                       // SwiftPM package root
  Sources/
    TauTUI/
      Core/                  // Component protocol, Container, TUI runtime
      Terminal/              // Terminal protocol, ProcessTerminal, VirtualTerminal (testable)
      Components/            // Text, Markdown, Input, Editor, etc.
      Autocomplete/
      Utilities/             // VisibleWidth, ANSI helpers, MIME helpers
  Tests/
    TauTUITests/             // Unit + integration tests (mirrors TS specs)
  Examples/
    ChatDemo/
    KeyTester/
  docs/
    spec.md (this file)
```

## 4. Dependencies
| Dependency | Purpose | Platforms |
|------------|---------|-----------|
| [`swift-markdown`](https://github.com/apple/swift-markdown) | Markdown parsing + AST walking for the `Markdown` component | macOS/Linux |
| [`swift-system`](https://github.com/apple/swift-system) | Safe wrappers around POSIX syscalls (`termios`, signals) in `ProcessTerminal` | macOS/Linux |
| [`swift-displaywidth`](https://github.com/ainame/swift-displaywidth) | Accurate wcwidth-style column measurement to replace `string-width` | macOS/Linux |
| `UniformTypeIdentifiers` (Foundation) | MIME/UTI lookup for attachment filtering when available | macOS |
| IBM Kitura MIME tables (vendored) | MIME lookup fallback when UTIs are unavailable | Linux |

No Windows support is planned; Package.swift and README must state this explicitly.

## 5. Key Feature Parity Checklist
- Differential rendering w/ first-render, width-change, and delta modes
- CSI 2026 synchronized output around every flush
- Terminal abstraction with raw-mode, bracketed paste, resize notifications
- Components: Text, Markdown, Input, Editor, SelectList, Loader, Spacer, Container
- Combined autocomplete (slash commands + filesystem + `@` attachments)
- Editor behaviors: autocomplete overlay, bracketed paste markers, large paste substitution, slash command shortcuts, complex key handling, fake cursor rendering
- Utilities: visible width, ANSI-safe wrapping, MIME filters
- Examples: Chat demo and Key tester
- Tests: Markdown rendering (nested lists, tables), rendering diffs, autocomplete, input/editor flows, loader timer

## 6. Terminal Abstraction
### 6.1 Protocol (`Terminal`)
```swift
public protocol Terminal: AnyObject {
    func start(onInput: @escaping @Sendable (TerminalInput) -> Void,
               onResize: @escaping @Sendable () -> Void) throws
    func stop()
    func write(_ data: String)
    var columns: Int { get }
    var rows: Int { get }
    func moveBy(lines: Int)
    func hideCursor()
    func showCursor()
    func clearLine()
    func clearFromCursor()
    func clearScreen()
}
```
`TerminalInput` will be an enum representing parsed key events (see §10), though `ProcessTerminal` will still surface raw bytes for advanced consumers.

### 6.2 `ProcessTerminal`
- Uses `swift-system` for file descriptors, `termios` for raw-mode toggling, and DispatchSources for stdin reads + SIGWINCH.
- Automatically enables/disables bracketed paste (`ESC[?2004h/l`).
- Converts byte streams into `TerminalInput` events plus raw data for components that require the exact escape sequences (Editor).

### 6.3 `VirtualTerminal`
- Lives under `Sources/TauTUI/Terminal` but compiled only for tests via `@testable import`.
- Records viewport + scrollback buffers, exposes `sendInput`, `resize`, `flush`, `viewportLines` to mirror `test/virtual-terminal.ts`.

## 7. Rendering Runtime (`TUI`)
- `Component` protocol replicates `render(width:) -> [String]` and optional `handle(input:)`.
- `Container` holds child components; `TUI` subclasses it.
- `TUI` stores `previousLines`, `previousWidth`, `cursorRow`, and `renderRequested` flag. Render loop mirrors TypeScript logic exactly, including:
  - First render: emit lines without clearing scrollback.
  - Width change or change above viewport: clear scrollback + full redraw.
  - Delta: move cursor, `ESC[J`, re-render changed tail.
- `visibleWidth` guard throws if any component overflows the terminal width.
- `setFocus(_:)` wires keyboard input to a single component at a time.
- `requestRender()` coalesces via `DispatchQueue.main.async`.

## 8. Components
| Component | Swift Notes |
|-----------|-------------|
| `Text` | Struct storing `text`, `padding`, `background`; caches last render; uses `swift-displaywidth` for wrapping. Properties w/ `didSet` to invalidate cache. (✅ implemented) |
| `Markdown` | Uses `swift-markdown` AST; replicates headings, lists, tables, inline styling, padding, and caching. (✅ implemented) |
| `Input` | Maintains cursor index, horizontal scroll window, `onSubmit`. Exposes `value` as `var`. (✅ implemented) |
| `Editor` | Multi-line buffer, autocomplete hooks, paste markers, ctrl/option shortcuts ported; further parity polish (e.g., option-delete-forward) tracked in refactor doc. (✅ implemented) |
| `SelectList` | Maintains filtered items, selection window, `onSelect`/`onCancel`. Supports optional descriptions + scroll indicators. (✅ implemented) |
| `Loader` | Subclass/compose `Text` to render spinner; uses `DispatchSourceTimer` for 80 ms ticks. (✅ implemented) |
| `Spacer` | Simple struct returning N blank lines. (✅ implemented) |
| `Container` | Already part of runtime; consider a `StackContainer` helper for layout convenience.

## 9. Editor Design
- `Editor` = class composed of:
  - `EditorBuffer`: array of `String` lines, cursor line/col, helper mutations (`insert`, `delete`, `moveCursor`, `split`, `merge`).
  - `PasteManager`: tracks bracketed paste state, large paste markers (`[paste #N +xx lines]`), Map from ID → content for substitution on submit.
  - `AutocompleteController`: wraps `AutocompleteProvider`, handles Tab triggers, slash command detection, forced file completion, `SelectList` overlay.
- Rendering: draw horizontal lines (chalk gray equivalent) above/below; show fake cursor via reverse video; append autocomplete list when active (reusing `SelectList` rendering output).
- Input pipeline replicates pi-tui order: bracketed paste start/end, autocomplete keys, Tab logic, control shortcuts (Ctrl+A/E/K/U/W, Option+Backspace, Shift+Enter combos), newline vs submit decision, backspace/delete/arrow keys, printable ASCII insertion.
- Public API:
  ```swift
  final class Editor: Component {
      var text: String { get }
      func setText(_ text: String)
      var disableSubmit: Bool
      var onSubmit: (@Sendable (String) -> Void)?
      var onChange: (@Sendable (String) -> Void)?
      func configure(_ config: TextEditorConfig)
      func setAutocompleteProvider(_ provider: AutocompleteProvider)
  }
  struct TextEditorConfig { /* reserved for future */ }
  ```

## 10. Autocomplete
- Protocols mirror TypeScript (`AutocompleteItem`, `SlashCommand`, `AutocompleteProvider`).
- `CombinedAutocompleteProvider` features:
  - Slash command completion (command names + argument completions).
  - File path completion with tilde expansion, `.`/`..`, `@` attachments, directories-first sorting.
  - Uses `FileManager` for listing, `UniformTypeIdentifiers` (when available) or extension whitelist for deciding “attachable” files. (✅ base implementation in Swift)
  - Force-completion path triggered by Tab; natural trigger occurs when typing path-like tokens.
- Provider returns suggestions + prefix; `Editor` uses them to update the overlay.

## 11. Unicode Width & ANSI Helpers
- Wrap `swift-displaywidth` with a small utility to normalize tabs and strip ANSI sequences before measurement (pi-tui replaces tabs with 3 spaces; we’ll keep that behavior).
- Provide `Ansi.stripCodes(_:)`, `Ansi.visibleSubstring(_:maxColumns:)`, etc., for reuse in `Text` and `Markdown`.

## 12. MIME & Attachment Filtering
- Apple: use `UniformTypeIdentifiers.UTType(filenameExtension:)` to classify files; accept text types, JSON, source code, and images exactly like `isAttachableFile` in `src/autocomplete.ts`.
- Linux: vendor IBM’s MIME lookup tables (from the Kitura projects) to map extensions → MIME; maintain the whitelist arrays from pi-tui for certainty.

## 13. Platform Support Notes
- **macOS**: fully supported. `ProcessTerminal` uses `swift-system` + `DispatchSource` APIs. UTType lookups available.
- **Linux**: supported via same code path; relies on Glibc termios through swift-system and IBM MIME fallback. Needs CI runner (GitHub Actions Ubuntu) to validate raw-mode toggling and tests.
- **Windows**: unsupported. README must clearly state “TauTUI currently targets macOS 13+ and Linux (glibc). Windows consoles are not supported.”

## 14. Swift-Idiomatic API Improvements
- Replace `setX` patterns with Swift properties or builder helpers while keeping naming familiar (e.g., `var text: String { didSet { invalidateCache() } }`).
- Introduce `TerminalKey` enum containing cases like `.character(String)`, `.enter(modifiers: KeyModifiers)`, `.control(Character)`, `.escapeSequence(String)`. This gives components strong typing yet allows raw escape fallbacks.
- Use nested namespaces to declutter: `Autocomplete.Provider`, `Components.Editor`, etc.
- Provide `@discardableResult` builder functions (e.g., `tui.addChild(_:) -> Self`) for chaining.
- Offer async-friendly APIs: `TUI.start(runLoop:) async throws` for clients that want to await completion, plus synchronous `start()` for parity demos.

## 15. Testing Strategy
### 15.1 Unit Tests
- `MarkdownRenderingTests`: port each case from `test/markdown.test.ts`, stripping ANSI sequences before assertions.
- `VisibleWidthTests`: ensure emojis, combining marks, ANSI segments behave; test tab normalization.
- `TextComponentTests`, `SelectListTests`, `AutocompleteProviderTests`, `LoaderTests`.
- `EditorBufferTests`: line splits/merges, delete behaviors, cursor movement bounds.

### 15.2 Integration Tests
- `DifferentialRendererTests`: feed synthetic components into `TUI` + `VirtualTerminal`, assert CSI sequences and viewport outcomes for first render, width change, delta update above viewport, etc.
- `EditorInputTests`: simulate key sequences (Bracketed paste, Tab completion, slash commands) using `VirtualTerminal` to ensure end-to-end behavior.
- `ChatDemoSnapshotTests`: drive the sample app with scripted inputs to ensure message ordering, loader insertion/removal, and Markdown rendering.

### 15.3 CI Matrix
- macOS 15 (Xcode 17 / Swift 6 snapshot)
- Ubuntu 24.04 (Swift 6 toolchain)
- Ensure tests don’t rely on actual terminal state; `VirtualTerminal` isolates them.

## 16. Examples & Documentation
- `Examples/ChatDemo`: Swift port of `test/chat-simple.ts`, showing Text, Markdown, Loader, and Editor composition.
- `Examples/KeyTester`: Swift port logging key codes, useful for debugging escape sequences.
- README outline:
  1. Introduction + screenshots (if possible)
  2. Credits to Mario Zechner & pi-tui (very prominent)
  3. Feature list mirroring pi-tui
  4. Quick start snippet
  5. Component reference summary
  6. Platform support statement (macOS + Linux only)
  7. Testing instructions (`swift test`)
  8. License (MIT, inheriting from pi-tui)

## 17. Migration Phases
1. **Bootstrap**: create SwiftPM package, wire dependencies, stub runtime + README credits.
2. **Core runtime**: Terminal protocol, ProcessTerminal, TUI differential renderer, VisibleWidth utility.
3. **Basic components**: Text, Spacer, Loader, Markdown.
4. **Input primitives**: Input, SelectList, Autocomplete provider.
5. **Editor**: buffer logic, key handling, autocomplete overlay, tests.
6. **Examples & docs**: Chat demo, Key tester, README polish.
7. **Test hardening**: parity checks, CI matrix, lint/docs passes.

## 18. Open Questions (Resolved)
- Wcwidth? → Use `swift-displaywidth`.
- POSIX wrappers? → Use `swift-system`.
- MIME classification on Linux? → Vendor IBM Kitura MIME tables.
- Windows support? → None initially; documented as unsupported.
- API modernization? → Apply the idiomatic adjustments listed in §14 without sacrificing feature parity.

---
Prepared 2025-11-15 for TauTUI planning. EOF
