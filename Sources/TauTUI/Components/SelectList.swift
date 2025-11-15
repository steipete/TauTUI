public struct SelectItem {
    public let value: String
    public let label: String
    public let description: String?

    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

public final class SelectList: Component {
    public var items: [SelectItem] { didSet { filterItems() } }
    public var maxVisible: Int
    public var onSelect: ((SelectItem) -> Void)?
    public var onCancel: (() -> Void)?

    private var filterText: String = "" { didSet { filterItems() } }
    private var filtered: [SelectItem] = []
    private var selectedIndex: Int = 0

    public init(items: [SelectItem], maxVisible: Int = 5) {
        self.items = items
        self.maxVisible = max(1, maxVisible)
        self.filtered = items
    }

    public func setFilter(_ newValue: String) {
        filterText = newValue
    }

    public func render(width: Int) -> [String] {
        guard !filtered.isEmpty else {
            return ["\u{001B}[90m  No matching commands\u{001B}[0m"]
        }
        let start = max(0, min(selectedIndex - maxVisible / 2, filtered.count - maxVisible))
        let end = min(filtered.count, start + maxVisible)
        var lines: [String] = []
        for index in start..<end {
            let item = filtered[index]
            let isSelected = index == selectedIndex
            let prefix = isSelected ? "\u{001B}[34m→ \u{001B}[0m" : "  "
            let title = isSelected ? "\u{001B}[34m\(item.label)\u{001B}[0m" : item.label
            var line = prefix + title
            if let description = item.description, width > 40 {
                let spacing = String(repeating: " ", count: max(1, 32 - title.count))
                let remaining = max(0, width - (prefix.count + title.count + spacing.count) - 2)
                if remaining > 10 {
                    line += spacing + "\u{001B}[90m" + description.prefix(remaining) + "\u{001B}[0m"
                }
            }
            lines.append(line)
        }
        if filtered.count > maxVisible {
            lines.append("\u{001B}[90m  (\(selectedIndex + 1)/\(filtered.count))\u{001B}[0m")
        }
        return lines
    }

    public func handle(input: TerminalInput) {
        guard case let .key(key, _) = input else { return }
        switch key {
        case .arrowUp:
            selectedIndex = max(0, selectedIndex - 1)
        case .arrowDown:
            selectedIndex = min(filtered.count - 1, selectedIndex + 1)
        case .enter:
            if filtered.indices.contains(selectedIndex) {
                onSelect?(filtered[selectedIndex])
            }
        case .escape:
            onCancel?()
        default:
            break
        }
    }

    public func selectedItem() -> SelectItem? {
        guard filtered.indices.contains(selectedIndex) else { return nil }
        return filtered[selectedIndex]
    }

    private func filterItems() {
        if filterText.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.value.lowercased().hasPrefix(filterText.lowercased()) || $0.label.lowercased().hasPrefix(filterText.lowercased()) }
        }
        selectedIndex = min(max(0, selectedIndex), max(0, filtered.count - 1))
    }
}
