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
    func `inserts mixed unicode`() {
        let editor = Editor()
        type("Hello äöü 😀", into: editor)
        #expect(editor.getText() == "Hello äöü 😀")
    }

    @Test
    func `backspace handles single and multi scalar characters`() {
        let editor = Editor()
        type("ä👍", into: editor)

        editor.handle(input: .key(.backspace)) // remove 👍
        #expect(editor.getText() == "ä")

        editor.handle(input: .key(.backspace)) // remove ä
        #expect(editor.getText().isEmpty)
    }

    @Test
    func `arrow navigation across emoji`() {
        let editor = Editor()
        type("😀👍", into: editor)
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.character("x")))
        #expect(editor.getText() == "😀x👍")
    }

    @Test
    func `insert after cursor move over umlauts`() {
        let editor = Editor()
        type("äöü", into: editor)
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.arrowLeft))
        editor.handle(input: .key(.character("x")))
        #expect(editor.getText() == "äxöü")
    }

    @Test
    func `paste preserves unicode and strips control chars`() {
        let editor = Editor()
        editor.handle(input: .paste("Hällö\u{0007} Wörld! 😀 äöüÄÖÜß"))
        #expect(editor.getText() == "Hällö Wörld! 😀 äöüÄÖÜß")
    }

    @Test
    func `preserves umlauts across line breaks`() {
        let editor = Editor()
        type("äöü\nÄÖÜ", into: editor)
        #expect(editor.getText() == "äöü\nÄÖÜ")
    }

    @Test
    func `set text replaces document with unicode`() {
        let editor = Editor()
        editor.setText("Hällö Wörld! 😀 äöüÄÖÜß")
        #expect(editor.getText() == "Hällö Wörld! 😀 äöüÄÖÜß")
    }

    @Test
    func `ctrl A move then insert with unicode present`() {
        let editor = Editor()
        type("äöü", into: editor)
        editor.handle(input: .key(.character("a"), modifiers: [.control]))
        editor.handle(input: .key(.character("X")))
        #expect(editor.getText() == "Xäöü")
    }
}
