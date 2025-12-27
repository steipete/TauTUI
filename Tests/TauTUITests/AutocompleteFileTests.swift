import Foundation
import Testing
@testable import TauTUI

@Suite("Autocomplete file suggestions")
struct AutocompleteFileTests {
    @Test
    func directoriesComeFirstAndAreSorted() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try FileManager.default.createDirectory(
            at: temp.appendingPathComponent("docs"),
            withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: temp.appendingPathComponent("Apps"),
            withIntermediateDirectories: false)
        FileManager.default.createFile(atPath: temp.appendingPathComponent("zeta.txt").path, contents: Data())
        FileManager.default.createFile(atPath: temp.appendingPathComponent("alpha.log").path, contents: Data())

        let provider = CombinedAutocompleteProvider(commands: [], basePath: temp.path)
        let lines = ["./"]
        let result = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 2)
        guard let items = result?.items else {
            Issue.record("expected suggestions")
            return
        }
        let labels = items.map(\.label)
        #expect(labels.prefix(2) == ["Apps/", "docs/"]) // directories first, alpha sort case-insensitive
        #expect(labels.suffix(2) == ["alpha.log", "zeta.txt"]) // files sorted after dirs
    }

    @Test
    func attachmentModeFiltersNonText() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        FileManager.default.createFile(atPath: temp.appendingPathComponent("image.png").path, contents: Data())
        FileManager.default.createFile(atPath: temp.appendingPathComponent("archive.bin").path, contents: Data())
        FileManager.default.createFile(atPath: temp.appendingPathComponent("note.md").path, contents: Data())

        let provider = CombinedAutocompleteProvider(commands: [], basePath: temp.path)
        let lines = ["@"]
        let result = provider.getSuggestions(lines: lines, cursorLine: 0, cursorCol: 1)
        guard let items = result?.items else {
            Issue.record("expected suggestions")
            return
        }
        let values = Set(items.map(\.value))
        #expect(values.contains("@image.png"))
        #expect(values.contains("@note.md"))
        #expect(!values.contains("@archive.bin")) // filtered out as non-attachable
    }

    @Test
    func fileSuggestionsAreCappedAtTen() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // create 3 dirs + 10 files (13 total) to ensure capping at 10
        for name in ["a", "b", "c"] {
            try FileManager.default.createDirectory(
                at: temp.appendingPathComponent(name),
                withIntermediateDirectories: false)
        }
        for i in 0..<10 {
            FileManager.default.createFile(atPath: temp.appendingPathComponent("file\(i).txt").path, contents: Data())
        }

        let provider = CombinedAutocompleteProvider(commands: [], basePath: temp.path)
        let result = provider.getSuggestions(lines: ["./"], cursorLine: 0, cursorCol: 2)
        guard let items = result?.items else {
            Issue.record("expected suggestions")
            return
        }
        #expect(items.count == 10)
        // Directories should still be first even when capped.
        let labels = items.map(\.label)
        #expect(labels.prefix(3).allSatisfy { $0.hasSuffix("/") })
    }

    @Test
    func forcedSuggestionsWorkWithoutPathDelimiters() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        FileManager.default.createFile(atPath: temp.appendingPathComponent("hello.txt").path, contents: Data())

        let provider = CombinedAutocompleteProvider(basePath: temp.path)
        let lines = ["hel"]
        let forced = provider.forceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 3)
        guard let items = forced?.items else {
            Issue.record("expected forced suggestions")
            return
        }
        #expect(items.contains(where: { $0.value.contains("hello.txt") }))
    }

    @Test
    func forceFileSuggestionsExtractsSlashPrefix() throws {
        let provider = CombinedAutocompleteProvider(basePath: "/tmp")

        let lines = ["hey /"]
        let result = provider.forceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 5)
        #expect(result?.prefix == "/")
    }

    @Test
    func forceFileSuggestionsDoesNotTriggerForSlashCommandItself() throws {
        let provider = CombinedAutocompleteProvider(basePath: "/tmp")
        let lines = ["/model"]
        let result = provider.forceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 6)
        #expect(result == nil)
    }

    @Test
    func forceFileSuggestionsTriggersForSlashCommandArgument() throws {
        let provider = CombinedAutocompleteProvider(basePath: "/tmp")
        let lines = ["/command /"]
        let result = provider.forceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 10)
        #expect(result?.prefix == "/")
    }
}
