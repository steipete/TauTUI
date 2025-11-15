import Testing
@testable import TauTUI

@Test
func visibleWidthIgnoresAnsiSequences() async throws {
    let colored = "\u{001B}[31mhello\u{001B}[0m"
    #expect(VisibleWidth.measure(colored) == 5)
}
