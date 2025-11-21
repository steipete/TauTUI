import Foundation
import TauTUI

@MainActor
final class ChatViewModel {
    let tui: TUI
    let messages = Container()
    let editor = Editor()
    let autocomplete: CombinedAutocompleteProvider
    private var isDark = true

    init() {
        let terminal = ProcessTerminal()
        // Entire view model is main-actor bound to keep demo state serialized.
        self.tui = TUI(terminal: terminal)
        // Autocomplete mirrors pi-tui: slash commands + file paths rooted at cwd.
        self.autocomplete = CombinedAutocompleteProvider(
            commands: [
                DemoCommand(name: "clear", description: "Clear all messages"),
                DemoCommand(name: "delete", description: "Delete the last user message"),
            ],
            basePath: FileManager.default.currentDirectoryPath)
        self.editor.setAutocompleteProvider(self.autocomplete)
        self.applyCurrentTheme()
    }

    // Helper to avoid capturing non-Sendable UI state inside escaping closures.
    func removeLoaderAndAppendReply(loader: Loader, reply: String) {
        self.messages.removeChild(loader)
        let replyMarkdown = MarkdownComponent(text: reply, padding: .init(horizontal: 1, vertical: 0))
        self.messages.addChild(replyMarkdown)
        self.tui.requestRender()
    }
}

@main
struct ChatDemo {
    static func main() {
        let vm = ChatViewModel()

        vm.tui.addChild(Text(text: "Welcome to TauTUI Chat!\n\nType your message below. Press Ctrl+C to exit."))
        vm.tui.addChild(vm.messages)
        vm.tui.addChild(vm.editor)
        vm.tui.setFocus(vm.editor)

        vm.editor.onSubmit = { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed == "/clear" {
                vm.messages.clear()
                vm.tui.requestRender()
                return
            }
            if trimmed == "/delete" {
                if let last = vm.messages.children.last {
                    vm.messages.removeChild(last)
                }
                vm.tui.requestRender()
                return
            }
            if trimmed == "/theme" {
                vm.toggleTheme()
                return
            }
            let userMessage = MarkdownComponent(text: trimmed, padding: .init(horizontal: 1, vertical: 0))
            vm.messages.addChild(userMessage)

            let loader = Loader(tui: vm.tui, message: "Thinking...")
            vm.messages.addChild(loader)

            let responses = [
                "That's interesting! Tell me more.",
                "I see what you mean.",
                "Fascinating perspective!",
                "Could you elaborate on that?",
            ]
            let reply = responses.randomElement() ?? "Thanks for sharing!"
            Task { @MainActor [weak vm, loader, reply] in
                guard let vm else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                vm.removeLoaderAndAppendReply(loader: loader, reply: reply)
            }
        }

        do {
            try vm.tui.start()
            RunLoop.main.run()
        } catch {
            let message = "Failed to start TUI: \(error)\n"
            if let data = message.data(using: .utf8) {
                try? FileHandle.standardError.write(contentsOf: data)
            }
            exit(1)
        }
    }
}

extension ChatViewModel {
    func toggleTheme() {
        self.isDark.toggle()
        self.applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        let palette = self.isDark ? ThemePalette.dark() : ThemePalette.light()
        self.tui.apply(theme: palette)
    }
}

private struct DemoCommand: SlashCommand {
    let name: String
    let description: String?

    func argumentCompletions(prefix: String) -> [AutocompleteItem] { [] }
}
