import Testing
@testable import TauTUI

@Suite("Input component")
struct InputTests {
    @Test
    func insertsCharactersAndSubmits() async throws {
        var submitted: String?
        let input = Input()
        input.onSubmit = { submitted = $0 }
        input.handle(input: .key(.character("h")))
        input.handle(input: .key(.character("i")))
        input.handle(input: .key(.enter))
        #expect(submitted == "hi")
    }

    @Test
    func backspaceRemovesCharacters() async throws {
        let input = Input(value: "hello")
        input.handle(input: .key(.backspace))
        input.handle(input: .key(.backspace))
        #expect(input.value == "hel")
    }

    @Test
    func bracketedPasteBuffersAndStripsNewlines() async throws {
        let input = Input()
        input.handle(input: .raw("\u{001B}[200~hello"))
        input.handle(input: .raw(" world\n\u{001B}[201~"))
        #expect(input.value == "hello world")

        input.handle(input: .paste("more\nlines"))
        #expect(input.value == "hello worldmorelines")
    }
}
