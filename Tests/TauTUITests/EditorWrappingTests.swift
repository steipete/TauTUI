import Testing
@testable import TauTUI

@Suite("Editor wrapping")
struct EditorWrappingTests {
    @Test
    func wrapsWideEmojisAndPadsToWidth() {
        let editor = Editor()
        let width = 20
        editor.setText("Hello ✅ World")
        let lines = editor.render(width: width)

        for line in lines.dropFirst().dropLast() {
            #expect(VisibleWidth.measure(line) == width)
        }
    }

    @Test
    func wrapsEmojisAtExactBoundary() {
        let editor = Editor()
        let width = 10
        editor.setText("✅✅✅✅✅✅")
        let lines = editor.render(width: width)

        for line in lines.dropFirst().dropLast() {
            #expect(VisibleWidth.measure(line) == width)
        }
    }

    @Test
    func wrapsCJKCharactersByDisplayWidth() {
        let editor = Editor()
        let width = 10
        editor.setText("日本語テスト")

        let lines = editor.render(width: width)
        for line in lines.dropFirst().dropLast() {
            #expect(VisibleWidth.measure(line) == width)
        }

        let plain = lines.dropFirst().dropLast().map { Ansi.stripCodes($0).trimmingCharacters(in: .whitespaces) }
        #expect(plain.count == 2)
        #expect(plain[0] == "日本語テス")
        #expect(plain[1] == "ト")
    }

    @Test
    func mixedASCIIAndWideCharactersFitExactly() {
        let editor = Editor()
        let width = 15
        editor.setText("Test ✅ OK 日本")
        let lines = editor.render(width: width)
        let contentLines = Array(lines.dropFirst().dropLast())
        #expect(contentLines.count == 1)
        #expect(VisibleWidth.measure(contentLines[0]) == width)
    }

    @Test
    func cursorRendersOnWideCharacters() {
        let editor = Editor()
        let width = 20
        editor.setText("A✅B")
        let lines = editor.render(width: width)
        let content = lines[1]
        #expect(content.contains("\u{001B}[7m"))
        #expect(VisibleWidth.measure(content) == width)
    }

    @Test
    func doesNotExceedWidthWithEmojiAtWrapBoundary() {
        let editor = Editor()
        let width = 11
        editor.setText("0123456789✅")
        let lines = editor.render(width: width)
        for line in lines.dropFirst().dropLast() {
            #expect(VisibleWidth.measure(line) <= width)
        }
    }
}
