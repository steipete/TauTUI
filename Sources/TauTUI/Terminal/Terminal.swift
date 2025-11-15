import Dispatch
import Foundation
import SystemPackage

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - Key Models

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let meta = KeyModifiers(rawValue: 1 << 4)
}

public enum TerminalKey: Sendable {
    case character(Character)
    case enter
    case tab
    case backspace
    case delete
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case escape
    case function(Int)
    case unknown(sequence: String)
}

public enum TerminalInput: Sendable {
    case key(TerminalKey, modifiers: KeyModifiers = [])
    case paste(String)
    case raw(String)
}

// MARK: - Terminal Protocol

public protocol Terminal: AnyObject {
    func start(
        onInput: @escaping (TerminalInput) -> Void,
        onResize: @escaping () -> Void
    ) throws

    func stop()
    func write(_ data: String)
    var columns: Int { get }
    var rows: Int { get }
    func moveBy(lines: Int)
    func hideCursor()
    func showCursor()
    func clearLine()
    func clearFromCursor()
    func clearScreen()
}

public enum TerminalError: Error {
    case alreadyRunning
}

// MARK: - ProcessTerminal

public final class ProcessTerminal: Terminal {
    private let inputFD = FileDescriptor.standardInput
    private let outputFD = FileDescriptor.standardOutput

    private var stdinSource: DispatchSourceRead?
    private var resizeSource: DispatchSourceSignal?
    private var inputHandler: ((TerminalInput) -> Void)?
    private var resizeHandler: (() -> Void)?

    private var originalTermios = termios()
    private var rawModeEnabled = false

    private var pendingInput = ""
    private var isInBracketedPaste = false
    private var pasteBuffer = ""

    private static let bracketedPasteStart = "\u{001B}[200~"
    private static let bracketedPasteEnd = "\u{001B}[201~"

    public init() {}

    deinit {
        stop()
    }

    public func start(
        onInput: @escaping (TerminalInput) -> Void,
        onResize: @escaping () -> Void
    ) throws {
        guard stdinSource == nil else { throw TerminalError.alreadyRunning }

        inputHandler = onInput
        resizeHandler = onResize

        try enableRawMode()
        write("\u{001B}[?2004h") // bracketed paste on

        let source = DispatchSource.makeReadSource(fileDescriptor: inputFD.rawValue, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let byteCount = buffer.withUnsafeMutableBytes { pointer -> Int in
                do {
                    return try self.inputFD.read(into: pointer)
                } catch {
                    return 0
                }
            }
            guard byteCount > 0 else { return }
            if let string = String(bytes: buffer.prefix(byteCount), encoding: .utf8) {
                self.handleRawChunk(string)
            }
        }
        source.resume()
        stdinSource = source

        signal(SIGWINCH, SIG_IGN)
        let resizeSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        resizeSource.setEventHandler { [weak self] in
            self?.resizeHandler?()
        }
        resizeSource.resume()
        self.resizeSource = resizeSource
    }

    public func stop() {
        stdinSource?.cancel()
        stdinSource = nil
        resizeSource?.cancel()
        resizeSource = nil

        write("\u{001B}[?2004l") // bracketed paste off
        disableRawMode()

        inputHandler = nil
        resizeHandler = nil
        pendingInput.removeAll(keepingCapacity: false)
        pasteBuffer.removeAll(keepingCapacity: false)
        isInBracketedPaste = false
    }

    public func write(_ data: String) {
        guard let payload = data.data(using: .utf8) else { return }
        try? outputFD.writeAll(payload)
    }

    public var columns: Int {
        currentTerminalSize().columns
    }

    public var rows: Int {
        currentTerminalSize().rows
    }

    public func moveBy(lines: Int) {
        guard lines != 0 else { return }
        if lines > 0 {
            write("\u{001B}[\(lines)B")
        } else {
            write("\u{001B}[\(-lines)A")
        }
    }

    public func hideCursor() {
        write("\u{001B}[?25l")
    }

    public func showCursor() {
        write("\u{001B}[?25h")
    }

    public func clearLine() {
        write("\u{001B}[K")
    }

    public func clearFromCursor() {
        write("\u{001B}[J")
    }

    public func clearScreen() {
        write("\u{001B}[2J\u{001B}[H")
    }

    // MARK: - Raw mode

    private func enableRawMode() throws {
        var term = termios()
        guard tcgetattr(inputFD.rawValue, &term) == 0 else { return }
        originalTermios = term
        var raw = term
        cfmakeraw(&raw)
        if tcsetattr(inputFD.rawValue, TCSAFLUSH, &raw) == 0 {
            rawModeEnabled = true
        }
    }

    private func disableRawMode() {
        guard rawModeEnabled else { return }
        var term = originalTermios
        _ = tcsetattr(inputFD.rawValue, TCSAFLUSH, &term)
        rawModeEnabled = false
    }

    // MARK: - Input parsing

