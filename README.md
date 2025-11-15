# TauTUI

TauTUI is an idiomatic Swift 6 port of [@mariozechner/pi-tui](https://github.com/badlogic/pi-mono/tree/main/packages/tui), Mario Zechner’s excellent TypeScript terminal UI toolkit. The goal is feature parity—differential rendering with synchronized output, bracketed paste support, markdown/text components, autocomplete, and the powerful editor—implemented with Swift-first APIs and testability in mind.

> ⚠️ **Work in progress**: only scaffolding, terminal plumbing, the differential renderer, and some basic components exist today. Follow `docs/spec.md` for the full migration plan.

## Why
- Keep pi-tui’s rock-solid design while exposing Swift idioms (value types, enums, `@Sendable` closures).
- Deliver a pure-Swift foundation for macOS + Linux terminal apps (Windows consoles will not be supported initially).
- Provide a thoroughly tested runtime: VirtualTerminal harness, Swift Tests translated from the original Node specs, and examples like the chat + key tester demos.

## Quick Start
Add TauTUI to your project once the runtime lands:

```swift
// swift-tools-version: 6.2
let package = Package(
    dependencies: [
        .package(url: "https://github.com/yourname/TauTUI.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Demo",
            dependencies: [
                .product(name: "TauTUI", package: "TauTUI"),
            ]
        )
    ]
)
```

Then compose components similar to pi-tui, but in Swift:

```swift
import TauTUI

let terminal = ProcessTerminal()
let tui = /* upcoming TUI runtime */
```

Full examples (chat demo, key tester) will live under `Examples/` once the port reaches parity.

## Platform Support
- ✅ macOS 13+ (Darwin, Swift 6 toolchains)
- ✅ Linux (glibc-based distros tested via CI)
- ❌ Windows consoles are not supported.

## Examples
- `swift run ChatDemo` launches a minimal chat-like interface showcasing `TUI`, `Editor`, autocomplete, and loaders. Source lives under `Examples/ChatDemo` and mirrors the `test/chat-simple.ts` experience from pi-tui.

## Credits
Huge thanks to Mario Zechner and the pi-tui contributors—the architecture, rendering strategy, and components originate from their work. TauTUI’s README, docs, and source files will continue to highlight that lineage.

## Development status
- [x] Spec + scaffolding (`docs/spec.md`)
- [x] VisibleWidth/ANSI helpers (baseline implementation)
- [x] Terminal runtime scaffolding (raw mode, bracketed paste, base renderer)
- [x] Core components: Spacer, Text, Markdown, Input, SelectList, Loader, Editor (baseline)
- [x] Autocomplete provider + filesystem hooks
- [ ] Editor + Loader ports
- [ ] Examples + Swift Test parity suite

If you want to track progress or contribute, start with `docs/spec.md` for the authoritative plan.
