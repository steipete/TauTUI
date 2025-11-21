import Testing
@testable import TauTUI

@Suite("ANSI wrapping")
struct AnsiWrappingTests {
    @Test
    func wrapsTextWithAnsiPreservingWidth() async throws {
        let text = "\u{001B}[31mHello world from TauTUI\u{001B}[0m"
        let wrapped = AnsiWrapping.wrapText(text, width: 8)
        #expect(!wrapped.isEmpty)
        #expect(wrapped.allSatisfy { VisibleWidth.measure($0) <= 8 })
        #expect(wrapped.first?.contains("\u{001B}[31m") == true)
    }

    @Test
    func wrapsSurrogatePairs() async throws {
        let text = "Hi 😀 there"
        let wrapped = AnsiWrapping.wrapText(text, width: 6)
        #expect(wrapped.count == 2)
        #expect(VisibleWidth.measure(wrapped[0]) <= 6)
        #expect(VisibleWidth.measure(wrapped[1]) <= 6)
    }

    @Test
    func applyBackgroundPadsAndKeepsResets() async throws {
        let bg = AnsiStyling.Background.rgb(0, 255, 0)
        let line = "\u{001B}[1mhello\u{001B}[0m world"
        let result = AnsiWrapping.applyBackgroundToLine(line, width: 20, background: bg)
        #expect(VisibleWidth.measure(result) == 20)
        // Background should be reapplied after reset
        #expect(result.contains(bg.start))
    }
}
