import Foundation
import Testing
@testable import TauTUI

private func type(_ text: String, into editor: Editor) {
    for char in text {
        editor.handle(input: .key(.character(char)))
    }
}

@Suite("Editor + Unicode")
struct EditorUnicodeTests {
    @Test
    func insertsMixedUnicode() async throws {
        let editor = Editor()
        type("Hello äöü 😀", into: editor)
        #expect(editor.getText() == "Hello äöü 😀")
    }

    @Test
    func backspaceHandlesSingleAndMultiScalarCharacters() async throws {
        let editor = Editor()
        type("ä👍", into: editor)

        editor.handle(input: .key(.backspace)) // remove 👍
        #expect(editor.getText() == "ä")

        editor.handle(input: .key(.backspace)) // remove ä
        #expect(editor.getText().isEmpty)
    }

    @Test
    func arrowNavigationAcrossEmoji() async throws {
        let editor = Editor()
        type("😀👍", into: editor)
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.character("x")))
        #expect(editor.getText() == "😀x👍")
    }

    @Test
    func insertAfterCursorMoveOverUmlauts() async throws {
        let editor = Editor()
        type("äöü", into: editor)
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.character("x")))
        #expect(editor.getText() == "äxöü")
    }

    @Test
    func pastePreservesUnicodeAndStripsControlChars() async throws {
        let editor = Editor()
        editor.handle(input: .paste("Hällö\u{0007} Wörld! 😀 äöüÄÖÜß"))
        #expect(editor.getText() == "Hällö Wörld! 😀 äöüÄÖÜß")
    }

    @Test
    func preservesUmlautsAcrossLineBreaks() async throws {
        let editor = Editor()
        type("äöü\nÄÖÜ", into: editor)
        #expect(editor.getText() == "äöü\nÄÖÜ")
    }

    @Test
    func setTextReplacesDocumentWithUnicode() async throws {
        let editor = Editor()
        editor.setText("Hällö Wörld! 😀 äöüÄÖÜß")
        #expect(editor.getText() == "Hällö Wörld! 😀 äöüÄÖÜß")
    }

    @Test
    func ctrlAMoveThenInsertWithUnicodePresent() async throws {
        let editor = Editor()
        type("äöü", into: editor)
        editor.handle(input: .key(.character("a"), modifiers: [.control]))
        editor.handle(input: .key(.character("X")))
        #expect(editor.getText() == "Xäöü")
    }
}
