import Foundation
import Testing
@testable import TauTUI

private struct DummyCommand: SlashCommand {
    let name: String
    let description: String?
    func argumentCompletions(prefix: String) -> [AutocompleteItem] {
        if prefix.isEmpty || "arg".hasPrefix(prefix) {
            return [AutocompleteItem(value: "arg", label: "arg", description: nil)]
        }
        return []
    }
}

@Suite("Autocomplete")
struct AutocompleteTests {
    @Test
    func slashCommandSuggestions() async throws {
        let provider = CombinedAutocompleteProvider(commands: [DummyCommand(name: "test", description: "desc")])
        let lines = ["/t"]
        let suggestion = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 2)
        #expect(suggestion?.items.first?.value == "test")
    }

    @Test
    func fileSuggestions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("hello.txt")
        try "hi".write(to: fileURL, atomically: true, encoding: .utf8)
        let provider = CombinedAutocompleteProvider(basePath: tempDir.path)
        let lines = ["./hel"]
        let suggestion = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 5)
        #expect(suggestion?.items.contains(where: { $0.value.contains("hello.txt") }) == true)
        try FileManager.default.removeItem(at: tempDir)
    }
}
