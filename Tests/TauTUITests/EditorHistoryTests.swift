import Testing
@testable import TauTUI

@Suite("Editor history")
struct EditorHistoryTests {
    @Test
    func upArrowDoesNothingWhenHistoryEmpty() {
        let editor = Editor()
        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText().isEmpty)
    }

    @Test
    func upArrowShowsMostRecentWhenEditorEmpty() {
        let editor = Editor()
        editor.addToHistory("first prompt")
        editor.addToHistory("second prompt")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "second prompt")
    }

    @Test
    func repeatedUpCyclesToOldest() {
        let editor = Editor()
        editor.addToHistory("first")
        editor.addToHistory("second")
        editor.addToHistory("third")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "third")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "second")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "first")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "first")
    }

    @Test
    func downArrowReturnsToEmptyAfterBrowsingHistory() {
        let editor = Editor()
        editor.addToHistory("prompt")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "prompt")

        editor.handle(input: .key(.arrowDown))
        #expect(editor.getText().isEmpty)
    }

    @Test
    func downArrowNavigatesForwardThroughHistory() {
        let editor = Editor()
        editor.addToHistory("first")
        editor.addToHistory("second")
        editor.addToHistory("third")

        editor.handle(input: .key(.arrowUp)) // third
        editor.handle(input: .key(.arrowUp)) // second
        editor.handle(input: .key(.arrowUp)) // first

        editor.handle(input: .key(.arrowDown))
        #expect(editor.getText() == "second")

        editor.handle(input: .key(.arrowDown))
        #expect(editor.getText() == "third")

        editor.handle(input: .key(.arrowDown))
        #expect(editor.getText().isEmpty)
    }

    @Test
    func typingExitsHistoryMode() {
        let editor = Editor()
        editor.addToHistory("old prompt")

        editor.handle(input: .key(.arrowUp))
        editor.handle(input: .key(.character("x")))

        #expect(editor.getText() == "old promptx")
    }

    @Test
    func setTextExitsHistoryMode() {
        let editor = Editor()
        editor.addToHistory("first")
        editor.addToHistory("second")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "second")

        editor.setText("")
        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "second")
    }

    @Test
    func historyIgnoresEmptyAndConsecutiveDuplicates() {
        let editor = Editor()
        editor.addToHistory("")
        editor.addToHistory("   ")
        editor.addToHistory("same")
        editor.addToHistory("same")
        editor.addToHistory("same")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "same")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "same")
    }

    @Test
    func historyAllowsNonConsecutiveDuplicates() {
        let editor = Editor()
        editor.addToHistory("first")
        editor.addToHistory("second")
        editor.addToHistory("first")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "first")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "second")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "first")
    }

    @Test
    func usesCursorMovementInsteadOfHistoryWhenEditorHasContent() {
        let editor = Editor()
        editor.addToHistory("history item")
        editor.setText("line1\nline2")

        editor.handle(input: .key(.arrowUp))
        editor.handle(input: .key(.character("X")))

        #expect(editor.getText() == "line1X\nline2")
    }

    @Test
    func historyIsLimitedTo100Entries() {
        let editor = Editor()
        for i in 0..<105 {
            editor.addToHistory("prompt \(i)")
        }

        for _ in 0..<100 {
            editor.handle(input: .key(.arrowUp))
        }

        #expect(editor.getText() == "prompt 5")

        editor.handle(input: .key(.arrowUp))
        #expect(editor.getText() == "prompt 5")
    }

    @Test
    func multilineHistoryEntry_allowsCursorMovementThenHistoryNavigation() {
        let editor = Editor()
        editor.addToHistory("older entry")
        editor.addToHistory("line1\nline2\nline3")

        editor.handle(input: .key(.arrowUp)) // show multi-line entry
        editor.handle(input: .key(.arrowUp)) // move within entry
        #expect(editor.getText() == "line1\nline2\nline3")

        editor.handle(input: .key(.arrowUp)) // to line1
        editor.handle(input: .key(.arrowUp)) // now navigate to older entry
        #expect(editor.getText() == "older entry")
    }

    @Test
    func multilineHistoryEntry_downMovesWithinThenExits() {
        let editor = Editor()
        editor.addToHistory("line1\nline2\nline3")

        editor.handle(input: .key(.arrowUp)) // show entry
        editor.handle(input: .key(.arrowUp)) // cursor to line2
        editor.handle(input: .key(.arrowUp)) // cursor to line1

        editor.handle(input: .key(.arrowDown)) // cursor to line2
        #expect(editor.getText() == "line1\nline2\nline3")

        editor.handle(input: .key(.arrowDown)) // cursor to line3
        #expect(editor.getText() == "line1\nline2\nline3")

        editor.handle(input: .key(.arrowDown)) // exit
        #expect(editor.getText().isEmpty)
    }

    @Test
    func publicCursorAndLinesAccessors() {
        let editor = Editor()
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 0))

        editor.handle(input: .key(.character("a")))
        editor.handle(input: .key(.character("b")))
        editor.handle(input: .key(.character("c")))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 3))

        editor.handle(input: .key(.arrowLeft))
        #expect(editor.getCursor() == CursorPosition(line: 0, col: 2))

        editor.setText("a\nb")
        var lines = editor.getLines()
        #expect(lines == ["a", "b"])
        lines[0] = "mutated"
        #expect(editor.getLines() == ["a", "b"])
    }
}
