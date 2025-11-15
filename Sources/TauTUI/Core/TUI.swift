import Dispatch

/// Main runtime responsible for differential rendering and input routing.
@MainActor
public final class TUI: Container {
    private let terminal: Terminal
    private let scheduleRender: (@escaping () -> Void) -> Void
    private var focusedComponent: Component?

    private var previousLines: [String] = []
    private var previousWidth: Int = 0
    private var cursorRow: Int = 0
    private var renderRequested = false

    private let syncStart = "\u{001B}[?2026h"
    private let syncEnd = "\u{001B}[?2026l"

    public init(terminal: Terminal, renderScheduler: ((@escaping () -> Void) -> Void)? = nil) {
        self.terminal = terminal
        self.scheduleRender = renderScheduler ?? { handler in
            DispatchQueue.main.async(execute: handler)
        }
        super.init(children: [])
    }

    public func setFocus(_ component: Component?) {
        focusedComponent = component
    }

    public func start() throws {
        try terminal.start(onInput: { [weak self] input in
            self?.handleInput(input)
        }, onResize: { [weak self] in
            self?.requestRender()
        })
        terminal.hideCursor()
        requestRender()
    }

    public func stop() {
        terminal.showCursor()
        terminal.stop()
    }

    public func requestRender() {
        guard !renderRequested else { return }
        renderRequested = true
        scheduleRender { [weak self] in
            guard let self else { return }
            self.renderRequested = false
            self.performRender()
        }
    }

    // MARK: - Input

    private func handleInput(_ input: TerminalInput) {
        focusedComponent?.handle(input: input)
        requestRender()
    }

    // MARK: - Rendering

    private func performRender() {
        let width = terminal.columns
        let height = terminal.rows
        let newLines = render(width: width)

        guard !newLines.isEmpty else {
            previousLines = []
            previousWidth = width
            cursorRow = 0
            return
        }

        if previousLines.isEmpty {
            writeFullRender(newLines)
            previousLines = newLines
            previousWidth = width
            cursorRow = newLines.count - 1
            return
        }

        if previousWidth != width {
            writeFullRender(newLines, clear: true)
            previousLines = newLines
            previousWidth = width
            cursorRow = newLines.count - 1
            return
        }

        guard let diffRange = computeDiffRange(old: previousLines, new: newLines) else {
            return // no changes
        }

        let viewportTop = cursorRow - height + 1
        if diffRange.lowerBound < viewportTop {
            writeFullRender(newLines, clear: true)
            previousLines = newLines
            previousWidth = width
            cursorRow = newLines.count - 1
            return
        }

        writePartialRender(lines: newLines, from: diffRange.lowerBound)
        previousLines = newLines
        previousWidth = width
        cursorRow = newLines.count - 1
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
        var buffer = syncStart
        if clear {
            buffer += "\u{001B}[3J\u{001B}[2J\u{001B}[H"
        }
        buffer += lines.joined(separator: "\r\n")
        buffer += syncEnd
        terminal.write(buffer)
    }

    private func writePartialRender(lines: [String], from start: Int) {
        var buffer = syncStart
        let lineDiff = start - cursorRow
        if lineDiff > 0 {
            buffer += "\u{001B}[\(lineDiff)B"
        } else if lineDiff < 0 {
            buffer += "\u{001B}[\(-lineDiff)A"
        }
        buffer += "\r\u{001B}[J"

        for index in start..<lines.count {
            if index > start { buffer += "\r\n" }
            let line = lines[index]
            precondition(VisibleWidth.measure(line) <= terminal.columns, "Rendered line exceeds width")
            buffer += line
        }

        buffer += syncEnd
        terminal.write(buffer)
    }
}
