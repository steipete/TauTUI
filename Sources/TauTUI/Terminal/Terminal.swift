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
    case terminalCellSize(widthPx: Int, heightPx: Int)
}

// MARK: - Terminal Protocol

public protocol Terminal: AnyObject {
    func start(
        onInput: @escaping (TerminalInput) -> Void,
        onResize: @escaping () -> Void) throws

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

    /// Emit `.raw` events for debugging/inspection (e.g. KeyTester).
    /// Off by default because `.key`/`.paste` already cover functional input.
    public var emitsRawInputEvents: Bool = false

    private static let bracketedPasteStart = "\u{001B}[200~"
    private static let bracketedPasteEnd = "\u{001B}[201~"

    // Kitty keyboard protocol (disambiguate key sequences).
    // https://sw.kovidgoyal.net/kitty/keyboard-protocol/
    private static let kittyKeyboardProtocolEnable = "\u{001B}[>1u"
    private static let kittyKeyboardProtocolDisable = "\u{001B}[<u"

    // Enter variants some terminals emit with modifiers.
    private static let shiftEnterCSI = "\u{001B}[13;2~"
    private static let optionEnterCSI = "\u{001B}[13;3~"
    private static let optionEnterMeta = "\u{001B}\r"

    public init() {}

    /// Testing helper: parse a raw input string into `TerminalInput` events
    /// without starting Dispatch sources. Only used in unit tests.
    func parseForTests(_ raw: String) -> [TerminalInput] {
        var captured: [TerminalInput] = []
        self.inputHandler = { captured.append($0) }
        self.handleRawChunk(raw)
        return captured
    }

    deinit {
        stop()
    }

    public func start(
        onInput: @escaping (TerminalInput) -> Void,
        onResize: @escaping () -> Void) throws
    {
        guard self.stdinSource == nil else { throw TerminalError.alreadyRunning }

        self.inputHandler = onInput
        self.resizeHandler = onResize

        try self.enableRawMode()
        self.write("\u{001B}[?2004h") // bracketed paste on
        self.write(Self.kittyKeyboardProtocolEnable) // kitty keyboard protocol on

        let source = DispatchSource.makeReadSource(fileDescriptor: self.inputFD.rawValue, queue: .main)
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
        self.stdinSource = source

        signal(SIGWINCH, SIG_IGN)
        let resizeSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        resizeSource.setEventHandler { [weak self] in
            self?.resizeHandler?()
        }
        resizeSource.resume()
        self.resizeSource = resizeSource
    }

    public func stop() {
        self.stdinSource?.cancel()
        self.stdinSource = nil
        self.resizeSource?.cancel()
        self.resizeSource = nil

        self.write("\u{001B}[?2004l") // bracketed paste off
        self.write(Self.kittyKeyboardProtocolDisable) // kitty keyboard protocol off
        self.disableRawMode()

        self.inputHandler = nil
        self.resizeHandler = nil
        self.pendingInput.removeAll(keepingCapacity: false)
        self.pasteBuffer.removeAll(keepingCapacity: false)
        self.isInBracketedPaste = false
    }

    public func write(_ data: String) {
        guard let payload = data.data(using: .utf8) else { return }
        try? self.outputFD.writeAll(payload)
    }

    public var columns: Int {
        self.currentTerminalSize().columns
    }

    public var rows: Int {
        self.currentTerminalSize().rows
    }

    public func moveBy(lines: Int) {
        guard lines != 0 else { return }
        if lines > 0 {
            self.write(ANSI.cursorDown(lines))
        } else {
            self.write(ANSI.cursorUp(-lines))
        }
    }

    public func hideCursor() {
        self.write("\u{001B}[?25l")
    }

    public func showCursor() {
        self.write("\u{001B}[?25h")
    }

    public func clearLine() {
        self.write(ANSI.clearLine)
    }

    public func clearFromCursor() {
        self.write(ANSI.clearToScreenEnd)
    }

