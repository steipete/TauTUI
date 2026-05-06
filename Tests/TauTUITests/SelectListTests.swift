import Testing
@testable import TauTUI

@Suite("SelectList")
struct SelectListTests {
    @Test
    func `moves selection and selects`() {
        let items = [
            SelectItem(value: "one", label: "One"),
            SelectItem(value: "two", label: "Two"),
            SelectItem(value: "three", label: "Three"),
        ]
        let list = SelectList(items: items, maxVisible: 2)
        var selected: SelectItem?
        list.onSelect = { selected = $0 }
        list.handle(input: .key(.arrowDown))
        list.handle(input: .key(.enter))
        #expect(selected?.value == "two")
    }

    @Test
    func `filters items`() {
        let items = [SelectItem(value: "apple", label: "Apple"), SelectItem(value: "banana", label: "Banana")]
        let list = SelectList(items: items)
        list.setFilter("ba")
        let rendered = list.render(width: 40)
        #expect(rendered.joined().contains("Banana"))
    }

    @Test
    func `description alignment consistent between selected and unselected`() {
        let items = [
            SelectItem(value: "a", label: "Alpha", description: "first item"),
            SelectItem(value: "b", label: "Beta", description: "second item"),
            SelectItem(value: "c", label: "Gamma", description: "third item"),
        ]
        let list = SelectList(items: items, maxVisible: 3)
        let rendered = list.render(width: 60)

        let line0 = Ansi.stripCodes(rendered[0])
        let line1 = Ansi.stripCodes(rendered[1])
        let line2 = Ansi.stripCodes(rendered[2])

        guard let descPos0 = line0.range(of: "first")?.lowerBound,
              let descPos1 = line1.range(of: "second")?.lowerBound,
              let descPos2 = line2.range(of: "third")?.lowerBound
        else {
            Issue.record("Expected descriptions in rendered output")
            return
        }

        let col0 = line0.distance(from: line0.startIndex, to: descPos0)
        let col1 = line1.distance(from: line1.startIndex, to: descPos1)
        let col2 = line2.distance(from: line2.startIndex, to: descPos2)

        #expect(col0 == col1, "Description column mismatch: selected=\(col0), unselected=\(col1)")
        #expect(col1 == col2, "Description column mismatch between unselected items: \(col1) vs \(col2)")
    }
}
