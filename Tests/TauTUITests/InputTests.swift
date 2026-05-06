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
}
