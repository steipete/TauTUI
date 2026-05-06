import Foundation
import Testing
@testable import TauTUI

private struct TestCommand: SlashCommand {
    let name: String
    let description: String? = nil
    func argumentCompletions(prefix: String) -> [AutocompleteItem] {
        []
    }
}

private func type(_ text: String, into editor: Editor) {
    for char in text {
        editor.handle(input: .key(.character(char)))
    }
}

private final class StubAutocompleteProvider: AutocompleteProvider {
    var suggestion: AutocompleteSuggestion?
    var triggerFileCompletion = true

    func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?
    {
        self.suggestion
    }

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int)
    {
        (lines, cursorLine, cursorCol)
    }

    func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?
    {
        self.suggestion
    }

    func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> Bool
    {
        self.triggerFileCompletion
    }
}

@Suite("Editor")
struct EditorTests {
    @Test
    func `typing and submit resets state`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        type("hello", into: editor)
        editor.handle(input: .key(.enter))
        #expect(submitted == "hello")
        #expect(editor.getText().isEmpty)
    }

    @Test
    func `newline creates second line`() {
        let editor = Editor()
        type("hello", into: editor)
        type("\nworld", into: editor)
        #expect(editor.getText() == "hello\nworld")
    }

    @Test
    func `backspace merges lines`() {
        let editor = Editor()
        editor.setText("hello\nworld")
        editor.handle(input: .key(.home))
        editor.handle(input: .key(.backspace))
        #expect(editor.getText() == "helloworld")
    }

    @Test
    func `large paste marker replaced on submit`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        let pasted = (0..<20).map { "line \($0)" }.joined(separator: "\n")
        editor.handle(input: .paste(pasted))
        #expect(editor.getText().contains("[paste #1"))
        editor.handle(input: .key(.enter))
        #expect(submitted == pasted)
    }

    @Test
    func `ctrl U and ctrl K delete segments`() {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.home))
        editor.handle(input: .key(.character("k"), modifiers: [.control]))
        #expect(editor.getText().isEmpty)

        editor.setText("hello world")
        editor.handle(input: .key(.end))
        editor.handle(input: .key(.character("u"), modifiers: [.control]))
        #expect(editor.getText().isEmpty)
    }

    @Test
    func `ctrl W deletes word backwards`() {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.end))
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "hello ")
    }

    @Test
    func `ctrl A moves to start and ctrl E moves to end`() {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.character("a"), modifiers: [.control]))
        editor.handle(input: .key(.character("x")))
        #expect(editor.getText().hasPrefix("x"))

        editor.handle(input: .key(.character("e"), modifiers: [.control]))
        editor.handle(input: .key(.character("!")))
        #expect(editor.getText().hasSuffix("!"))
    }

    @Test
    func `option backspace deletes word`() {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.end))
        editor.handle(input: .key(.backspace, modifiers: [.option]))
        #expect(editor.getText() == "hello ")
    }

    @Test
    func `ctrl W deletes whitespace then word`() {
        let editor = Editor()
        editor.setText("hello   world")

        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "hello   ")

        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText().isEmpty)
    }

    @Test
    func `ctrl W deletes punctuation runs`() {
        let editor = Editor()
        editor.setText("foo.bar")

        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo.")

        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo")
    }

    @Test
    func `ctrl left right moves by word`() {
        let editor = Editor()
        editor.setText("hello world")

        editor.handle(input: .key(.arrowLeft, modifiers: [.control]))
        editor.handle(input: .key(.character("X")))
        #expect(editor.getText() == "hello Xworld")

        editor.handle(input: .key(.arrowRight, modifiers: [.control]))
        editor.handle(input: .key(.character("Y")))
        #expect(editor.getText() == "hello XworldY")
    }

    @Test
    func `ctrl W and option backspace parity`() {
        let editor = Editor()

        editor.setText("foo bar baz")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo bar ")

        editor.setText("foo bar   ")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo ")

        editor.setText("foo bar...")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo bar")

        editor.setText("line one\nline two")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "line one\nline ")

        editor.setText("line one\n")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "line one")

        editor.setText("foo 😀😀 bar")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo 😀😀 ")
        editor.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(editor.getText() == "foo ")

        editor.setText("foo bar")
        editor.handle(input: .key(.backspace, modifiers: [.option]))
        #expect(editor.getText() == "foo ")
    }

    @Test
    func `ctrl left right word navigation parity`() {
        let editor = Editor()
        editor.setText("foo bar... baz")

        editor.handle(input: .key(.arrowLeft, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 11))

        editor.handle(input: .key(.arrowLeft, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 7))

        editor.handle(input: .key(.arrowLeft, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 4))

        editor.handle(input: .key(.arrowRight, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 7))

        editor.handle(input: .key(.arrowRight, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 10))

        editor.handle(input: .key(.arrowRight, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 14))

        editor.setText("   foo bar")
        editor.handle(input: .key(.character("a"), modifiers: [.control]))
        editor.handle(input: .key(.arrowRight, modifiers: [.control]))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 6))
    }

    @Test
    func `option delete forward deletes word`() {
        let editor = Editor()
        editor.setText("hello world")
        editor.handle(input: .key(.home))
        editor.handle(input: .key(.delete, modifiers: [.option]))
        #expect(editor.getText() == " world")
    }

    @Test
    func `option enter adds newline not submit`() {
        let editor = Editor()
        editor.setText("hello")
        editor.handle(input: .key(.enter, modifiers: [.option]))
        #expect(editor.getText() == "hello\n")
    }

    @Test
    func `vscode shift enter sequence adds newline`() {
        let editor = Editor()
        editor.handle(input: .key(.enter, modifiers: [.shift]))
        #expect(editor.getText() == "\n")
    }

    @Test
    func `tab forces file autocomplete`() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        FileManager.default.createFile(atPath: temp.appendingPathComponent("hello.txt").path, contents: Data())

        let provider = CombinedAutocompleteProvider(basePath: temp.path)
        let editor = Editor()
        editor.setAutocompleteProvider(provider)

        type("hel", into: editor)
        editor.handle(input: .key(.tab)) // show suggestions
        editor.handle(input: .key(.tab)) // accept first item

        #expect(editor.getText().contains("hello.txt"))
    }

    @Test
    func `slash commands tab complete`() {
        let provider = CombinedAutocompleteProvider(commands: [TestCommand(name: "clear")])
        let editor = Editor()
        editor.setAutocompleteProvider(provider)

        type("/cl", into: editor)
        editor.handle(input: .key(.tab))
        editor.handle(input: .key(.tab))

        #expect(editor.getText().hasPrefix("/clear "))
    }

    @Test
    func `paste filters control characters`() {
        let editor = Editor()
        editor.handle(input: .paste("\tcolumn\u{0007}\nline"))
        let text = editor.getText()
        #expect(text.contains("    column"))
        #expect(!text.contains("\u{0007}"))
    }

    @Test
    func `escape cancels autocomplete`() {
        let provider = StubAutocompleteProvider()
        let editor = Editor()
        editor.setAutocompleteProvider(provider)

        type("/cl", into: editor)
        provider.suggestion = AutocompleteSuggestion(
            items: [AutocompleteItem(value: "clear", label: "clear", description: nil)],
            prefix: "/cl")
        editor.handle(input: .key(.tab)) // open autocomplete list
        let showing = editor.render(width: 20)

        editor.handle(input: .key(.escape))
        let hidden = editor.render(width: 20)
        #expect(showing.count > hidden.count)
    }

    @Test
    func `tab skips when provider declines`() {
        let provider = StubAutocompleteProvider()
        provider.triggerFileCompletion = false
        let editor = Editor()
        editor.setAutocompleteProvider(provider)

        type("hello", into: editor)
        let before = editor.render(width: 20)
        editor.handle(input: .key(.tab))
        let after = editor.render(width: 20)
        #expect(before == after)
    }

    @Test
    func `arrow left and right move cursor`() {
        let editor = Editor()
        editor.setText("hi")
        editor.handle(input: .key(.arrowLeft))
        type("X", into: editor)
        #expect(editor.getText() == "hXi")
        editor.handle(input: .key(.arrowRight))
        type("!", into: editor)
        #expect(editor.getText() == "hXi!")
    }

    @Test
    func `arrow up and down navigate lines`() {
        let editor = Editor()
        editor.setText("foo\nbar")
        editor.handle(input: .key(.arrowUp))
        type("*", into: editor)
        #expect(editor.getText().starts(with: "foo*"))
        editor.handle(input: .key(.arrowDown))
        type("!", into: editor)
        #expect(editor.getText().hasSuffix("bar!"))
    }

    @Test
    func `home and end keys move to line bounds`() {
        let editor = Editor()
        editor.setText("hello")
        editor.handle(input: .key(.home))
        type("X", into: editor)
        #expect(editor.getText() == "Xhello")
        editor.handle(input: .key(.end))
        type("!", into: editor)
        #expect(editor.getText() == "Xhello!")
    }

    @Test
    func `delete key removes forward characters`() {
        let editor = Editor()
        editor.setText("hello")
        editor.handle(input: .key(.home))
        editor.handle(input: .key(.delete))
        #expect(editor.getText() == "ello")
    }

    @Test
    func `delete key merges next line`() {
        let editor = Editor()
        editor.setText("foo\nbar")
        editor.handle(input: .key(.home))
        editor.handle(input: .key(.arrowUp))
        editor.handle(input: .key(.end))
        editor.handle(input: .key(.delete))
        #expect(editor.getText() == "foobar")
    }
}
