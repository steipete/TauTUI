/// Shared component protocol. Mirrors the TypeScript interface in pi-tui but
/// follows Swift naming conventions and uses the strongly-typed
/// `TerminalInput` enum defined in `Terminal/Terminal.swift`.
public protocol Component: AnyObject {
    /// Render the component for the current viewport width. Each string in the
    /// returned array represents an entire terminal line, including ANSI
    /// sequences.
    func render(width: Int) -> [String]

    /// Handle input when the component has focus. Components that do not care
    /// about keyboard events can adopt the default empty implementation.
    func handle(input: TerminalInput)

    /// Invalidate any cached rendering state. Components that don’t cache can
    /// rely on the default no-op implementation.
    func invalidate()

    /// Optional hook for theme updates. Components that support themes should
    /// implement this; others can ignore.
    @MainActor func apply(theme: ThemePalette)
}

extension Component {
    public func handle(input: TerminalInput) {
        // Default: ignore input.
    }

    public func invalidate() {
        // Default: nothing to reset.
    }

    @MainActor public func apply(theme: ThemePalette) {
        // Default: nothing to apply.
    }
}

/// Basic container used by the `TUI` runtime. Components are stored in-order
/// and rendered sequentially; consumers can subclass to add layout logic.
open class Container: Component {
    public private(set) var children: [Component] = []

    public init(children: [Component] = []) {
        self.children = children
    }

    open func addChild(_ child: Component) {
        self.children.append(child)
    }

    open func removeChild(_ child: Component) {
        guard let index = children.firstIndex(where: { $0 === child }) else {
            return
        }
        self.children.remove(at: index)
    }

    open func clear() {
        self.children.removeAll()
    }

    open func invalidate() {
        self.children.forEach { $0.invalidate() }
    }

    @MainActor open func apply(theme: ThemePalette) {
        self.children.forEach { $0.apply(theme: theme) }
    }

    open func render(width: Int) -> [String] {
        self.children.flatMap { $0.render(width: width) }
    }
}
