import Testing
@testable import TauTUI

@Suite("Terminal cell size query")
struct TerminalCellSizeTests {
    @Test
    func processTerminalParsesCellSizeResponse() throws {
        let parser = ProcessTerminal()
        let events = parser.parseForTests("\u{001B}[6;18;9t")
        #expect(events.count == 1)
        if case let .terminalCellSize(widthPx, heightPx) = events[0] {
            #expect(widthPx == 9)
            #expect(heightPx == 18)
        } else {
            Issue.record("Expected .terminalCellSize event")
        }
    }
}
