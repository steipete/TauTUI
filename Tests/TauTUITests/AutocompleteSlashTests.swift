import Testing
@testable import TauTUI

@Suite("Autocomplete slash filtering")
struct AutocompleteSlashTests {
    private struct Command: SlashCommand {
        let name: String
        let description: String? = nil
        func argumentCompletions(prefix: String) -> [AutocompleteItem] { [] }
    }

    @Test
    func filtersCaseInsensitiveMaintainsOrder() throws {
        let provider = CombinedAutocompleteProvider(commands: [
            Command(name: "clear"),
            Command(name: "clap"),
            Command(name: "Close"),
            Command(name: "other"),
        ])

        let lines = ["/cl"]
        guard let result = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 3) else {
            Issue.record("expected suggestions")
            return
        }

        let values = result.items.map { $0.value }
        #expect(values == ["clear", "clap", "Close"])
        #expect(result.prefix == "/cl")
    }

    @Test
    func argumentCompletionsStopAtSpace() throws {
        let provider = CombinedAutocompleteProvider(commands: [
            Command(name: "say")
        ])

        let lines = ["/say hello"]
        let result = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 10)
        #expect(result == nil) // no arg completions provided -> nil
    }
}

