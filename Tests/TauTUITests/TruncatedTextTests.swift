import Testing
@testable import TauTUI

@Suite("TruncatedText")
struct TruncatedTextTests {
    @Test
    func `pads lines to width`() {
        let text = TruncatedText(text: "Hello world", paddingX: 1, paddingY: 1)
        let lines = text.render(width: 30)
        #expect(lines.count == 3)
        for line in lines {
            #expect(VisibleWidth.measure(line) == 30)
        }
    }

    @Test
    func `truncates with reset and ellipsis`() {
        let text = TruncatedText(text: "This is a very long piece of text", paddingX: 1, paddingY: 0)
        let lines = text.render(width: 15)
        #expect(lines.count == 1)
        #expect(VisibleWidth.measure(lines[0]) == 15)
        #expect(lines[0].contains("\u{001B}[0m..."))
    }

    @Test
    func `respects ansi when truncating`() {
        let colored = "\u{001B}[31mRed text that is long\u{001B}[0m"
        let text = TruncatedText(text: colored, paddingX: 1, paddingY: 0)
        let lines = text.render(width: 18)
        #expect(VisibleWidth.measure(lines[0]) == 18)
        #expect(lines[0].contains("\u{001B}[31m"))
    }

    @Test
    func `stops at first newline`() {
        let text = TruncatedText(text: "First line\nSecond line", paddingX: 1, paddingY: 0)
        let lines = text.render(width: 20)
        #expect(lines.count == 1)
        #expect(lines[0].contains("Second") == false)
    }

    @Test
    func `handles empty text`() {
        let text = TruncatedText(text: "", paddingX: 1, paddingY: 0)
        let lines = text.render(width: 30)
        #expect(lines.count == 1)
        #expect(VisibleWidth.measure(lines[0]) == 30)
    }

    @Test
    func `fits exactly without ellipsis`() {
        let text = TruncatedText(text: "Hello world", paddingX: 1, paddingY: 0)
        let lines = text.render(width: 30)
        #expect(lines.count == 1)
        #expect(VisibleWidth.measure(lines[0]) == 30)
        #expect(!lines[0].contains("..."))
    }
}
