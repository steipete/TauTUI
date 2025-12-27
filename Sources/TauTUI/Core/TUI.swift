import Dispatch

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Main runtime responsible for differential rendering and input routing.
@MainActor
public final class TUI: Container {
    private let terminal: Terminal
    private let scheduleRender: (@MainActor @Sendable @escaping () -> Void) -> Void
    private var focusedComponent: Component?
    private var theme: ThemePalette = .default

    private var previousLines: [String] = []
    private var previousWidth: Int = 0
    private var cursorRow: Int = 0
    private var renderRequested = false

    /// Called when Ctrl+C is received. If unset, Ctrl+C will stop the terminal and call `exit(0)`.
    public var onControlC: (@MainActor @Sendable () -> Void)?

    /// When true (default), Ctrl+C is intercepted before forwarding input to the focused component.
    public var handlesControlC: Bool = true

    public init(terminal: Terminal, renderScheduler: ((@MainActor @Sendable @escaping () -> Void) -> Void)? = nil) {
        self.terminal = terminal
        self.scheduleRender = renderScheduler ?? { handler in
            DispatchQueue.main.async(execute: handler)
        }
        super.init(children: [])
    }

    public func setFocus(_ component: Component?) {
        self.focusedComponent = component
    }

    public func start() throws {
        try self.terminal.start(onInput: { [weak self] input in
            self?.handleInput(input)
        }, onResize: { [weak self] in
            self?.requestRender()
        })
        self.terminal.hideCursor()
        self.requestRender()
    }

    public func stop() {
        self.terminal.showCursor()
        self.terminal.stop()
    }

    @MainActor override public func apply(theme: ThemePalette) {
        self.theme = theme
        self.children.forEach { $0.apply(theme: theme) }
        self.invalidate()
        self.requestRender()
    }

    public func requestRender() {
        guard !self.renderRequested else { return }
        self.renderRequested = true
        self.scheduleRender { @MainActor [weak self] in
            guard let self else { return }
            self.renderRequested = false
            self.performRender()
        }
    }

    // MARK: - Input

    private func handleInput(_ input: TerminalInput) {
        if self.handlesControlC,
           case let .key(.character("c"), modifiers) = input,
           modifiers.contains(.control)
        {
            if let onControlC = self.onControlC {
                onControlC()
            } else {
                self.stop()
                exit(0)
            }
            return
        }

        self.focusedComponent?.handle(input: input)
        self.requestRender()
    }

    // MARK: - Rendering

    private func performRender() {
        let width = self.terminal.columns
        let height = self.terminal.rows
        let newLines = render(width: width)

        guard !newLines.isEmpty else {
            self.previousLines = []
            self.previousWidth = width
            self.cursorRow = 0
            return
        }

        if self.previousLines.isEmpty {
            self.writeFullRender(newLines)
            self.previousLines = newLines
            self.previousWidth = width
            self.cursorRow = newLines.count - 1
            return
        }

        if self.previousWidth != width {
            self.writeFullRender(newLines, clear: true)
            self.previousLines = newLines
            self.previousWidth = width
            self.cursorRow = newLines.count - 1
            return
        }

        guard let diffRange = computeDiffRange(old: previousLines, new: newLines) else {
            return // no changes
        }

        let viewportTop = self.cursorRow - height + 1
        if diffRange.lowerBound < viewportTop {
            self.writeFullRender(newLines, clear: true)
            self.previousLines = newLines
            self.previousWidth = width
            self.cursorRow = newLines.count - 1
            return
        }

        self.writePartialRender(lines: newLines, from: diffRange.lowerBound)
        self.previousLines = newLines
        self.previousWidth = width
        self.cursorRow = newLines.count - 1
    }

    private func computeDiffRange(old: [String], new: [String]) -> Range<Int>? {
        let maxCount = max(old.count, new.count)
        var firstChanged: Int?
        var lastChanged: Int?

        for index in 0..<maxCount {
            let oldLine = index < old.count ? old[index] : ""
            let newLine = index < new.count ? new[index] : ""
            if oldLine != newLine {
                if firstChanged == nil { firstChanged = index }
                lastChanged = index
            }
        }

        guard let start = firstChanged, let end = lastChanged else {
            return nil
        }
        return start..<(end + 1)
    }

    private func writeFullRender(_ lines: [String], clear: Bool = false) {
        var buffer = ANSI.syncStart
        if clear {
            buffer += ANSI.clearScrollbackAndScreen
        }
        buffer += lines.joined(separator: "\r\n")
        buffer += ANSI.syncEnd
        self.terminal.write(buffer)
    }

    private func writePartialRender(lines: [String], from start: Int) {
        var buffer = ANSI.syncStart
        let lineDiff = start - self.cursorRow
        if lineDiff > 0 {
            buffer += ANSI.cursorDown(lineDiff)
        } else if lineDiff < 0 {
            buffer += ANSI.cursorUp(-lineDiff)
        }
        buffer += ANSI.carriageReturn + ANSI.clearToScreenEnd

        for index in start..<lines.count {
            if index > start { buffer += "\r\n" }
            let line = lines[index]
            precondition(VisibleWidth.measure(line) <= self.terminal.columns, "Rendered line exceeds width")
            buffer += line
        }

        buffer += ANSI.syncEnd
        self.terminal.write(buffer)
    }

    /// Testing/debug helper: render synchronously instead of via requestRender().
    public func renderNow() {
        self.performRender()
    }
}
