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
}

extension Component {
    public func handle(input: TerminalInput) {
        // Default: ignore input.
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

    open func render(width: Int) -> [String] {
        self.children.flatMap { $0.render(width: width) }
    }
}
