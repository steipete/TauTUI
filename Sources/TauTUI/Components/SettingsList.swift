import Foundation

public struct SettingItem {
    public let id: String
    public let label: String
    public let description: String?
    public var currentValue: String
    public let values: [String]?
    public let submenu: ((String, @escaping (String?) -> Void) -> any Component)?

    public init(
        id: String,
        label: String,
        description: String? = nil,
        currentValue: String,
        values: [String]? = nil,
        submenu: ((String, @escaping (String?) -> Void) -> any Component)? = nil)
    {
        self.id = id
        self.label = label
        self.description = description
        self.currentValue = currentValue
        self.values = values
        self.submenu = submenu
    }
}

public struct SettingsListTheme: Sendable {
    public var label: @Sendable (_ text: String, _ selected: Bool) -> String
    public var value: @Sendable (_ text: String, _ selected: Bool) -> String
    public var description: @Sendable (_ text: String) -> String
    public var cursor: String
    public var hint: @Sendable (_ text: String) -> String

    public init(
        label: @escaping @Sendable (_ text: String, _ selected: Bool) -> String,
        value: @escaping @Sendable (_ text: String, _ selected: Bool) -> String,
        description: @escaping @Sendable (_ text: String) -> String,
        cursor: String,
        hint: @escaping @Sendable (_ text: String) -> String)
    {
        self.label = label
        self.value = value
        self.description = description
        self.cursor = cursor
        self.hint = hint
    }

    public static let `default` = SettingsListTheme(
        label: { text, selected in selected ? "\u{001B}[1m\(text)\u{001B}[22m" : text },
        value: { text, selected in selected ? "\u{001B}[7m \(text) \u{001B}[27m" : text },
        description: { "\u{001B}[90m\($0)\u{001B}[39m" },
        cursor: "\u{001B}[36m›\u{001B}[39m ",
        hint: { "\u{001B}[90m\($0)\u{001B}[39m" })
}

public final class SettingsList: Component {
    private var items: [SettingItem]
    private let maxVisible: Int
    private let theme: SettingsListTheme
    private let onChange: (String, String) -> Void
    private let onCancel: () -> Void

    private var selectedIndex: Int = 0
    private var submenuComponent: (any Component)?
    private var submenuItemIndex: Int?

    public init(
        items: [SettingItem],
        maxVisible: Int = 10,
        theme: SettingsListTheme = .default,
        onChange: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void)
    {
        self.items = items
        self.maxVisible = max(1, maxVisible)
        self.theme = theme
        self.onChange = onChange
        self.onCancel = onCancel
    }

    public func updateValue(id: String, newValue: String) {
        guard let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
        self.items[idx].currentValue = newValue
    }

    public func invalidate() {
        self.submenuComponent?.invalidate()
    }

    public func render(width: Int) -> [String] {
        if let submenuComponent {
            return submenuComponent.render(width: width)
        }
        return self.renderMainList(width: width)
    }

    public func handle(input: TerminalInput) {
        if let submenuComponent {
            submenuComponent.handle(input: input)
            return
        }

        switch input {
        case .key(.arrowUp, _):
            if self.items.isEmpty { return }
            self.selectedIndex = self.selectedIndex == 0 ? self.items.count - 1 : self.selectedIndex - 1
        case .key(.arrowDown, _):
            if self.items.isEmpty { return }
            self.selectedIndex = self.selectedIndex == self.items.count - 1 ? 0 : self.selectedIndex + 1
        case .key(.enter, _), .key(.character(" "), _):
            self.activateSelectedItem()
        case .key(.escape, _):
            self.onCancel()
        case let .key(.character("c"), modifiers)
            where modifiers.contains(.control):
            self.onCancel()
        default:
            break
        }
    }

    private func renderMainList(width: Int) -> [String] {
        if self.items.isEmpty {
            return [self.theme.hint("  No settings available")]
        }

        var lines: [String] = []

        let startIndex = max(
            0,
            min(self.selectedIndex - (self.maxVisible / 2), self.items.count - self.maxVisible))
        let endIndex = min(startIndex + self.maxVisible, self.items.count)

        let maxLabelWidth = min(30, self.items.map { VisibleWidth.measure($0.label) }.max() ?? 0)

        for index in startIndex..<endIndex {
            let item = self.items[index]
            let isSelected = index == self.selectedIndex

            let prefix = isSelected ? self.theme.cursor : "  "
            let prefixWidth = VisibleWidth.measure(prefix)

            let labelPadCount = max(0, maxLabelWidth - VisibleWidth.measure(item.label))
            let labelPadded = item.label + String(repeating: " ", count: labelPadCount)
            let labelText = self.theme.label(labelPadded, isSelected)

            let separator = "  "
            let usedWidth = prefixWidth + maxLabelWidth + VisibleWidth.measure(separator)
            let valueMaxWidth = max(0, width - usedWidth - 2)
            let valueText = self.theme.value(
                TruncatedText.truncate(item.currentValue, toWidth: valueMaxWidth),
                isSelected)

            lines.append(prefix + labelText + separator + valueText)
        }

        if startIndex > 0 || endIndex < self.items.count {
            let scrollText = "  (\(self.selectedIndex + 1)/\(self.items.count))"
            lines.append(self.theme.hint(TruncatedText.truncate(scrollText, toWidth: max(0, width - 2))))
        }

        if let desc = self.items[self.selectedIndex].description {
            lines.append("")
            lines.append(self.theme.description("  " + TruncatedText.truncate(desc, toWidth: max(0, width - 4))))
        }

        lines.append("")
        lines.append(self.theme.hint("  Enter/Space to change · Esc to cancel"))
        return lines
    }

    private func activateSelectedItem() {
        guard !self.items.isEmpty else { return }
        var item = self.items[self.selectedIndex]

        if let submenu = item.submenu {
            self.submenuItemIndex = self.selectedIndex
            self.submenuComponent = submenu(item.currentValue) { [weak self] selectedValue in
                guard let self else { return }
                if let selectedValue {
                    self.items[self.selectedIndex].currentValue = selectedValue
                    self.onChange(item.id, selectedValue)
                }
                self.closeSubmenu()
            }
            return
        }

        if let values = item.values, !values.isEmpty {
            let currentIndex = values.firstIndex(of: item.currentValue) ?? -1
            let nextIndex = (currentIndex + 1) % values.count
            let newValue = values[nextIndex]
            item.currentValue = newValue
            self.items[self.selectedIndex] = item
            self.onChange(item.id, newValue)
        }
    }

    private func closeSubmenu() {
        self.submenuComponent = nil
        if let submenuItemIndex {
            self.selectedIndex = submenuItemIndex
            self.submenuItemIndex = nil
        }
    }
}
