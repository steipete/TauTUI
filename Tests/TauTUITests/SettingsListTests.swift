import Testing
@testable import TauTUI

@Suite("SettingsList")
struct SettingsListTests {
    private final class Submenu: Component {
        private let done: (String?) -> Void
        init(done: @escaping (String?) -> Void) { self.done = done }
        func render(width: Int) -> [String] { ["submenu"] }
        func handle(input: TerminalInput) {
            if case .key(.enter, _) = input {
                self.done("chosen")
            }
        }
    }

    @Test
    func arrowNavigationWrapsAround() {
        var changes: [(String, String)] = []
        var cancelled = false

        let list = SettingsList(
            items: [
                .init(id: "a", label: "A", currentValue: "1"),
                .init(id: "b", label: "B", currentValue: "2"),
                .init(id: "c", label: "C", currentValue: "3"),
            ],
            onChange: { changes.append(($0, $1)) },
            onCancel: { cancelled = true })

        list.handle(input: .key(.arrowUp))
        let lines = list.render(width: 40)
        let selectedLine = lines.first(where: { $0.contains("›") })
        #expect(selectedLine?.contains("C") == true)

        list.handle(input: .key(.arrowDown))
        let lines2 = list.render(width: 40)
        let selectedLine2 = lines2.first(where: { $0.contains("›") })
        #expect(selectedLine2?.contains("A") == true)

        #expect(changes.isEmpty)
        #expect(cancelled == false)
    }

    @Test
    func enterCyclesValuesAndCallsOnChange() {
        var changes: [(String, String)] = []

        let list = SettingsList(
            items: [
                .init(id: "mode", label: "Mode", currentValue: "off", values: ["off", "on"]),
            ],
            onChange: { changes.append(($0, $1)) },
            onCancel: {})

        list.handle(input: .key(.enter))
        #expect(changes.count == 1)
        #expect(changes.first?.0 == "mode")
        #expect(changes.first?.1 == "on")

        let rendered = list.render(width: 40).joined(separator: "\n")
        #expect(rendered.contains("on"))
    }

    @Test
    func submenuDelegatesInputAndRestoresSelection() {
        var changes: [(String, String)] = []

        let list = SettingsList(
            items: [
                .init(id: "x", label: "X", currentValue: "0"),
                .init(
                    id: "pick",
                    label: "Pick",
                    description: "Choose a value",
                    currentValue: "old",
                    submenu: { _, done in
                        Submenu(done: done)
                    }),
            ],
            onChange: { changes.append(($0, $1)) },
            onCancel: {})

        list.handle(input: .key(.arrowDown))
        list.handle(input: .key(.enter))

        let submenuLines = list.render(width: 40)
        #expect(submenuLines.first == "submenu")

        list.handle(input: .key(.enter))
        #expect(changes.count == 1)
        #expect(changes.first?.0 == "pick")
        #expect(changes.first?.1 == "chosen")

        let mainLines = list.render(width: 40)
        let selectedLine = mainLines.first(where: { $0.contains("›") })
        #expect(selectedLine?.contains("Pick") == true)
        #expect(mainLines.joined(separator: "\n").contains("chosen"))
    }
}
