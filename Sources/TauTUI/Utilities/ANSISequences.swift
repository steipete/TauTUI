/// Centralized ANSI/CSI escape sequences used across the runtime.
/// Keeps rendering code readable and reduces duplication/typos.
public enum ANSI {
    // Synchronized output (CSI ?2026) for flicker-free updates.
    public static let syncStart = "\u{001B}[?2026h"
    public static let syncEnd = "\u{001B}[?2026l"

    // Clearing helpers
    public static let clearToScreenEnd = "\u{001B}[J"
    public static let clearLine = "\u{001B}[K"
    public static let clearScreen = "\u{001B}[2J\u{001B}[H"
    public static let clearScrollbackAndScreen = "\u{001B}[3J\u{001B}[2J\u{001B}[H"

    // Cursor movement
    public static func cursorUp(_ lines: Int) -> String { "\u{001B}[\(max(lines, 1))A" }
    public static func cursorDown(_ lines: Int) -> String { "\u{001B}[\(max(lines, 1))B" }

    // Carriage return
    public static let carriageReturn = "\r"
}
