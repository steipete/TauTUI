# TauTUI refactor plan for pi-tui v0.8.0 (Nov 21, 2025)

Context
- Upstream commits inspected at `pi-mono` → `packages/tui` @ `45ffe0a` (tags v0.8.0–v0.8.2) dated 2025-11-21.
- Local upstream checkout lives at `../../pi-mono` (`/Users/steipete/Projects/pi-mono`).
- Prior sync window ended at `ed53fce` (v0.7.13). See `docs/pitui-sync.md` for commit-by-commit details.

Goals
- Bring TauTUI to feature parity with v0.8.0: themeable components, ANSI-aware wrapping, truncation fixes, bracketed paste improvements, and lifecycle invalidation.
- Keep public API stable where possible; add conservative defaults so downstream Swift users are unaffected.

Progress (2025-11-21)
- ✅ Theme surfaces added (Editor/SelectList/Markdown/Text/Loader) with defaults mirroring prior colors.
- ✅ `Component.invalidate()` wired through Container; components implement no-op/ cache clears.
- ✅ ANSI-aware wrapping + background helper (`AnsiWrapping.wrapText`, `applyBackgroundToLine`) used by Text/Markdown.
- ✅ TruncatedText added with padding-to-width and reset-before-ellipsis semantics; wrapping/background tests ported and expanded.
- ✅ Input now buffers bracketed paste markers and strips newlines on paste; new tests cover both `.raw` and `.paste`.
- ✅ Added `ThemePalette` + `apply(theme:)` propagation on `TUI` and components; test covers propagation.
- Pending: optional global theme propagation API (decision needed), doc polish beyond porting notes.
Work items (ordered execution)
1) **Theme surface + defaults**
   - Introduce Swift theme structs for `Editor`, `SelectList`, `Markdown`, `Text`, `Loader` with color functions (not RGB structs).
   - Wire through component initializers; keep existing colors as default theme so demos stay unchanged.
   - Add `SelectList.onSelectionChange` parity.
2) **Component `invalidate()` lifecycle**
   - Extend `Component` protocol with `invalidate()` (default no-op) and cascade from `Container` children.
   - Ensure theme switches or setting changes call `invalidate()` before re-render.
3) **ANSI-aware word wrapping**
   - Port upstream `wrapTextWithAnsi` to Swift (preserve SGR state and surrogate pairs).
   - Swap Markdown/Text (and any other wrappers) to use the shared helper; keep `VisibleWidth` for measurement.
4) **Background + truncation semantics**
   - Update background fill helper to accept color functions and reapply after resets.
   - Align `TruncatedText`: first-line-only, reset-before-ellipsis, pad every line (including vertical padding) to the viewport width.
5) **Editor/Input parity**
   - Editor: accept border color function via theme; ensure autocomplete lists use injected SelectList theme.
   - Input: verify bracketed paste buffering and newline stripping match upstream; add tests if behavior differs.
6) **Docs + tests**
   - Add Swift tests for ANSI wrapping, background fill, truncated text padding/truncation, Markdown theming, and Input bracketed paste.
   - Update `docs/spec.md` and `docs/pi-tui-porting.md` for new theme surface and wrapping rules.

Execution notes
- Keep changes small and in the above order; run the usual Swift test suite after each chunk.
- Reuse existing color defaults to avoid demo regressions; expose themes as opt-in customization points.
- Track any intentional deviations or TODOs in `docs/pi-tui-porting.md`.

Open questions
- Do we want a top-level “theme” container on `TUI` for system-wide propagation, or keep per-component themes for now?
- Should we add a compatibility shim so existing initializers stay source-compatible (e.g., deprecated convenience inits)?
