# pi-tui → TauTUI Port Notes & Maintenance Tips

These are the key decisions, learnings, and a playbook for keeping TauTUI in sync with upstream changes to [@mariozechner/pi-tui](https://github.com/badlogic/pi-mono/tree/main/packages/tui).

## Overview
- **Goal:** Swift 6+ port with idiomatic APIs, strong isolation defaults, and testability while preserving pi-tui features (differential rendering, bracketed paste, autocomplete, markdown, editor, loader, input, select list).
- **Theming:** TauTUI mirrors upstream v0.8.0 theming via `EditorTheme`, `SelectListTheme`, `MarkdownTheme`, `LoaderTheme`, and `Text.Background`; defaults keep legacy colors while allowing dynamic updates (call `invalidate()` when swapping).
- **Global theme swaps:** Use `TUI.apply(theme:)` with `ThemePalette` to push themes to theme-aware components; defaults match previous styling so existing apps remain unchanged until they opt in.
- **Status:** Core runtime, components, autocomplete, loader, editor, tests, and a ChatDemo example are implemented. Editor/keybindings are close but not 1:1 yet; this doc helps future syncs.

## Porting Principles We Used
1. **Parity first, polish second:** replicate behavior before API sugar. Only add Swift-idiomatic improvements when they don’t block parity.
2. **Small, testable seams:** utilities (ANSI, width), terminal abstraction, renderer, components, autocomplete, editor in separate files/modules.
3. **Concurrency clarity:** favor main-actor isolation for UI/demo; use `@concurrent` (off-actor work) explicitly. Avoid ad-hoc `Task.detached` to maintain predictability.
4. **Snapshot-able rendering:** VirtualTerminal harness captures CSI output for renderer/component tests (planned expansion).
5. **Composable autocomplete:** `CombinedAutocompleteProvider` mirrors slash+file completion; filesystem and MIME heuristics are centralized.

## Mapping: TS → Swift
- `tui.ts` → `Core/TUI.swift` (differential renderer) + `Terminal/Terminal.swift` + `VirtualTerminal`.
- `terminal.ts` → `Terminal/Terminal.swift` (ProcessTerminal) with raw mode, bracketed paste, resize.
- Components:
  - `text.ts` → `Components/Text.swift`
  - `markdown.ts` → `Components/MarkdownComponent.swift` (table rendering simplified but wrapping/highlighting retained)
  - `input.ts` → `Components/Input.swift`
  - `select-list.ts` → `Components/SelectList.swift`
  - `loader.ts` → `Components/Loader.swift`
  - `editor.ts` → `Components/Editor.swift` (buffer, autocomplete hooks, paste markers)
- Autocomplete: `autocomplete.ts` → `Autocomplete/Autocomplete.swift` + `Utilities/FileAttachmentFilter.swift`.
- Utils: `utils.ts (visibleWidth)` → `Utilities/VisibleWidth.swift`; ANSI helpers → `Utilities/Ansi.swift`.

## Known Behavioral Differences / Simplifications
- **Markdown tables:** currently simplified; alignment/padding may differ from pi-tui’s exact formatting. Improve if upstream changes here.
- **Editor keybindings:** many are ported (enter/shift-enter, tab, arrows, ctrl-U/K/W, option-word moves). Verify any new upstream shortcuts and align. Option+delete-forward currently relies on delete handling; check against upstream.
- **Autocomplete UI:** uses SelectList; behavior matches pi-tui but navigation tests should be expanded when upstream changes filtering/selection logic.
- **Render warnings:** none in library/tests. ChatDemo resolves loader by ID to avoid Sendable warnings; keep demos `@MainActor` to stay warning-free.
- **Key normalization:** ProcessTerminal now emits normalized key events with modifiers (Shift/Ctrl/Option/Meta), including Option+arrow/backspace/delete for word navigation. Components no longer need to parse escape sequences manually.
- **Editor buffer split:** text mutations live in `EditorBuffer` (Sendable) while UI/autocomplete/rendering stay in `Editor`, making future keybinding changes easier and safer to port.
- **Extra tests added:** renderer smoke snapshots, markdown code/quotes, multiple paste markers, slash/file autocomplete ordering + attachment filters, Enter-with-modifier normalization, Ctrl+A/E navigation.

## When Upstream Changes: Step-by-Step
1. **Fetch upstream diff:** inspect `packages/tui/src/*.ts` and `components/*.ts` for logic changes, especially in `tui.ts`, `terminal.ts`, `editor.ts`, `autocomplete.ts`, and component renderers.
2. **Classify change:**
   - Rendering/ANSI logic → update `Core/TUI.swift` or ANSI utilities.
   - Key handling/editor buffer → `Components/Editor.swift` (consider buffer/refactor tests first).
   - Autocomplete/file heuristics → `Autocomplete/Autocomplete.swift`, `FileAttachmentFilter.swift`.
   - Markdown layout → `MarkdownComponent.swift`; add/adjust wrapping tests.
3. **Port incrementally:** mirror the upstream change in Swift in a small patch; add/adjust tests first where possible, then code.
4. **Tests to update/add:**
   - Renderer diffs (VirtualTerminal snapshots) for first render, width change, delta render.
   - Component behavior: Markdown (lists/tables), Input (cursor/backspace), SelectList (filter/selection), Loader tick, Editor (shortcuts, paste markers, autocomplete application).
   - Autocomplete: slash commands, file completion (temp dir fixtures), attachment filter behavior.
5. **Run full suite:** `swift test` (expect zero warnings). If demos warn, fix captures or isolate to `@MainActor` helpers.
6. **Docs:** note significant divergences in `docs/spec.md` and update `docs/pi-tui-porting.md` with any intentional deviations.

## Concurrency & Isolation Tips (tau-specific)
- Library targets default to nonisolated; UI/demo code (ChatDemo) uses `@MainActor` view model. If you add a UI-ish target, set `.defaultIsolation(MainActor.self)` in `Package.swift` or mark types with `@MainActor`.
- Heavy/parallel work: prefer `@concurrent` on functions that should leave the actor; avoid `Task.detached` unless you need isolation breaks.
- Cross-actor data: prefer `Sendable` value types. Use `@unchecked Sendable` sparingly (e.g., RenderCallback weak TUI holder) and document why.
- Demos: resolve non-Sendable UI objects by identity (ObjectIdentifier) inside `@MainActor` contexts when scheduling asyncAfter work.

## Testing Matrix / What to Add Next
- Snapshot tests for TUI diff rendering (VirtualTerminal) to lock CSI output.
- Editor overlay navigation tests (arrow/tab/enter/escape) and modifier shortcuts (option-delete forward, shift-enter variants across terminals).
- Markdown table alignment tests if we improve fidelity.
- Autocomplete selection tests that assert cursor position/prefix replacement.

## Handy Paths & Targets
- Core runtime: `Sources/TauTUI/Core/TUI.swift`, `Terminal/Terminal.swift`, `Terminal/VirtualTerminal.swift`
- Components: `Sources/TauTUI/Components/*`
- Autocomplete: `Sources/TauTUI/Autocomplete/Autocomplete.swift`
- Utilities: `Sources/TauTUI/Utilities/*`
- Tests: `Tests/TauTUITests/*`
- Demo: `Examples/ChatDemo` (`swift run ChatDemo`)
- Concurrency guide: `docs/concurrency.md`
- Port spec: `docs/spec.md`

## Quick Commands
- Run tests: `swift test`
- Run demo: `swift run ChatDemo`
- Strict concurrency (per build): `swift build -Xswiftc -strict-concurrency=complete`

## Future Refactors Worth Considering
- **Extract CSI/ANSI helper:** centralize sync start/end, clear, cursor movement to reduce duplication in TUI/ProcessTerminal/Loader.
- **EditorBuffer separation:** isolate pure buffer logic (Sendable) from UI rendering for cleaner tests and less actor churn.
- **Key event normalization:** build a richer `TerminalKeyEvent` with modifiers to simplify component key handling and tests.

## Contact Points
- Upstream source of truth: https://github.com/badlogic/pi-mono/tree/main/packages/tui
- When in doubt about behavior, run upstream Node tests/demos and snapshot expected output, then mirror in Swift tests.
