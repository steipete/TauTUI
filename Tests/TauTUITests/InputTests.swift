import Testing
@testable import TauTUI

@Suite("Input component")
struct InputTests {
    @Test
    func insertsCharactersAndSubmits() async throws {
        var submitted: String?
        let input = Input()
        input.onSubmit = { submitted = $0 }
        input.handle(input: .key(.character("h"), modifiers: []))
        input.handle(input: .key(.character("i"), modifiers: []))
        input.handle(input: .key(.enter, modifiers: []))
        #expect(submitted == "hi")
    }

    @Test
    func backspaceRemovesCharacters() async throws {
        let input = Input(value: "hello")
        input.handle(input: .key(.backspace, modifiers: []))
        input.handle(input: .key(.backspace, modifiers: []))
        #expect(input.value == "hel")
    }
}
