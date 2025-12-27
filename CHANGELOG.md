# Changelog

All notable changes to this project will be documented in this file.

## [0.1.5] - Unreleased
- TUI now intercepts Ctrl+C by default (stop terminal + exit), with an override hook and tests.
- Sync pi-mono keyboard handling: enable Kitty keyboard protocol, parse CSI-u sequences, and keep `.raw` input events opt-in (debug-only).
- Input: add common readline-style shortcuts (Ctrl+A/E/U/K/W) plus word navigation/deletion; ignore raw escape sequences.
- Editor: Ctrl+W word deletion now matches whitespace/punctuation run semantics; file-path pastes auto-prepend a safety space when needed.

## [0.1.4] - 2025-11-21
- Added golden snapshots for TTYSampler scenarios (select, markdown, markdown tables) under `Tests/Fixtures/TTY`, with tests that replay scripts for visual regressions.
- TTYSampler gains `markdownTable` scenario and bundled scripts (`markdown.json`, `markdown-table.json`) for wrapping/table coverage.

## [0.1.3] - 2025-11-21
- Extend TTY replayer: `theme` events, space key token, and deterministic `renderNow` driven resize coverage; new tests cover theme flips and editor resize handling.
- TTYSampler CLI gains `select` and `markdown` scenarios plus bundled `select.json`; sample script now toggles dark theme.
- Sync/plan/docs updated to point at the TTY harness for upstream parity debugging.

## [0.1.2] - 2025-11-21
- Add global theming: `ThemePalette` dark/light presets, `apply(theme:)` on TUI/components, ChatDemo `/theme` toggle, KeyTester uses light theme.
- ANSI-aware wrapping/background helper shared across Text/Markdown; new `TruncatedText` aligns truncation/padding with pi-tui.
- Input parity: buffers bracketed paste markers and strips newlines before insert.
- Added tests for wrapping, truncation, theme propagation; docs/spec/sync notes updated.

## [0.1.1] - 2025-11-17
- Allow printable Unicode in editor paste path (drops only control characters) to match upstream pi-tui Unicode input behavior.
- Add Unicode-focused editor tests (emoji, umlauts, cursor movement, control-char stripping).
- Document printable Unicode handling and Alt+Enter newline guidance in spec/README.

## [0.1.0] - 2025-11-15
- Initial TauTUI sync with pi-tui core features (editor, autocomplete, markdown, loader, select list, renderer).
