/// TauTUI is the root module that wires together the runtime, components, and
/// utilities described in `docs/spec.md`. Source files are organized beneath
/// `Sources/TauTUI` (Core, Terminal, Utilities, Components, Autocomplete) to
/// keep responsibilities testable and maintainable.
///
/// The empty namespace below gives downstream clients a stable entry point so
/// we can add static helpers (e.g., logging hooks) later without breaking
/// imports.
public enum TauTUI {}
