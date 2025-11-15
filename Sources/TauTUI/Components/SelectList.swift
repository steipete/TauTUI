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
    public var items: [SelectItem] { didSet { self.filterItems() } }
    public var maxVisible: Int
    public var onSelect: ((SelectItem) -> Void)?
    public var onCancel: (() -> Void)?

    private var filterText: String = "" { didSet { self.filterItems() } }
    private var filtered: [SelectItem] = []
    private var selectedIndex: Int = 0

    public init(items: [SelectItem], maxVisible: Int = 5) {
        self.items = items
        self.maxVisible = max(1, maxVisible)
        self.filtered = items
    }

    public func setFilter(_ newValue: String) {
        self.filterText = newValue
    }

    public func render(width: Int) -> [String] {
        guard !self.filtered.isEmpty else {
            return ["\u{001B}[90m  No matching commands\u{001B}[0m"]
        }
        let start = max(0, min(selectedIndex - self.maxVisible / 2, self.filtered.count - self.maxVisible))
        let end = min(filtered.count, start + self.maxVisible)
        var lines: [String] = []
        for index in start..<end {
            let item = self.filtered[index]
            let isSelected = index == self.selectedIndex
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
        if self.filtered.count > self.maxVisible {
            lines.append("\u{001B}[90m  (\(self.selectedIndex + 1)/\(self.filtered.count))\u{001B}[0m")
        }
        return lines
    }

    public func handle(input: TerminalInput) {
        guard case let .key(key, _) = input else { return }
        switch key {
        case .arrowUp:
            self.selectedIndex = max(0, self.selectedIndex - 1)
        case .arrowDown:
            self.selectedIndex = min(self.filtered.count - 1, self.selectedIndex + 1)
        case .enter:
            if self.filtered.indices.contains(self.selectedIndex) {
                self.onSelect?(self.filtered[self.selectedIndex])
            }
        case .escape:
            self.onCancel?()
        default:
            break
        }
    }

    public func selectedItem() -> SelectItem? {
        guard self.filtered.indices.contains(self.selectedIndex) else { return nil }
        return self.filtered[self.selectedIndex]
    }

    private func filterItems() {
        if self.filterText.isEmpty {
            self.filtered = self.items
        } else {
            self.filtered = self.items
                .filter {
                    $0.value.lowercased().hasPrefix(self.filterText.lowercased()) || $0.label.lowercased()
                        .hasPrefix(self.filterText.lowercased())
                }
        }
        self.selectedIndex = min(max(0, self.selectedIndex), max(0, self.filtered.count - 1))
    }
}
