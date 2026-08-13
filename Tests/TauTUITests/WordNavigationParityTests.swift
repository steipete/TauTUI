import Testing
@testable import TauTUI

@Suite("Word navigation parity")
struct WordNavigationParityTests {
    struct Fixture: Sendable {
        let text: String
        let backwardInsertion: String
        let forwardInsertion: String
        let backwardDeletion: String
    }

    static let fixtures = [
        Fixture(
            text: "foo bar... baz",
            backwardInsertion: "foo bar... |baz",
            forwardInsertion: "foo| bar... baz",
            backwardDeletion: "foo bar... "),
        Fixture(
            text: "   foo bar",
            backwardInsertion: "   foo |bar",
            forwardInsertion: "   foo| bar",
            backwardDeletion: "   foo "),
        Fixture(
            text: "foo 😀😀 bar",
            backwardInsertion: "foo 😀😀 |bar",
            forwardInsertion: "foo| 😀😀 bar",
            backwardDeletion: "foo 😀😀 "),
    ]

    @Test(arguments: fixtures)
    func `Input and Editor share word movement`(_ fixture: Fixture) {
        let inputBackward = Input(value: fixture.text)
        inputBackward.handle(input: .key(.arrowLeft, modifiers: [.control]))
        inputBackward.handle(input: .key(.character("|")))

        let editorBackward = Editor()
        editorBackward.setText(fixture.text)
        editorBackward.handle(input: .key(.arrowLeft, modifiers: [.control]))
        editorBackward.handle(input: .key(.character("|")))

        #expect(inputBackward.value == fixture.backwardInsertion)
        #expect(editorBackward.getText() == fixture.backwardInsertion)

        let inputForward = Input(value: fixture.text)
        inputForward.handle(input: .key(.home))
        inputForward.handle(input: .key(.arrowRight, modifiers: [.control]))
        inputForward.handle(input: .key(.character("|")))

        let editorForward = Editor()
        editorForward.setText(fixture.text)
        editorForward.handle(input: .key(.home))
        editorForward.handle(input: .key(.arrowRight, modifiers: [.control]))
        editorForward.handle(input: .key(.character("|")))

        #expect(inputForward.value == fixture.forwardInsertion)
        #expect(editorForward.getText() == fixture.forwardInsertion)
    }

    @Test(arguments: fixtures)
    func `Input and Editor share backward deletion`(_ fixture: Fixture) {
        let input = Input(value: fixture.text)
        input.handle(input: .key(.character("w"), modifiers: [.control]))

        let editor = Editor()
        editor.setText(fixture.text)
        editor.handle(input: .key(.character("w"), modifiers: [.control]))

        #expect(input.value == fixture.backwardDeletion)
        #expect(editor.getText() == fixture.backwardDeletion)
    }
}
