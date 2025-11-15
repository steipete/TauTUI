import Dispatch

public final class Loader: Component {
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
    private var frameIndex = 0
    // Timer runs on the main queue; frames are cheap so main-queue delivery is fine.
    private var timer: DispatchSourceTimer?
    private let textComponent = Text(text: "", paddingX: 1, paddingY: 0)

    public private(set) var message: String {
        didSet { self.updateText() }
    }

    public init(tui: TUI, message: String = "Loading...", autoStart: Bool = true) {
        self.renderTarget = .tui(RenderCallback(tui: tui))
        self.message = message
        self.updateText()
        if autoStart { self.start() }
    }

    public init(message: String = "Loading...", autoStart: Bool = true, renderNotifier: @escaping () -> Void) {
        self.renderTarget = .closure(renderNotifier)
        self.message = message
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
        self.textComponent.text = "\(frame) \(self.message)"
    }
}
