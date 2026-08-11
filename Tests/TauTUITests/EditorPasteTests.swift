import Testing
@testable import TauTUI

@Suite("Editor paste markers")
struct EditorPasteTests {
    private func type(_ text: String, into editor: Editor) {
        for char in text {
            editor.handle(input: .key(.character(char)))
        }
    }

    @Test
    func `multiple markers replaced on submit`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }

        // Simulate two large pastes separated by text
        let big1 = Array(repeating: "alpha", count: 15).joined(separator: "\n")
        let big2 = Array(repeating: "beta", count: 12).joined(separator: "\n")

        editor.handle(input: .paste(big1))
        self.type(" middle ", into: editor)
        editor.handle(input: .paste(big2))
        editor.handle(input: .key(.enter))

        #expect(submitted == big1 + " middle " + big2)
    }

    @Test
    func `markers do not match partial ids`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }

        editor.handle(input: .paste("hello")) // marker #1
        self.type(" [paste #12 +x lines]", into: editor) // literal text, not real marker we created
        editor.handle(input: .key(.enter))

        #expect(submitted?.contains("[paste #12") == true)
        #expect(submitted?.starts(with: "hello") == true)
    }

    @Test
    func `paste expansion preserves replacement metacharacters`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        let paste = String(repeating: "$1 \\path\n", count: 12)

        editor.handle(input: .paste(paste))
        editor.handle(input: .key(.enter))

        #expect(submitted == paste.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test
    func `set text clears hidden paste state`() {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }
        let paste = Array(repeating: "secret", count: 12).joined(separator: "\n")

        editor.handle(input: .paste(paste))
        let marker = editor.getText()
        editor.setText(marker)
        editor.handle(input: .key(.enter))

        #expect(submitted == marker)
    }

    @Test
    func `editing a marker drops its hidden paste`() {
        let editor = Editor()
        let paste = Array(repeating: "payload", count: 12).joined(separator: "\n")

        editor.handle(input: .paste(paste))
        #expect(editor.pastes.count == 1)
        editor.handle(input: .key(.backspace))

        #expect(editor.pastes.isEmpty)
    }

    @Test
    func `pastes mutate the editor once without querying autocomplete`() {
        let editor = Editor()
        let provider = CountingAutocompleteProvider()
        editor.setAutocompleteProvider(provider)
        var changes = 0
        editor.onChange = { _ in changes += 1 }

        editor.handle(input: .paste(String(repeating: "x", count: 999)))

        #expect(changes == 1)
        #expect(provider.queryCount == 0)
    }

    @Test
    func `paste prepends space for file paths after word character`() {
        let editor = Editor()
        editor.setText("hello")

        editor.handle(input: .paste("/tmp/file.txt"))

        #expect(editor.getText() == "hello /tmp/file.txt")
    }
}

private final class CountingAutocompleteProvider: AutocompleteProvider {
    var queryCount = 0

    func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int) -> AutocompleteSuggestion?
    {
        self.queryCount += 1
        return nil
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
}
