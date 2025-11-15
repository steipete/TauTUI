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

    // Enter variants some terminals emit with modifiers.
    private static let shiftEnterCSI = "\u{001B}[13;2~"
    private static let optionEnterCSI = "\u{001B}[13;3~"
    private static let optionEnterMeta = "\u{001B}\r"

    public init() {}

    /// Testing helper: parse a raw input string into `TerminalInput` events
    /// without starting Dispatch sources. Only used in unit tests.
    func parseForTests(_ raw: String) -> [TerminalInput] {
        var captured: [TerminalInput] = []
        inputHandler = { captured.append($0) }
        handleRawChunk(raw)
        return captured
    }

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
            write(ANSI.cursorDown(lines))
        } else {
            write(ANSI.cursorUp(-lines))
        }
    }

    public func hideCursor() {
        write("\u{001B}[?25l")
    }

    public func showCursor() {
        write("\u{001B}[?25h")
    }

    public func clearLine() {
        write(ANSI.clearLine)
    }

    public func clearFromCursor() {
        write(ANSI.clearToScreenEnd)
    }

    public func clearScreen() {
        write(ANSI.clearScreen)
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

    fileprivate func handleRawChunk(_ chunk: String) {
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

            // Normalize common Enter-with-modifier sequences emitted as raw data.
            if pendingInput.hasPrefix(Self.shiftEnterCSI) {
                emitKey(.enter, modifiers: [.shift])
                pendingInput.removeFirstCharacters(Self.shiftEnterCSI.count)
                continue
            }
            if pendingInput.hasPrefix(Self.optionEnterCSI) {
                emitKey(.enter, modifiers: [.option])
                pendingInput.removeFirstCharacters(Self.optionEnterCSI.count)
                continue
            }
            if pendingInput.hasPrefix(Self.optionEnterMeta) {
                emitKey(.enter, modifiers: [.option])
                pendingInput.removeFirstCharacters(Self.optionEnterMeta.count)
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
        // Normalize everything that starts with ESC so downstream components
        // only see semantic keys + modifiers. This mirrors xterm-style
        // modifier encodings (CSI 1;{mod}<letter>/~) and the common "Meta"
        // prefix (ESC + key) used by macOS terminals for Option/Alt.
        guard pendingInput.first == "\u{001B}" else { return nil }
        let scalars = Array(pendingInput.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        let second = scalars[1]

        if second == "[" {
            guard let (sequence, length) = extractCSISequence(from: scalars) else { return nil }
            let parsed = mapCSISequence(sequence)
            return (parsed, length)
        } else if second == "O" {
            guard scalars.count >= 3 else { return nil }
            let seq = String(String.UnicodeScalarView(scalars[0..<3]))
            return (mapSS3Sequence(seq), 3)
        } else {
            // ESC + key is treated as Option/Meta on most terminals.
            let consumed = 2
            if second.value == 0x7F { // ESC + DEL (Option+Backspace)
                return ((.backspace, [.option]), consumed)
            }
            let char = Character(String(second))
            switch char {
            case "b": // Option+Left on macOS terminals
                return ((.arrowLeft, [.option]), consumed)
            case "f": // Option+Right
                return ((.arrowRight, [.option]), consumed)
            case "d": // Option+Delete-forward
                return ((.delete, [.option]), consumed)
            default:
                return ((.character(char), [.option]), consumed)
            }
        }
    }

    private func extractCSISequence(from scalars: [UnicodeScalar]) -> (String, Int)? {
        // CSI sequences end with 0x40...0x7E (per ECMA-48). We return the full
        // sequence string and the number of scalars consumed so the caller can
        // trim pendingInput accurately.
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
        // Strip leading ESC[ to isolate params/final byte.
        guard sequence.hasPrefix("\u{001B}[") else { return (.unknown(sequence: sequence), []) }
        let body = sequence.dropFirst(2)
        guard let final = body.last else { return (.unknown(sequence: sequence), []) }
        let paramString = body.dropLast()
        let params = paramString.isEmpty ? [] : paramString.split(separator: ";").compactMap { Int($0) }
        let modifiers = params.count >= 2 ? mapModifiers(from: params.last ?? 1) : []
        let primary = params.first ?? 0

        switch final {
        case "A": return (.arrowUp, modifiers)
        case "B": return (.arrowDown, modifiers)
        case "C": return (.arrowRight, modifiers)
        case "D": return (.arrowLeft, modifiers)
        case "H": return (.home, modifiers)
        case "F": return (.end, modifiers)
        case "Z":
            var mods = modifiers
            mods.insert(.shift) // CSI Z is Shift+Tab; keep explicit flag even if param absent
            return (.tab, mods)
        case "~":
            switch primary {
            case 1, 7: return (.home, modifiers)
            case 4, 8: return (.end, modifiers)
            case 3: return (.delete, modifiers)
            case 11: return (.function(1), modifiers)
            case 12: return (.function(2), modifiers)
            case 13: return (.function(3), modifiers)
            case 14: return (.function(4), modifiers)
            case 15: return (.function(5), modifiers)
            case 17: return (.function(6), modifiers)
            case 18: return (.function(7), modifiers)
            case 19: return (.function(8), modifiers)
            case 20: return (.function(9), modifiers)
            case 21: return (.function(10), modifiers)
            case 23: return (.function(11), modifiers)
            case 24: return (.function(12), modifiers)
            default:
                return (.unknown(sequence: sequence), modifiers)
            }
        default:
            return (.unknown(sequence: sequence), modifiers)
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

    private func emitKey(_ key: TerminalKey, modifiers: KeyModifiers = []) {
        inputHandler?(.key(key, modifiers: modifiers))
    }

    private func mapModifiers(from csiModifier: Int) -> KeyModifiers {
        // xterm encodes modifiers starting at 1 (no modifiers). 2=Shift,
        // 3=Alt/Option, 4=Shift+Alt, 5=Ctrl, 6=Shift+Ctrl, 7=Alt+Ctrl,
        // 8=Shift+Alt+Ctrl. We also map 9..12 to Meta combinations used by
        // some terminals just in case.
        switch csiModifier {
        case 2: return [.shift]
        case 3: return [.option]
        case 4: return [.shift, .option]
        case 5: return [.control]
        case 6: return [.shift, .control]
        case 7: return [.option, .control]
        case 8: return [.shift, .option, .control]
        case 9: return [.meta]
        case 10: return [.shift, .meta]
        case 11: return [.meta, .control]
        case 12: return [.shift, .meta, .control]
        default: return []
        }
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
