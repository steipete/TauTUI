import Testing
@testable import TauTUI

@Suite("Box")
struct BoxTests {
    private final class Dummy: Component {
        let lines: [String]
        init(_ lines: [String]) { self.lines = lines }
        func render(width: Int) -> [String] { self.lines }
    }

    @Test
    func boxPadsAndAppliesBackground() {
        let bg = AnsiStyling.Background.rgb(1, 2, 3)
        let box = Box(paddingX: 1, paddingY: 1, background: bg, children: [Dummy(["hi"])])

        let rendered = box.render(width: 6)
        #expect(rendered.count == 3)
        for line in rendered {
            #expect(VisibleWidth.measure(line) == 6)
            #expect(line.contains("\u{001B}[48;2;1;2;3m"))
            #expect(line.contains("\u{001B}[49m"))
        }
    }
}
