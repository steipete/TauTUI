# pi-tui sync log (Dec 27, 2025)

Context: upstream `pi-mono` checkout lives at `../../pi-mono` (`/Users/steipete/Projects/pi-mono`) relative to this repo. Current head inspected: `origin/main` at `04fa79e` as of **2025-12-27**. `packages/tui/CHANGELOG.md` latest entry: **0.29.0 (2025-12-25)**.

## Notable upstream changes (TUI)
- Auto-space before pasted file paths (prefix `/`, `~`, `.`) when cursor is after a word char.
- Input: Ctrl+Left/Right + Alt+Left/Right word navigation; Ctrl+W readline-style deletion; full Unicode input.
- Terminal: Kitty keyboard protocol support (CSI `...u` sequences) and more robust escape/lock-bit handling.
- Components: `Box`, `SettingsList`, and `Image` (kitty/iterm2 via `terminal-image`) exports.
- Runtime: query terminal cell pixel size (CSI `16t` → CSI `6;height;widtht`) to size images; diff renderer clears each line (CSI `2K`) and clears extra old lines.

## TauTUI sync status
- `ProcessTerminal`: enables Kitty keyboard protocol, parses CSI-u sequences, maps Escape; `.raw` input events are opt-in (debug-only).
- `Input`/`Editor`: readline-style word motion + deletion parity; paste safety-space for file paths; tests added.
- `Box` + `SettingsList`: Swift ports aligned with pi-mono APIs; tests added.
- `TerminalImage` + `Image`: kitty/iTerm2 encoding + image dimension sniffers (png/jpeg/gif/webp); `TUI` queries + applies cell size; tests added.
- `TUI`: partial diff clears each line (CSI `2K`) and clears trailing old lines; skips width precondition for image escape lines.

# pi-tui sync log (Nov 18–21, 2025)

Context: upstream `pi-mono` checkout lives at `../../pi-mono` (`/Users/steipete/Projects/pi-mono`) relative to this repo. Prior sync covered commits through `ed53fce` (v0.7.13) dated 2025-11-16. Current head inspected: `origin/main` at `45ffe0a` (tags v0.8.0/v0.8.1/v0.8.2) as of **2025-11-21**.

TauTUI sync helpers: use `Examples/TTYSampler` + `Sources/TauTUI/Utilities/TTYReplayer.swift` for replayable scripts that compare Swift rendering to upstream snapshots (handy for resizes, theme flips, and editor interaction). Sample scripts live beside the sampler (`sample.json`, `select.json`).

## Commits (newest → oldest)
- **2025-11-21 — 45ffe0a — Release v0.8.0 (tags v0.8.0–v0.8.2):** rolls out theming across TUI components (themes for Editor, Markdown, SelectList, Loader, Text), new `invalidate()` hook on components/Container, truncation fixes, SelectList selection change callback, autocomplete styling via themes, background coloring via functions, and expansive tests (wrap, truncated text, markdown/theme fixtures).
- **2025-11-20 — 4c12daf — WIP: Add theming system with /theme command:** introduces `MarkdownTheme` interfaces and exports to prepare Markdown for theme injection (superseded/refined by v0.8.0).
- **2025-11-20 — 17d213a — Downgrade Biome to 2.3.5:** tooling/lint change only; no runtime effect for TauTUI.
- **2025-11-19 — aed141a / af0f67a — Thinking level visual feedback:** Editor gains a `borderColor` property (driven by thinking level), SelectList changes bubble selection change events; coding-agent renderer maps thinking levels → border colors.
- **2025-11-18 — 5703a3b — Add ANSI-aware word wrapping:** adds shared `wrapTextWithAnsi` utility (tracks ANSI codes, surrogate pairs, word wrapping) and refactors Text/Markdown to use it; background fill helper revamped.
- **2025-11-18 — 117f0db — feat(coding-agent): add OAuth + bracketed paste in Input:** Input component buffers bracketed paste markers (`\x1b[200~` / `\x1b[201~`) and strips newlines when inserting; rest of commit is coding-agent OAuth plumbing.
- **2025-11-17–20 — v0.7.15 → v0.7.29 tags:** package.json bumps and changelog credits only; no TUI logic changes.

## Porting impact for TauTUI
- **Themeable components (breaking):** Editor now requires an `EditorTheme` (border color + SelectList theme); SelectList renders through injected colors and exposes `onSelectionChange`; Markdown requires a `MarkdownTheme` and now styles bold/italic/links via theme functions; Text/Loader accept background/color functions instead of raw RGB; TruncatedText pads lines fully. Add Swift equivalents and sensible default themes matching current colors.
- **Invalidate lifecycle:** new `invalidate()` on `Component` and `Container` cascades. Update `Component` protocol in Swift, implement no-op/default overrides, and call when themes/settings change.
- **Theme propagation:** `ThemePalette` + `apply(theme:)` live on `TUI` and theme-aware components to make global theme swaps easy.
- **ANSI-aware wrapping:** shared `wrapTextWithAnsi` handles ANSI codes, surrogate pairs, and word boundaries. Port to Swift utility (likely `VisibleWidth` helper) and use in Markdown/Text (and any other wrappers) to avoid color loss or mis-wrapping.
- **Truncation semantics:** TruncatedText now stops at first newline, truncates with reset + ellipsis, and pads every line (including vertical padding) to width. Align Swift’s `TruncatedText` (or equivalent) behavior and add tests.
- **Input bracketed paste:** Upstream Input buffers `[200~`/`[201~` and strips newlines on paste insert. Our pipeline already surfaces `.paste` events via `Terminal`, but verify `Components/Input` mirrors the buffer/cleaning behavior for parity.
- **Thinking-level border color:** Editor exposes `borderColor` to allow dynamic status coloring (used by coding-agent). Ensure Swift editor can accept a border color function and hook it to any thinking-level UI we provide.
- **Tests to mirror:** add Swift test coverage for ANSI-aware wrapping, background application, truncated text padding/truncation, Markdown theme rendering, and Input bracketed paste handling.

## Plan to migrate into TauTUI (Swift)
1) **Theme surface:** define Swift theme structs for Editor, SelectList, Markdown, Loader, Text; thread them through initializers and defaults so existing demos keep current colors. Add SelectList selection-change callback. ✅
2) **Component lifecycle:** extend `Component` protocol with `invalidate()` (default no-op) and propagate through `TUI.Container`; ensure theme switches call invalidate on children. ✅
3) **Wrapping utility:** implement ANSI-aware word wrap helper (preserving SGR state, surrogate pairs) and replace ad-hoc wrapping in Markdown/Text with it; keep using `VisibleWidth` for width math. ✅
4) **Background/truncation updates:** switch background fill helpers to accept color functions; update TruncatedText to first-line-only, reset-before-ellipsis, and fixed-width padding; port new tests. ✅
5) **Editor/Input parity:** add border color injection + SelectList theming in Editor; audit autocomplete creation; confirm Input handles bracketed paste/newline stripping even when delivered as raw input. ✅
6) **Docs:** keep spec/porting docs aligned with theme + wrapping changes; note upstream path (`../../pi-mono`) here for future syncs. ✅
7) **Demos:** ChatDemo `/theme` toggle wired to ThemePalette presets; KeyTester starts with light theme. ✅

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
