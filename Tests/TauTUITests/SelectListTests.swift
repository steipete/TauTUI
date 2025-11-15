import Testing
@testable import TauTUI

@Suite("SelectList")
struct SelectListTests {
    @Test
    func movesSelectionAndSelects() async throws {
        let items = [
            SelectItem(value: "one", label: "One"),
            SelectItem(value: "two", label: "Two"),
            SelectItem(value: "three", label: "Three"),
        ]
        let list = SelectList(items: items, maxVisible: 2)
        var selected: SelectItem?
        list.onSelect = { selected = $0 }
        list.handle(input: .key(.arrowDown, modifiers: []))
        list.handle(input: .key(.enter, modifiers: []))
        #expect(selected?.value == "two")
    }

    @Test
    func filtersItems() async throws {
        let items = [SelectItem(value: "apple", label: "Apple"), SelectItem(value: "banana", label: "Banana")]
        let list = SelectList(items: items)
        list.setFilter("ba")
        let rendered = list.render(width: 40)
        #expect(rendered.joined().contains("Banana"))
    }
}
