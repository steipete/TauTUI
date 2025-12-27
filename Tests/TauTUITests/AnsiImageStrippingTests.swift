import Testing
@testable import TauTUI

@Suite("Ansi.stripCodes")
struct AnsiImageStrippingTests {
    @Test
    func stripCodes_removesKittyAndITerm2ImageSequences() {
        let kitty = "\u{001B}_Ga=T,f=100;AAAA\u{001B}\\"
        let iterm = "\u{001B}]1337;File=inline=1:AAAA\u{0007}"

        let input = "ab" + kitty + "cd" + iterm + "ef"
        #expect(Ansi.stripCodes(input) == "abcdef")
    }
}

