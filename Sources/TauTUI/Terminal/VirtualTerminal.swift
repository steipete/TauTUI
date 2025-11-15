import Foundation

/// Lightweight terminal implementation for unit tests. It does not attempt to
/// emulate cursor movement; instead it records every write so tests can inspect
/// ANSI sequences and payloads emitted by the renderer.
public final class VirtualTerminal: Terminal {
    public private(set) var columns: Int
    public private(set) var rows: Int
    public private(set) var outputLog: [String] = []

    private var inputHandler: ((TerminalInput) -> Void)?
    private var resizeHandler: (() -> Void)?
    private var isRunning = false

    public init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    public func start(
        onInput: @escaping (TerminalInput) -> Void,
        onResize: @escaping () -> Void
    ) throws {
        guard !isRunning else { throw TerminalError.alreadyRunning }
        isRunning = true
        inputHandler = onInput
        resizeHandler = onResize
    }

    public func stop() {
        isRunning = false
        inputHandler = nil
        resizeHandler = nil
    }

    public func write(_ data: String) {
        outputLog.append(data)
    }

    public func moveBy(lines: Int) {
        // For completeness we record cursor movement.
        guard lines != 0 else { return }
        let sequence = lines > 0 ? "\u{001B}[\(lines)B" : "\u{001B}[\(-lines)A"
        outputLog.append(sequence)
    }

    public func hideCursor() {
        outputLog.append("\u{001B}[?25l")
    }

    public func showCursor() {
        outputLog.append("\u{001B}[?25h")
    }

    public func clearLine() {
        outputLog.append("\u{001B}[K")
    }

    public func clearFromCursor() {
        outputLog.append("\u{001B}[J")
    }

    public func clearScreen() {
        outputLog.append("\u{001B}[2J\u{001B}[H")
    }

    /// Simulate user input for tests.
    public func sendInput(_ input: TerminalInput) {
        inputHandler?(input)
    }

    /// Change the viewport size and trigger resize callback.
    public func resize(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        resizeHandler?()
    }
}
