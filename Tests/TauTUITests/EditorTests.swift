import Testing
@testable import TauTUI

@Suite("Editor")
struct EditorTests {
    @Test
    func typingAndSubmitResetsState() async throws {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        editor.handle(input: .raw("hello"))
        editor.handle(input: .key(.enter, modifiers: []))
        #expect(submitted == "hello")
        #expect(editor.getText().isEmpty)
    }

    @Test
    func newlineCreatesSecondLine() async throws {
        let editor = Editor()
        editor.handle(input: .raw("hello"))
        editor.handle(input: .raw("\nworld"))
        #expect(editor.getText() == "hello\nworld")
    }

    @Test
    func backspaceMergesLines() async throws {
        let editor = Editor()
        editor.setText("hello\nworld")
        editor.handle(input: .key(.home, modifiers: []))
        editor.handle(input: .key(.backspace, modifiers: []))
        #expect(editor.getText() == "helloworld")
    }

    @Test
    func largePasteMarkerReplacedOnSubmit() async throws {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        let pasted = (0..<20).map { "line \($0)" }.joined(separator: "\n")
        editor.handle(input: .paste(pasted))
        #expect(editor.getText().contains("[paste #1"))
        editor.handle(input: .key(.enter, modifiers: []))
        #expect(submitted == pasted)
    }

    @Test
    func ctrlUAndCtrlKDeleteSegments() async throws {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.home, modifiers: []))
        editor.handle(input: .key(.character("k"), modifiers: [.control]))
        #expect(editor.getText() == "")

        editor.setText("hello world")
        editor.handle(input: .key(.end, modifiers: []))
        editor.handle(input: .key(.character("u"), modifiers: [.control]))
        #expect(editor.getText() == "")
    }

    @Test
    func ctrlWDeletesWordBackwards() async throws {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.end, modifiers: []))
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "hello ")
    }
}
