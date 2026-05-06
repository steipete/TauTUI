import Testing
@testable import TauTUI

@Suite("ANSI wrapping")
struct AnsiWrappingTests {
    @Test
    func `wraps text with ansi preserving width`() {
        let text = "\u{001B}[31mHello world from TauTUI\u{001B}[0m"
        let wrapped = AnsiWrapping.wrapText(text, width: 8)
        #expect(!wrapped.isEmpty)
        #expect(wrapped.allSatisfy { VisibleWidth.measure($0) <= 8 })
        #expect(wrapped.first?.contains("\u{001B}[31m") == true)
    }

    @Test
    func `wraps surrogate pairs`() {
        let text = "Hi 😀 there"
        let wrapped = AnsiWrapping.wrapText(text, width: 6)
        #expect(wrapped.count == 2)
        #expect(VisibleWidth.measure(wrapped[0]) <= 6)
        #expect(VisibleWidth.measure(wrapped[1]) <= 6)
    }

    @Test
    func `apply background pads and keeps resets`() {
        let bg = AnsiStyling.Background.rgb(0, 255, 0)
        let line = "\u{001B}[1mhello\u{001B}[0m world"
        let result = AnsiWrapping.applyBackgroundToLine(line, width: 20, background: bg)
        #expect(VisibleWidth.measure(result) == 20)
        // Background should be reapplied after reset
        #expect(result.contains(bg.start))
    }

    @Test
    func `underline does not start before styled text`() {
        let underlineOn = "\u{001B}[4m"
        let underlineOff = "\u{001B}[24m"
        let url = "https://example.com/very/long/path/that/will/wrap"
        let text = "read this thread \(underlineOn)\(url)\(underlineOff)"

        let wrapped = AnsiWrapping.wrapText(text, width: 40)
        #expect(wrapped.count >= 2)
        #expect(wrapped[0] == "read this thread ")
        #expect(wrapped[1].hasPrefix(underlineOn))
        #expect(wrapped[1].contains("https://"))
    }

    @Test
    func `underline does not bleed into padding`() {
        let underlineOn = "\u{001B}[4m"
        let underlineOff = "\u{001B}[24m"
        let url = "https://example.com/very/long/path/that/will/definitely/wrap"
        let text = "prefix \(underlineOn)\(url)\(underlineOff) suffix"

        let wrapped = AnsiWrapping.wrapText(text, width: 30)
        #expect(wrapped.count >= 2)

        for line in wrapped.dropLast() where line.contains(underlineOn) {
            #expect(line.hasSuffix(underlineOff))
            #expect(!line.hasSuffix("\u{001B}[0m"))
        }
    }

    @Test
    func `preserves background across wrapped lines without full reset`() {
        let bgBlue = "\u{001B}[44m"
        let reset = "\u{001B}[0m"
        let text = "\(bgBlue)hello world this is blue background text\(reset)"

        let wrapped = AnsiWrapping.wrapText(text, width: 15)
        #expect(wrapped.count >= 2)

        for line in wrapped {
            #expect(line.contains(bgBlue))
        }

        for line in wrapped.dropLast() {
            #expect(!line.hasSuffix(reset))
        }
    }

    @Test
    func `preserves foreground across wraps without full reset`() {
        let red = "\u{001B}[31m"
        let reset = "\u{001B}[0m"
        let text = "\(red)hello world this is red text that wraps\(reset)"

        let wrapped = AnsiWrapping.wrapText(text, width: 10)
        #expect(wrapped.count >= 2)

        for line in wrapped.dropFirst() {
            #expect(line.hasPrefix(red))
        }

        for line in wrapped.dropLast() {
            #expect(!line.hasSuffix(reset))
        }
    }

    @Test
    func `resets underline but preserves background across wraps`() {
        let underlineOn = "\u{001B}[4m"
        let underlineOff = "\u{001B}[24m"
        let reset = "\u{001B}[0m"

        let text = "\u{001B}[41mprefix \(underlineOn)UNDERLINED_CONTENT_THAT_WRAPS\(underlineOff) suffix\(reset)"

        let wrapped = AnsiWrapping.wrapText(text, width: 20)
        #expect(wrapped.count >= 2)

        for line in wrapped {
            let hasBg =
                line.contains("\u{001B}[41m") ||
                line.contains(";41m") ||
                line.contains("[41;")
            #expect(hasBg)
        }

        for line in wrapped.dropLast() {
            if line.contains(underlineOn) || line.contains("[4;") || line.contains(";4m") {
                #expect(line.hasSuffix(underlineOff))
                #expect(!line.hasSuffix(reset))
            }
        }
    }
}
