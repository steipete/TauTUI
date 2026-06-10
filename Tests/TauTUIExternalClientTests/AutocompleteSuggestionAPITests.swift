import TauTUI
import Testing

@Suite("External client autocomplete API")
struct AutocompleteSuggestionAPITests {
    @Test
    func `can construct autocomplete suggestion through public module import`() {
        let item = AutocompleteItem(value: "value", label: "label")
        let suggestion = AutocompleteSuggestion(items: [item], prefix: "v")

        #expect(suggestion.items == [item])
        #expect(suggestion.prefix == "v")
    }
}
