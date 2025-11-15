import Testing
@testable import TauTUI

@Suite("Editor paste markers")
struct EditorPasteTests {
    private func type(_ text: String, into editor: Editor) {
        text.forEach { char in
            editor.handle(input: .key(.character(char)))
        }
    }

    @Test
    func multipleMarkersReplacedOnSubmit() async throws {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }

        // Simulate two large pastes separated by text
        let big1 = Array(repeating: "alpha", count: 15).joined(separator: "\n")
        let big2 = Array(repeating: "beta", count: 12).joined(separator: "\n")

        editor.handle(input: .paste(big1))
        type(" middle ", into: editor)
        editor.handle(input: .paste(big2))
        editor.handle(input: .key(.enter))

        #expect(submitted == big1 + " middle " + big2)
    }

    @Test
    func markersDoNotMatchPartialIds() async throws {
        let editor = Editor()
        var submitted: String?
        editor.onSubmit = { submitted = $0 }

        editor.handle(input: .paste("hello")) // marker #1
        type(" [paste #12 +x lines]", into: editor) // literal text, not real marker we created
        editor.handle(input: .key(.enter))

        #expect(submitted?.contains("[paste #12") == true)
        #expect(submitted?.starts(with: "hello") == true)
    }
}