    private func handleRawChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        inputHandler?(.raw(chunk))
        pendingInput.append(chunk)
        processPendingInput()
    }

    private func processPendingInput() {
        while !pendingInput.isEmpty {
            if isInBracketedPaste {
                if let endRange = pendingInput.range(of: Self.bracketedPasteEnd) {
                    pasteBuffer.append(String(pendingInput[..<endRange.lowerBound]))
                    pendingInput.removeSubrange(pendingInput.startIndex..<endRange.upperBound)
                    isInBracketedPaste = false
                    inputHandler?(.paste(pasteBuffer))
                    pasteBuffer.removeAll(keepingCapacity: false)
                    continue
                } else {
                    pasteBuffer.append(pendingInput)
                    pendingInput.removeAll(keepingCapacity: false)
                    return
                }
            }

            if pendingInput.hasPrefix(Self.bracketedPasteStart) {
                pendingInput.removeFirstCharacters(Self.bracketedPasteStart.count)
                isInBracketedPaste = true
                continue
            }

            if let (event, consumed) = parseEscapeSequence() {
                emitKey(event.0, modifiers: event.1)
                pendingInput.removeFirstCharacters(consumed)
                continue
            }

            let char = pendingInput.removeFirst()
            handleCharacter(char)
        }
    }

    private func handleCharacter(_ char: Character) {
        guard let scalar = char.unicodeScalars.first else { return }
        switch scalar.value {
        case 0x0D:
            emitKey(.enter)
        case 0x0A:
            emitKey(.character("\n"))
        case 0x09:
            emitKey(.tab)
        case 0x7F, 0x08:
            emitKey(.backspace)
        default:
            if scalar.value < 0x20 {
                if let letterScalar = UnicodeScalar(scalar.value + 0x60) {
                    emitKey(.character(Character(letterScalar)), modifiers: [.control])
                } else {
                    emitKey(.unknown(sequence: String(char)))
                }
            } else {
                emitKey(.character(char))
            }
        }
    }

    private func parseEscapeSequence() -> ((TerminalKey, KeyModifiers), Int)? {
        guard pendingInput.first == "\u{001B}" else { return nil }
        let scalars = Array(pendingInput.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        let second = scalars[1]

        if second == "[" {
            guard let (sequence, length) = extractCSISequence(from: scalars) else { return nil }
            return (mapCSISequence(sequence), length)
        } else if second == "O" {
            guard scalars.count >= 3 else { return nil }
            let seq = String(String.UnicodeScalarView(scalars[0..<3]))
            return (mapSS3Sequence(seq), 3)
        } else {
            return ((.escape, []), 1)
        }
    }

    private func extractCSISequence(from scalars: [UnicodeScalar]) -> (String, Int)? {
        guard scalars.count >= 3 else { return nil }
        for index in 2..<scalars.count {
            let value = scalars[index].value
            if value >= 0x40 && value <= 0x7E {
                let length = index + 1
                let sequence = String(String.UnicodeScalarView(scalars[0..<length]))
                return (sequence, length)
            }
        }
        return nil
    }

    private func mapCSISequence(_ sequence: String) -> (TerminalKey, KeyModifiers) {
        switch sequence {
        case "\u{001B}[A": return (.arrowUp, [])
        case "\u{001B}[B": return (.arrowDown, [])
        case "\u{001B}[C": return (.arrowRight, [])
        case "\u{001B}[D": return (.arrowLeft, [])
        case "\u{001B}[H", "\u{001B}[1~", "\u{001B}[7~": return (.home, [])
        case "\u{001B}[F", "\u{001B}[4~", "\u{001B}[8~": return (.end, [])
        case "\u{001B}[3~": return (.delete, [])
        case "\u{001B}[Z": return (.tab, [.shift])
        default:
            if let function = functionKeyNumber(from: sequence) {
                return (.function(function), [])
            }
            return (.unknown(sequence: sequence), [])
        }
    }

    private func mapSS3Sequence(_ sequence: String) -> (TerminalKey, KeyModifiers) {
        switch sequence {
        case "\u{001B}OP": return (.function(1), [])
        case "\u{001B}OQ": return (.function(2), [])
        case "\u{001B}OR": return (.function(3), [])
        case "\u{001B}OS": return (.function(4), [])
        case "\u{001B}OH": return (.home, [])
        case "\u{001B}OF": return (.end, [])
        default:
            return (.unknown(sequence: sequence), [])
        }
    }

    private func functionKeyNumber(from sequence: String) -> Int? {
        guard sequence.hasPrefix("\u{001B}[") && sequence.hasSuffix("~") else { return nil }
        let start = sequence.index(sequence.startIndex, offsetBy: 2)
        let end = sequence.index(before: sequence.endIndex)
        let digits = sequence[start..<end]
        guard let value = Int(digits) else { return nil }
        switch value {
        case 11: return 1
        case 12: return 2
        case 13: return 3
        case 14: return 4
        case 15: return 5
        case 17: return 6
        case 18: return 7
        case 19: return 8
        case 20: return 9
        case 21: return 10
        case 23: return 11
        case 24: return 12
        default: return nil
        }
    }

    private func emitKey(_ key: TerminalKey, modifiers: KeyModifiers = []) {
        inputHandler?(.key(key, modifiers: modifiers))
    }

    private func currentTerminalSize() -> (columns: Int, rows: Int) {
        var windowSize = winsize()
        if ioctl(outputFD.rawValue, TIOCGWINSZ, &windowSize) == 0 {
            let cols = Int(windowSize.ws_col)
            let rows = Int(windowSize.ws_row)
            return (max(cols, 1), max(rows, 1))
        }
        return (80, 24)
    }
}

// MARK: - Helpers

private extension FileDescriptor {
    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var remaining = buffer.count
            var pointer = base
            while remaining > 0 {
                let written = try self.write(UnsafeRawBufferPointer(start: pointer, count: remaining))
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }
}

private extension String {
    mutating func removeFirstCharacters(_ count: Int) {
        guard count > 0, count <= self.count else { return }
        let end = index(startIndex, offsetBy: count)
        removeSubrange(startIndex..<end)
    }
}
