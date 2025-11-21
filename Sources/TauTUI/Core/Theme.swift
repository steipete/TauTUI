import Foundation

/// Aggregate theme passed to components that support theming.
public struct ThemePalette: Sendable {
    public var editor: EditorTheme
    public var selectList: SelectListTheme
    public var markdown: MarkdownComponent.MarkdownTheme
    public var textBackground: Text.Background?
    public var loader: Loader.LoaderTheme
    public var truncatedBackground: AnsiStyling.Background?

    public init(
        editor: EditorTheme = .default,
        selectList: SelectListTheme = .default,
        markdown: MarkdownComponent.MarkdownTheme = .default,
        textBackground: Text.Background? = nil,
        loader: Loader.LoaderTheme = .default,
        truncatedBackground: AnsiStyling.Background? = nil)
    {
        self.editor = editor
        self.selectList = selectList
        self.markdown = markdown
        self.textBackground = textBackground
        self.loader = loader
        self.truncatedBackground = truncatedBackground
    }

    public static let `default` = ThemePalette()

    /// High-contrast dark preset.
    public static func dark() -> ThemePalette {
        ThemePalette(
            editor: .init(
                borderColor: AnsiStyling.color(36),
                selectList: .default),
            selectList: .default,
            markdown: .default,
            textBackground: .init(red: 24, green: 26, blue: 32),
            loader: .default,
            truncatedBackground: .rgb(24, 26, 32))
    }

    /// Light preset for terminals with light backgrounds.
    public static func light() -> ThemePalette {
        ThemePalette(
            editor: .init(
                borderColor: AnsiStyling.color(30),
                selectList: SelectListTheme(
                    selectedPrefix: AnsiStyling.color(34),
                    selectedText: { AnsiStyling.color(34)(AnsiStyling.bold($0)) },
                    description: AnsiStyling.dim,
                    scrollInfo: AnsiStyling.dim,
                    noMatch: AnsiStyling.dim)),
            selectList: .default,
            markdown: .default,
            textBackground: nil,
            loader: Loader.LoaderTheme(
                spinner: AnsiStyling.color(34),
                message: AnsiStyling.dim),
            truncatedBackground: nil)
    }
}

/// Components that react to theme changes can conform to this protocol.
public protocol ThemeUpdatable: AnyObject {
    func apply(theme: ThemePalette)
}

public extension ThemeUpdatable {
    func apply(theme: ThemePalette) {}
}
