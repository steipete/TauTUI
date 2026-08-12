import Foundation
import Testing
@testable import TauTUI

@Suite("Input component")
struct InputTests {
    @Test
    func `inserts characters and submits`() {
        var submitted: String?
        let input = Input()
        input.onSubmit = { submitted = $0 }
        input.handle(input: .key(.character("h")))
        input.handle(input: .key(.character("i")))
        input.handle(input: .key(.enter))
        #expect(submitted == "hi")
    }

    @Test
    func `backspace removes characters`() {
        let input = Input(value: "hello")
        input.handle(input: .key(.backspace))
        input.handle(input: .key(.backspace))
        #expect(input.value == "hel")
    }

    @Test
    func `paste strips newlines`() {
        let input = Input()
        input.handle(input: .paste("hello world\n"))
        #expect(input.value == "hello world")

        input.handle(input: .paste("more\nlines"))
        #expect(input.value == "hello worldmorelines")

        input.handle(input: .raw("\u{001B}[A"))
        #expect(input.value == "hello worldmorelines")
    }

    @Test
    func `paste removes terminal control sequences and preserves unicode`() {
        let input = Input()

        input.handle(input: .paste("\u{001B}]0;owned\u{0007}\u{001B}[31mhello\u{007F}\u{0085}\t😀\nworld"))

        #expect(input.value == "]0;owned[31mhello    😀world")
        #expect(!input.value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
    }

    @Test
    func `ctrl A moves to start and ctrl E moves to end`() {
        let input = Input(value: "hello")
        input.handle(input: .key(.character("a"), modifiers: [.control]))
        input.handle(input: .key(.character("x")))
        #expect(input.value == "xhello")

        input.handle(input: .key(.character("e"), modifiers: [.control]))
        input.handle(input: .key(.character("y")))
        #expect(input.value == "xhelloy")
    }

    @Test
    func `ctrl W deletes whitespace then word`() {
        let input = Input(value: "hello   world")
        input.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(input.value == "hello   ")

        input.handle(input: .key(.character("w"), modifiers: [.control]))
        #expect(input.value.isEmpty)
    }

    @Test
    func `option backspace deletes word`() {
        let input = Input(value: "hello world")
        input.handle(input: .key(.backspace, modifiers: [.option]))
        #expect(input.value == "hello ")
    }

    @Test
    func `ctrl left right moves by word`() {
        let input = Input(value: "hello world")

        input.handle(input: .key(.arrowLeft, modifiers: [.control]))
        input.handle(input: .key(.character("X")))
        #expect(input.value == "hello Xworld")

        input.handle(input: .key(.arrowRight, modifiers: [.control]))
        input.handle(input: .key(.character("Y")))
        #expect(input.value == "hello XworldY")
    }

    @Test
    func `render does not overflow with wide text at any cursor position`() {
        let width = 20
        let values = [
            "가나다라마바사아자차카타파하",
            "これは日本語のテキストです",
            "ＡＢＣＤＥＦＧＨＩＪＫＬ",
        ]

        for value in values {
            let atStart = Input(value: value)
            atStart.handle(input: .key(.home))

            let inMiddle = Input(value: value)
            inMiddle.handle(input: .key(.home))
            for _ in 0..<5 {
                inMiddle.handle(input: .key(.arrowRight))
            }

            let atEnd = Input(value: value)

            for input in [atStart, inMiddle, atEnd] {
                let line = input.render(width: width)[0]
                #expect(VisibleWidth.measure(line) <= width)
            }
        }
    }

    @Test
    func `render keeps the cursor on a whole grapheme`() {
        let family = "👨‍👩‍👧‍👦"
        let input = Input(value: "a\(family)b")
        input.handle(input: .key(.home))
        input.handle(input: .key(.arrowRight))

        let line = input.render(width: 8)[0]

        #expect(line.contains("\u{001B}[7m\(family)\u{001B}[27m"))
        #expect(VisibleWidth.measure(line) <= 8)
    }
}
