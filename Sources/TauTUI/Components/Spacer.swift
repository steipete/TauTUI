/// Renders blank lines for vertical spacing.
public final class Spacer: Component {
    private var storage: Int

    public var lines: Int {
        get { storage }
        set { storage = max(0, newValue) }
    }

    public init(lines: Int = 1) {
        self.storage = max(0, lines)
    }

    public func render(width: Int) -> [String] {
        guard storage > 0 else { return [] }
        return Array(repeating: "", count: storage)
    }
}
