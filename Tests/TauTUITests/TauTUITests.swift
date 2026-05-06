import Testing
@testable import TauTUI

@Test
func `visible width ignores ansi sequences`() {
    let colored = "\u{001B}[31mhello\u{001B}[0m"
    #expect(VisibleWidth.measure(colored) == 5)
}
