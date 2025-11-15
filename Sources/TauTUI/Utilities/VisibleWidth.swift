import DisplayWidth

/// Wrapper around `swift-displaywidth` that mirrors pi-tui's handling of tabs
/// (converted to three spaces) and ignores ANSI escape sequences before
/// measuring.
public enum VisibleWidth {
    private static let measurer = DisplayWidth()

    public static func measure(_ text: String, tabSize: Int = 3) -> Int {
        guard !text.isEmpty else { return 0 }
        let normalized = Ansi.normalizeTabs(text, spacesPerTab: tabSize)
        let stripped = Ansi.stripCodes(normalized)
        return self.measurer(stripped)
    }
}
