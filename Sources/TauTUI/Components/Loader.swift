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
        didSet { updateText() }
    }

    public init(tui: TUI, message: String = "Loading...", autoStart: Bool = true) {
        self.renderTarget = .tui(RenderCallback(tui: tui))
        self.message = message
        updateText()
        if autoStart { start() }
    }

    public init(message: String = "Loading...", autoStart: Bool = true, renderNotifier: @escaping () -> Void) {
        self.renderTarget = .closure(renderNotifier)
        self.message = message
        updateText()
        if autoStart { start() }
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
        timer?.cancel()
        timer = nil
    }

    public func setMessage(_ newMessage: String) {
        message = newMessage
    }

    public func render(width: Int) -> [String] {
        [""] + textComponent.render(width: width)
    }

    func tick() {
        frameIndex = (frameIndex + 1) % Loader.frames.count
        updateText()
        notifyRender()
    }

    private func notifyRender() {
        switch renderTarget {
        case .closure(let handler):
            handler()
        case .tui(let callback):
            callback.notify()
        }
    }

    private func updateText() {
        let frame = Loader.frames[frameIndex]
        textComponent.text = "\(frame) \(message)"
    }
}
