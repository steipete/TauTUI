# pi-tui sync log (Nov 15–17, 2025)

Context: track upstream changes in `packages/tui` from `pi-mono` since **2025-11-15** (last pre-window commit: `1afe40e` / v0.7.10). Current head inspected: `origin/main` as of **2025-11-17**.

## Commits (newest → oldest)
- **2025-11-16 23:08 CET — ed53fce — v0.7.13:** version bump after Unicode input fix (no code changes).
- **2025-11-16 23:06 CET — a032d41 — merge fix/support-umlauts-and-unicode:** pulls in editor Unicode work + README tweak; keeps new tests.
- **2025-11-16 23:05 CET — adc8b0e — refactor:** clarifies the Unicode filter by checking `charCodeAt(0) >= 32` for regular characters.
- **2025-11-16 22:56 CET — b2491aa — v0.7.12:** version bump for models.json work (no TUI code touched).
- **2025-11-16 21:05 CET — 7efcda6 — test(editor):** reorganizes Unicode tests for clarity.
- **2025-11-16 21:01 CET — fd2b2ec — Filter model selector…:** only bumps `packages/tui/package.json`; logic elsewhere.
- **2025-11-16 18:15 CET — 500e0f8 — test(editor):** adds coverage for umlauts, emojis, cursor movement over multi-code-unit chars, Backspace on surrogate pairs, setText with Unicode, and Ctrl+A insertion.
- **2025-11-16 18:09 CET — efa6a00 — feat(tui):** functional change—editor now treats any `charCode >= 32` as insertable (was ASCII-only) and updates keybinding docs to note `Alt+Enter` as the most reliable “new line” chord.

## Porting impact for TauTUI
- **Input filtering:** `packages/tui/src/components/editor.ts` now allows all printable Unicode (`charCode >= 32`) and removes the upper ASCII bound in paste filtering. Our Swift `Editor` still limits pasted characters to scalars `<= 126` (see `Sources/TauTUI/Components/Editor.swift`, `handlePaste`), so Unicode input/paste parity is missing—needs to be relaxed to `>= 32` with no upper bound.
- **Keybinding doc:** Upstream README calls out `Alt+Enter` as the most reliable way to insert a newline in terminals; mirror this note in our docs (`docs/spec.md` and/or README) when we next touch keybinding guidance.
- **Tests to mirror:** Upstream added explicit Unicode scenarios. Add equivalent Swift tests covering:
  - Mixed ASCII + umlaut + emoji insertion stays literal.
  - Backspace over single-code-unit umlauts vs. multi-code-unit emojis (requiring two deletes).
  - Cursor movement across multi-code-unit emojis before insertion.
  - Unicode preserved across newlines and via `setText`/paste.
  - Ctrl+A move-to-start followed by insertion with Unicode present.
- **Version-only commits:** b2491aa/fd2b2ec/ed53fce are version bumps; no TauTUI action beyond tracking upstream tag alignment.

## Next steps
1) Update `Editor.handlePaste` (and any other printable-character guards) to accept all `>= 0x20` code points.  
2) Add the Unicode-focused tests to `Tests/TauTUITests` to verify Backspace behavior on surrogate pairs.  
3) Refresh newline keybinding wording to include `Alt+Enter` reliability note.
