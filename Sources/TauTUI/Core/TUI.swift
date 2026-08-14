import Dispatch

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Main runtime responsible for differential rendering and input routing.
@MainActor
public final class TUI: Container {
    struct RenderWidthViolation: Equatable, Sendable {
        let lineIndex: Int
        let visibleWidth: Int
        let maximumWidth: Int
    }

    private let terminal: Terminal
    private let scheduleRender: (@MainActor @Sendable @escaping () -> Void) -> Void
    private var focusedComponent: Component?
    private var theme: ThemePalette = .default

    private var previousLines: [String] = []
    private var previousWidth: Int = 0
    private var previousHeight: Int = 0
    private var cursorRow: Int = 0
    private var renderRequested = false
    private var isRunning = false
    private var sessionGeneration: UInt = 0

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
        self.isRunning = true
        self.sessionGeneration &+= 1
        self.terminal.hideCursor()
        self.queryCellSizeIfNeeded()
        self.requestRender()
    }

    public func stop() {
        guard self.isRunning else { return }
        self.isRunning = false
        self.sessionGeneration &+= 1
        self.renderRequested = false
        self.previousLines = []
        self.previousWidth = 0
        self.previousHeight = 0
        self.cursorRow = 0
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
        guard self.isRunning else { return }
        guard !self.renderRequested else { return }
        self.renderRequested = true
        let generation = self.sessionGeneration
        self.scheduleRender { @MainActor [weak self] in
            guard let self, self.isRunning, self.sessionGeneration == generation else { return }
            self.renderRequested = false
            self.performRender()
        }
    }

    // MARK: - Input

    private func handleInput(_ input: TerminalInput) {
        if case let .terminalCellSize(widthPx, heightPx) = input {
            TerminalImage.setCellDimensions(.init(widthPx: widthPx, heightPx: heightPx))
            self.invalidate()
            self.requestRender()
            return
        }

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

    private func queryCellSizeIfNeeded() {
        guard TerminalImage.getCapabilities().images != nil else { return }
        // Query terminal for cell size in pixels: CSI 16 t
        // Response format: CSI 6 ; height ; width t
        self.terminal.write("\u{001B}[16t")
    }

    // MARK: - Rendering

    private func performRender() {
        let width = self.terminal.columns
        let height = self.terminal.rows
        let newLines = render(width: width)

        guard !newLines.isEmpty else {
            if !self.previousLines.isEmpty {
                self.writePartialRender(lines: [""], from: 0, width: width)
            }
            self.recordRenderState(lines: [], width: width, height: height)
            return
        }

        if self.previousLines.isEmpty {
            self.writeFullRender(newLines, width: width)
            self.recordRenderState(lines: newLines, width: width, height: height)
            return
        }

        if self.previousWidth != width || self.previousHeight != height {
            self.writeFullRender(newLines, width: width, clear: true)
            self.recordRenderState(lines: newLines, width: width, height: height)
            return
        }

        guard let firstChangedLine = self.firstChangedLine(old: self.previousLines, new: newLines) else {
            return // no changes
        }

        let viewportTop = self.cursorRow - height + 1
        if firstChangedLine < viewportTop {
            self.writeFullRender(newLines, width: width, clear: true)
            self.recordRenderState(lines: newLines, width: width, height: height)
            return
        }

        self.writePartialRender(lines: newLines, from: firstChangedLine, width: width)
        self.recordRenderState(lines: newLines, width: width, height: height)
    }

    private func recordRenderState(lines: [String], width: Int, height: Int) {
        self.previousLines = lines
        self.previousWidth = width
        self.previousHeight = height
        self.cursorRow = max(0, lines.count - 1)
    }

    private func firstChangedLine(old: [String], new: [String]) -> Int? {
        for index in 0..<min(old.count, new.count) where old[index] != new[index] {
            return index
        }
        return old.count == new.count ? nil : min(old.count, new.count)
    }

    private func writeFullRender(_ lines: [String], width: Int, clear: Bool = false) {
        self.validateRenderedLines(lines, width: width)
        var buffer = ANSI.syncStart
        if clear {
            buffer += ANSI.clearScrollbackAndScreen
        }
        buffer += lines.joined(separator: "\r\n")
        buffer += ANSI.syncEnd
        self.terminal.write(buffer)
    }

    private func writePartialRender(lines: [String], from start: Int, width: Int) {
        self.validateRenderedLines(lines, width: width, from: start)
        var buffer = ANSI.syncStart
        let lineDiff = start - self.cursorRow
        if lineDiff > 0 {
            buffer += ANSI.cursorDown(lineDiff)
        } else if lineDiff < 0 {
            buffer += ANSI.cursorUp(-lineDiff)
        }

        buffer += ANSI.carriageReturn

        for index in start..<lines.count {
            if index > start { buffer += "\r\n" }
            let line = lines[index]
            buffer += ANSI.clearLine
            buffer += line
        }

        if self.previousLines.count > lines.count {
            let extraLines = self.previousLines.count - lines.count
            if start == lines.count {
                buffer += ANSI.clearLine
            }
            for _ in (start == lines.count ? 1 : 0)..<extraLines {
                buffer += "\r\n" + ANSI.clearLine
            }
            buffer += ANSI.cursorUp(extraLines)
        }

        buffer += ANSI.syncEnd
        self.terminal.write(buffer)
    }

    nonisolated static func firstRenderWidthViolation(
        in lines: [String],
        width: Int,
        from start: Int = 0) -> RenderWidthViolation?
    {
        let lowerBound = min(max(start, 0), lines.count)
        for index in lowerBound..<lines.count where !Self.containsImage(lines[index]) {
            let lineWidth = VisibleWidth.measure(lines[index])
            if lineWidth > width {
                return RenderWidthViolation(
                    lineIndex: index,
                    visibleWidth: lineWidth,
                    maximumWidth: width)
            }
        }
        return nil
    }

    private func validateRenderedLines(_ lines: [String], width: Int, from start: Int = 0) {
        guard let violation = Self.firstRenderWidthViolation(in: lines, width: width, from: start) else { return }
        preconditionFailure(
            "Rendered line \(violation.lineIndex) exceeds terminal width " +
                "(\(violation.visibleWidth) > \(violation.maximumWidth))")
    }

    private nonisolated static func containsImage(_ line: String) -> Bool {
        line.contains("\u{001B}_G") || line.contains("\u{001B}]1337;File=")
    }

    /// Testing/debug helper: render synchronously instead of via requestRender().
    public func renderNow() {
        self.performRender()
    }
}
