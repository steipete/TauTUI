# Refactor Opportunities After the pi-tui Port

These tweaks are low-to-medium effort improvements identified during the port. They’re ordered by impact vs. risk. Pick and choose as needed.

## 1) Centralize ANSI/CSI Helpers (Done)
**Problem:** CSI sequences (sync start/end, clear, cursor moves) were duplicated across TUI, ProcessTerminal, Loader.
**Action:** Added `Utilities/ANSISequences.swift` and replaced literals in `Core/TUI.swift` and `Terminal/Terminal.swift`.
**Benefit:** Less duplication, fewer typos, easier future changes.

## 2) Split Editor Logic from UI (Medium Effort, Big Testability Win)
**Problem:** Editor mixes buffer mutations, autocomplete, and rendering in one class, making Sendable/testing harder.
**Plan:**
- Create `EditorBuffer` (Sendable) for lines/cursor/paste markers and mutations (insert/delete/move/by-word).
- Keep `EditorView` (current render + autocomplete overlay wiring) actor-bound.
- Rewrite tests to hit `EditorBuffer` directly for shortcut/paste flows; keep render tests minimal.
**Benefit:** Clear separation, simpler isolation, faster unit tests for buffer logic, easier to align with upstream changes.

## 3) Normalize Key Events at the Terminal Boundary (Medium)
**Problem:** Components parse escape semantics themselves.
**Plan:**
- Extend `TerminalInput.key` to carry a richer `KeyEvent` (key + modifiers + semantic flags like word-move).
- Move escape-sequence parsing entirely into `ProcessTerminal`, so `Editor/Input/SelectList` consume normalized events.
**Benefit:** Cleaner component code, fewer corner cases, easier to add new shortcuts.

## 4) Strengthen Markdown Table Fidelity (Optional)
**Problem:** Table rendering is simplified vs. pi-tui.
**Plan:**
- Implement column alignment/padding more closely to upstream; add width clamping tests.
- Add snapshot-like tests for tables (ANSI stripped) mirroring upstream cases.
**Benefit:** Higher parity; safer future merges when pi-tui changes table logic.

## 5) Snapshot Tests for Renderer (Medium)
**Problem:** Differential renderer isn’t guarded by golden outputs.
**Plan:**
- Use `VirtualTerminal` to capture buffers for first render, width change, and delta updates; store as fixtures.
- Add a few markdown/select-list/text snapshots to catch regressions.
**Benefit:** Confident refactors in renderer and components.

## 6) Sendable Hygiene for Demos (Low)
**Problem:** ChatDemo needed identity lookup to avoid warnings when capturing non-Sendable UI objects.
**Plan:**
- Keep demo state `@MainActor`; add a tiny wrapper type (e.g., `MainActorLoaderHandle`) or mark Loader demo-only extensions as `@MainActor`.
**Benefit:** Zero warnings without identity workarounds.

## 7) Align Option+Delete Forward (Parity Polish)
**Problem:** Option+backspace is implemented; option+delete-forward may behave differently across terminals.
**Plan:**
- Add a key test for ESC + DEL (common mapping) and adjust `Editor.handleKey` to drop the word ahead.
**Benefit:** Closer to pi-tui keybinding behavior.

## 8) Package/Build Tweaks
- Consider a `TauTUIInternal` target for test-only utilities (VirtualTerminal) to keep public API surface lean.
- Add `SWIFT_STRICT_CONCURRENCY=complete` to CI to ensure new code stays warning-free.

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
