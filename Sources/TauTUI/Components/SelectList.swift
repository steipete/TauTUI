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

public struct SelectListTheme: Sendable {
    public var selectedPrefix: AnsiStyling.Style
    public var selectedText: AnsiStyling.Style
    public var description: AnsiStyling.Style
    public var scrollInfo: AnsiStyling.Style
    public var noMatch: AnsiStyling.Style

    public init(
        selectedPrefix: @escaping AnsiStyling.Style,
        selectedText: @escaping AnsiStyling.Style,
        description: @escaping AnsiStyling.Style,
        scrollInfo: @escaping AnsiStyling.Style,
        noMatch: @escaping AnsiStyling.Style)
    {
        self.selectedPrefix = selectedPrefix
        self.selectedText = selectedText
        self.description = description
        self.scrollInfo = scrollInfo
        self.noMatch = noMatch
    }

    public static let `default` = SelectListTheme(
        selectedPrefix: AnsiStyling.color(34),
        selectedText: { AnsiStyling.color(34)(AnsiStyling.bold($0)) },
        description: { "\u{001B}[90m\($0)\u{001B}[0m" },
        scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
        noMatch: { "\u{001B}[90m\($0)\u{001B}[0m" }
    )
}

public final class SelectList: Component {
    public var items: [SelectItem] { didSet { self.filterItems() } }
    public var maxVisible: Int
    public var onSelect: ((SelectItem) -> Void)?
    public var onCancel: (() -> Void)?
    public var onSelectionChange: ((SelectItem) -> Void)?
    public var theme: SelectListTheme { didSet { self.filterItems() } }

    private var filterText: String = "" { didSet { self.filterItems() } }
    private var filtered: [SelectItem] = []
    private var selectedIndex: Int = 0

    public init(items: [SelectItem], maxVisible: Int = 5, theme: SelectListTheme = .default) {
        self.items = items
        self.maxVisible = max(1, maxVisible)
        self.filtered = items
        self.theme = theme
    }

    public func setFilter(_ newValue: String) {
        self.filterText = newValue
    }

    public func render(width: Int) -> [String] {
        guard !self.filtered.isEmpty else {
            return [self.theme.noMatch("  No matching commands")]
        }
        let start = max(0, min(selectedIndex - self.maxVisible / 2, self.filtered.count - self.maxVisible))
        let end = min(filtered.count, start + self.maxVisible)
        var lines: [String] = []
        for index in start..<end {
            let item = self.filtered[index]
            let isSelected = index == self.selectedIndex
            let prefix = isSelected ? self.theme.selectedPrefix("→ ") : "  "
            let title = isSelected ? self.theme.selectedText(item.label) : item.label
            var line = prefix + title
            if let description = item.description, width > 40 {
                let spacing = String(repeating: " ", count: max(1, 32 - title.count))
                let remaining = max(0, width - (prefix.count + title.count + spacing.count) - 2)
                if remaining > 10 {
                    line += spacing + self.theme.description(String(description.prefix(remaining)))
                }
            }
            lines.append(line)
        }
        if self.filtered.count > self.maxVisible {
            lines.append(self.theme.scrollInfo("  (\(self.selectedIndex + 1)/\(self.filtered.count))"))
        }
        return lines
    }

    public func handle(input: TerminalInput) {
        guard case let .key(key, _) = input else { return }
        switch key {
        case .arrowUp:
            self.selectedIndex = max(0, self.selectedIndex - 1)
            self.notifySelectionChange()
        case .arrowDown:
            self.selectedIndex = min(self.filtered.count - 1, self.selectedIndex + 1)
            self.notifySelectionChange()
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
        self.notifySelectionChange()
    }

    private func notifySelectionChange() {
        guard let onSelectionChange, self.filtered.indices.contains(self.selectedIndex) else { return }
        onSelectionChange(self.filtered[self.selectedIndex])
    }

    public func invalidate() {
        // No cached state to clear.
    }

    @MainActor public func apply(theme: ThemePalette) {
        self.theme = theme.selectList
    }
}
