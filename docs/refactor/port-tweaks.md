# Refactor Opportunities After the pi-tui Port

These tweaks are low-to-medium effort improvements identified during the port. They’re ordered by impact vs. risk. Pick and choose as needed.

## 1) Centralize ANSI/CSI Helpers (Done)
**Problem:** CSI sequences (sync start/end, clear, cursor moves) were duplicated across TUI, ProcessTerminal, Loader.
**Action:** Added `Utilities/ANSISequences.swift` and replaced literals in `Core/TUI.swift` and `Terminal/Terminal.swift`.
**Benefit:** Less duplication, fewer typos, easier future changes.

## 2) Split Editor Logic from UI (Done)
**Problem:** Editor mixed buffer mutations, autocomplete, and rendering.
**Action:** Introduced `EditorBuffer` (Sendable) to own lines/cursor and word operations; `Editor` now delegates mutations to it while keeping rendering/autocomplete wiring. Tests stay green.
**Benefit:** Clear separation, simpler isolation, easier future tweaks and upstream syncs.

## 3) Normalize Key Events at the Terminal Boundary (Done)
**Problem:** Components parsed escape semantics themselves.
**Action:**
- `ProcessTerminal` now decodes xterm CSI modifiers (Shift/Ctrl/Option/Meta) and Meta-prefix sequences (ESC+key), emitting normalized `TerminalInput.key` events.
- Option variants for arrows/backspace/delete are surfaced as modifiers so components can offer word motions/deletions without manual escape parsing.
- Added unit coverage for Meta-prefix and CSI modifier decoding using `parseForTests` helper.
**Benefit:** Cleaner component code, fewer corner cases, easier to add new shortcuts.

## 4) Strengthen Markdown Table Fidelity (Done)
**Problem:** Table rendering was simplified vs. pi-tui.
**Action:** Implemented column alignment (left/center/right) using Markdown table alignment hints and added a baseline alignment test in `MarkdownTests`.
**Benefit:** Closer parity with upstream; regression coverage for future table tweaks.

## 5) Snapshot Tests for Renderer (Done — basic coverage)
**Problem:** Differential renderer wasn’t guarded by golden outputs.
**Action:** Added `TUIRenderingTests` for first render, resize (full clear + sync), and partial diff (`VirtualTerminal` logs). Serves as smoke snapshots for core renderer paths.
**Next:** Consider file-backed fixtures for broader component coverage (markdown/select-list) if renderer churn increases.

## 6) Sendable Hygiene for Demos (Done)
**Problem:** ChatDemo used identity lookup to avoid Sendable warnings when capturing UI objects.
**Action:** Kept `ChatViewModel` on `@MainActor` and replaced detached task/identity lookup with a `Task { @MainActor ... }` sleep to update the loader directly without Sendable warnings.
**Benefit:** Demo remains warning-free with clearer intent and no identity hacks.

## 7) Align Option+Delete Forward (Done)
**Problem:** Option+backspace was implemented; option+delete-forward differed across terminals.
**Action:** Terminal now recognizes Option+Delete via CSI modifier codes and Meta-prefix ESC+DEL; Editor deletes the word ahead (Alt+D parity) with coverage in `EditorTests`.
**Benefit:** Closer to pi-tui keybinding behavior with tests to guard regressions.

## 8) Package/Build Tweaks (Done)
- Added package-level strict concurrency flag (`-strict-concurrency=complete`) for TauTUI target to guard future changes.
- Still consider a `TauTUIInternal` target for test-only utilities (VirtualTerminal) if API surface becomes a concern.

## Suggested Order
1. ANSI helper (1)
2. Key normalization (3)
3. Editor split (2)
4. Snapshot tests (5)
5. Table fidelity (4)
6. Sendable/demo polish (6)
7. Option+delete-forward parity (7)
8. Build/CI tweaks (8)

## How to Work These In
- Do them incrementally with small PRs; run `swift test` after each.
- Update `docs/pi-tui-porting.md` if behavior changes (especially tables, editor keys).
- Keep demo warning-free to model best practices for consumers.
