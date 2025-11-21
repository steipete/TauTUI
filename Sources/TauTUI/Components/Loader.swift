import Dispatch

public final class Loader: Component {
    public struct LoaderTheme: Sendable {
        public var spinner: AnsiStyling.Style
        public var message: AnsiStyling.Style

        public init(spinner: @escaping AnsiStyling.Style, message: @escaping AnsiStyling.Style) {
            self.spinner = spinner
            self.message = message
        }

        public static let `default` = LoaderTheme(
            spinner: AnsiStyling.color(36),
            message: { AnsiStyling.dim($0) }
        )
    }
    private enum RenderTarget {
        // Custom render notifier lets tests drive the loader without a TUI.
        case closure(() -> Void)
        // Render callback keeps only a weak reference to TUI to avoid leaks.
        case tui(RenderCallback)
    }

    private final class RenderCallback: @unchecked Sendable {
        weak var tui: TUI?

        init(tui: TUI) {
            self.tui = tui
        }

        func notify() {
            Task { @MainActor [weak self] in
                self?.tui?.requestRender()
            }
        }
    }

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private let renderTarget: RenderTarget
    private var theme: LoaderTheme
    private var frameIndex = 0
    // Timer runs on the main queue; frames are cheap so main-queue delivery is fine.
    private var timer: DispatchSourceTimer?
    private let textComponent = Text(text: "", paddingX: 1, paddingY: 0)

    public private(set) var message: String {
        didSet { self.updateText() }
    }

    public init(tui: TUI, message: String = "Loading...", autoStart: Bool = true, theme: LoaderTheme = .default) {
        self.renderTarget = .tui(RenderCallback(tui: tui))
        self.message = message
        self.theme = theme
        self.updateText()
        if autoStart { self.start() }
    }

    public init(message: String = "Loading...", autoStart: Bool = true, theme: LoaderTheme = .default, renderNotifier: @escaping () -> Void) {
        self.renderTarget = .closure(renderNotifier)
        self.message = message
        self.theme = theme
        self.updateText()
        if autoStart { self.start() }
    }

    deinit {
        stop()
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        self.timer?.cancel()
        self.timer = nil
    }

    public func setMessage(_ newMessage: String) {
        self.message = newMessage
    }

    public func render(width: Int) -> [String] {
        [""] + self.textComponent.render(width: width)
    }

    func tick() {
        self.frameIndex = (self.frameIndex + 1) % Loader.frames.count
        self.updateText()
        self.notifyRender()
    }

    private func notifyRender() {
        switch self.renderTarget {
        case let .closure(handler):
            handler()
        case let .tui(callback):
            callback.notify()
        }
    }

    private func updateText() {
        let frame = Loader.frames[self.frameIndex]
        self.textComponent.text = "\(self.theme.spinner(frame)) \(self.theme.message(self.message))"
    }

    public func invalidate() {
        self.textComponent.invalidate()
    }

    @MainActor public func apply(theme: ThemePalette) {
        self.theme = theme.loader
        self.textComponent.invalidate()
    }
}
