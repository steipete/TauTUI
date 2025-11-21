import Testing
@testable import TauTUI

private final class ThemeAwareComponent: Component {
    var applied: ThemePalette = .default
    func render(width: Int) -> [String] { ["ok"] }
    func apply(theme: ThemePalette) { self.applied = theme }
}

@Suite("Theme propagation")
@MainActor
struct ThemePropagationTests {
    @Test
    func tuiAppliesThemeToChildren() async throws {
        let child = ThemeAwareComponent()
        let tui = TUI(terminal: VirtualTerminal())
        tui.addChild(child)

        var updated = ThemePalette()
        updated.editor = .init(borderColor: { "**" + $0 }, selectList: .default)
        tui.apply(theme: updated)

        #expect(child.applied.editor.borderColor("x").contains("**"))
    }
}