    public func clearScreen() {
        self.write(ANSI.clearScreen)
    }

    // MARK: - Raw mode

    private func enableRawMode() throws {
        var term = termios()
        guard tcgetattr(self.inputFD.rawValue, &term) == 0 else { return }
        self.originalTermios = term
        var raw = term
        cfmakeraw(&raw)
        if tcsetattr(self.inputFD.rawValue, TCSAFLUSH, &raw) == 0 {
            self.rawModeEnabled = true
        }
    }

    private func disableRawMode() {
        guard self.rawModeEnabled else { return }
        var term = self.originalTermios
        _ = tcsetattr(self.inputFD.rawValue, TCSAFLUSH, &term)
        self.rawModeEnabled = false
    }

    // MARK: - Input parsing

    fileprivate func handleRawChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        if self.emitsRawInputEvents {
            self.inputHandler?(.raw(chunk))
        }
        self.pendingInput.append(chunk)
        self.processPendingInput()
    }

    private enum ParsedEscape {
        case key(TerminalKey, KeyModifiers)
        case terminalCellSize(widthPx: Int, heightPx: Int)
    }

    private func processPendingInput() {
        while !self.pendingInput.isEmpty {
            if self.isInBracketedPaste {
                if let endRange = pendingInput.range(of: Self.bracketedPasteEnd) {
                    self.pasteBuffer.append(String(self.pendingInput[..<endRange.lowerBound]))
                    self.pendingInput.removeSubrange(self.pendingInput.startIndex..<endRange.upperBound)
                    self.isInBracketedPaste = false
                    self.inputHandler?(.paste(self.pasteBuffer))
                    self.pasteBuffer.removeAll(keepingCapacity: false)
                    continue
                } else {
                    self.pasteBuffer.append(self.pendingInput)
                    self.pendingInput.removeAll(keepingCapacity: false)
                    return
                }
            }

            if self.pendingInput.hasPrefix(Self.bracketedPasteStart) {
                self.pendingInput.removeFirstCharacters(Self.bracketedPasteStart.count)
                self.isInBracketedPaste = true
                continue
            }

            // Normalize common Enter-with-modifier sequences emitted as raw data.
            if self.pendingInput.hasPrefix(Self.shiftEnterCSI) {
                self.emitKey(.enter, modifiers: [.shift])
                self.pendingInput.removeFirstCharacters(Self.shiftEnterCSI.count)
                continue
            }
            if self.pendingInput.hasPrefix(Self.optionEnterCSI) {
                self.emitKey(.enter, modifiers: [.option])
                self.pendingInput.removeFirstCharacters(Self.optionEnterCSI.count)
                continue
            }
            if self.pendingInput.hasPrefix(Self.optionEnterMeta) {
                self.emitKey(.enter, modifiers: [.option])
                self.pendingInput.removeFirstCharacters(Self.optionEnterMeta.count)
                continue
            }

            if let (event, consumed) = parseEscapeSequence() {
                switch event {
                case let .key(key, modifiers):
                    self.emitKey(key, modifiers: modifiers)
                case let .terminalCellSize(widthPx, heightPx):
                    self.inputHandler?(.terminalCellSize(widthPx: widthPx, heightPx: heightPx))
                }
                self.pendingInput.removeFirstCharacters(consumed)
                continue
            }

            let char = self.pendingInput.removeFirst()
            self.handleCharacter(char)
        }
    }

    private func handleCharacter(_ char: Character) {
        guard let scalar = char.unicodeScalars.first else { return }
        switch scalar.value {
        case 0x1B:
            self.emitKey(.escape)
        case 0x0D:
            self.emitKey(.enter)
        case 0x0A:
            self.emitKey(.enter)
        case 0x09:
            self.emitKey(.tab)
        case 0x7F, 0x08:
            self.emitKey(.backspace)
        default:
            if scalar.value < 0x20 {
                if let letterScalar = UnicodeScalar(scalar.value + 0x60) {
                    self.emitKey(.character(Character(letterScalar)), modifiers: [.control])
                } else {
                    self.emitKey(.unknown(sequence: String(char)))
                }
            } else {
                self.emitKey(.character(char))
            }
        }
    }

    private func parseEscapeSequence() -> (ParsedEscape, Int)? {
        // Normalize everything that starts with ESC so downstream components
        // only see semantic keys + modifiers. This mirrors xterm-style
        // modifier encodings (CSI 1;{mod}<letter>/~) and the common "Meta"
        // prefix (ESC + key) used by macOS terminals for Option/Alt.
        guard self.pendingInput.first == "\u{001B}" else { return nil }
        let scalars = Array(pendingInput.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        let second = scalars[1]

        if second == "[" {
            guard let (sequence, length) = extractCSISequence(from: scalars) else { return nil }
            if let cellSize = self.parseCellSizeResponse(sequence) {
                return (.terminalCellSize(widthPx: cellSize.widthPx, heightPx: cellSize.heightPx), length)
            }
            let parsed = self.mapCSISequence(sequence)
            return (.key(parsed.0, parsed.1), length)
        } else if second == "O" {
            guard scalars.count >= 3 else { return nil }
            let seq = String(String.UnicodeScalarView(scalars[0..<3]))
            let mapped = self.mapSS3Sequence(seq)
            return (.key(mapped.0, mapped.1), 3)
        } else {
            // ESC + key is treated as Option/Meta on most terminals.
            let consumed = 2
            if second.value == 0x7F { // ESC + DEL (Option+Backspace)
                return (.key(.backspace, [.option]), consumed)
            }
            let char = Character(String(second))
            switch char {
            case "b": // Option+Left on macOS terminals
                return (.key(.arrowLeft, [.option]), consumed)
            case "f": // Option+Right
                return (.key(.arrowRight, [.option]), consumed)
            case "d": // Option+Delete-forward
                return (.key(.delete, [.option]), consumed)
            default:
                return (.key(.character(char), [.option]), consumed)
            }
        }
    }

    private func parseCellSizeResponse(_ sequence: String) -> (widthPx: Int, heightPx: Int)? {
        // Response format: ESC [ 6 ; height ; width t  (from CSI 16 t query)
        guard sequence.hasPrefix("\u{001B}[") else { return nil }
        guard sequence.hasSuffix("t") else { return nil }

        let body = sequence.dropFirst(2)
        let paramString = body.dropLast()
        let params = paramString.split(separator: ";").compactMap { Int($0) }
        guard params.count >= 3, params[0] == 6 else { return nil }

        let heightPx = params[1]
        let widthPx = params[2]
        guard heightPx > 0, widthPx > 0 else { return nil }

        return (widthPx: widthPx, heightPx: heightPx)
    }

    private func extractCSISequence(from scalars: [UnicodeScalar]) -> (String, Int)? {
        // CSI sequences end with 0x40...0x7E (per ECMA-48). We return the full
        // sequence string and the number of scalars consumed so the caller can
        // trim pendingInput accurately.
        guard scalars.count >= 3 else { return nil }
        for index in 2..<scalars.count {
            let value = scalars[index].value
            if value >= 0x40, value <= 0x7E {
                let length = index + 1
                let sequence = String(String.UnicodeScalarView(scalars[0..<length]))
                return (sequence, length)
            }
        }
        return nil
    }

    // swiftlint:disable cyclomatic_complexity
    private func mapCSISequence(_ sequence: String) -> (TerminalKey, KeyModifiers) {
        // Strip leading ESC[ to isolate params/final byte.
        guard sequence.hasPrefix("\u{001B}[") else { return (.unknown(sequence: sequence), []) }
        let body = sequence.dropFirst(2)
        guard let final = body.last else { return (.unknown(sequence: sequence), []) }
        let paramString = body.dropLast()
        let params = paramString.isEmpty ? [] : paramString.split(separator: ";").compactMap { Int($0) }
        let modifiers = params.count >= 2 ? self.mapModifiers(from: params.last ?? 1) : []
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
        case "u":
            let modParam = params.count >= 2 ? (params.dropFirst().first ?? 1) : 1
            let kittyMods = self.mapKittyModifiers(from: modParam)
            return (self.mapKittyCodepoint(primary, fallbackSequence: sequence), kittyMods)
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

    // swiftlint:enable cyclomatic_complexity

    private func mapSS3Sequence(_ sequence: String) -> (TerminalKey, KeyModifiers) {
        switch sequence {
        case "\u{001B}OP": (.function(1), [])
        case "\u{001B}OQ": (.function(2), [])
        case "\u{001B}OR": (.function(3), [])
        case "\u{001B}OS": (.function(4), [])
        case "\u{001B}OH": (.home, [])
        case "\u{001B}OF": (.end, [])
        default:
            (.unknown(sequence: sequence), [])
        }
    }

    private func emitKey(_ key: TerminalKey, modifiers: KeyModifiers = []) {
        self.inputHandler?(.key(key, modifiers: modifiers))
    }

    private func mapModifiers(from csiModifier: Int) -> KeyModifiers {
        // xterm encodes modifiers starting at 1 (no modifiers). 2=Shift,
        // 3=Alt/Option, 4=Shift+Alt, 5=Ctrl, 6=Shift+Ctrl, 7=Alt+Ctrl,
        // 8=Shift+Alt+Ctrl. We also map 9..12 to Meta combinations used by
        // some terminals just in case.
        switch csiModifier {
        case 2: [.shift]
        case 3: [.option]
        case 4: [.shift, .option]
        case 5: [.control]
        case 6: [.shift, .control]
        case 7: [.option, .control]
        case 8: [.shift, .option, .control]
        case 9: [.meta]
        case 10: [.shift, .meta]
        case 11: [.meta, .control]
        case 12: [.shift, .meta, .control]
        default: []
        }
    }

    private func mapKittyModifiers(from csiModifier: Int) -> KeyModifiers {
        // Kitty protocol transmits (modifierBits + 1). We also mask out lock bits (Caps/Num)
        // so they don’t affect key matching (some terminals include them).
        let raw = max(csiModifier - 1, 0)
        let masked = raw & ~192 // 64 + 128

        var mods: KeyModifiers = []
        if (masked & 1) != 0 { mods.insert(.shift) }
        if (masked & 2) != 0 { mods.insert(.option) }
        if (masked & 4) != 0 { mods.insert(.control) }
        if (masked & 8) != 0 { mods.insert(.command) }
        if (masked & 32) != 0 { mods.insert(.meta) }
        return mods
    }

    private func mapKittyCodepoint(_ codepoint: Int, fallbackSequence: String) -> TerminalKey {
        switch codepoint {
        case 9: return .tab
        case 13: return .enter
        case 27: return .escape
        case 8, 127: return .backspace
        default:
            guard codepoint >= 0, let scalar = UnicodeScalar(UInt32(codepoint)) else {
                return .unknown(sequence: fallbackSequence)
            }
            return .character(Character(scalar))
        }
    }

    private func currentTerminalSize() -> (columns: Int, rows: Int) {
        var windowSize = winsize()
        if ioctl(self.outputFD.rawValue, numericCast(TIOCGWINSZ), &windowSize) == 0 {
            let cols = Int(windowSize.ws_col)
            let rows = Int(windowSize.ws_row)
            return (max(cols, 1), max(rows, 1))
        }
        return (80, 24)
    }
}

// MARK: - Helpers

extension FileDescriptor {
    fileprivate func writeAll(_ data: Data) throws {
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

extension String {
    fileprivate mutating func removeFirstCharacters(_ count: Int) {
        guard count > 0, count <= self.count else { return }
        let end = index(startIndex, offsetBy: count)
        removeSubrange(startIndex..<end)
    }
}
