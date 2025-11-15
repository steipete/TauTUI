import Foundation
import TauTUI

@MainActor
final class ChatViewModel {
    let tui: TUI
    let messages = Container()
    let editor = Editor()
    let autocomplete: CombinedAutocompleteProvider

    init() {
        let terminal = ProcessTerminal()
        // Entire view model is main-actor bound to keep demo state serialized.
        tui = TUI(terminal: terminal)
        // Autocomplete mirrors pi-tui: slash commands + file paths rooted at cwd.
        autocomplete = CombinedAutocompleteProvider(commands: [DemoCommand()], basePath: FileManager.default.currentDirectoryPath)
        editor.setAutocompleteProvider(autocomplete)
    }

    // Helper to avoid capturing non-Sendable UI state inside escaping closures.
    func removeLoaderAndAppendReply(loader: Loader, reply: String) {
        messages.removeChild(loader)
        let replyMarkdown = MarkdownComponent(text: reply, padding: .init(horizontal: 1, vertical: 0))
        messages.addChild(replyMarkdown)
        tui.requestRender()
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
            let userMessage = MarkdownComponent(text: trimmed, padding: .init(horizontal: 1, vertical: 0))
            vm.messages.addChild(userMessage)

            let loader = Loader(tui: vm.tui, message: "Thinking...")
            vm.messages.addChild(loader)
            let loaderID = ObjectIdentifier(loader)

            let responses = [
                "That's interesting! Tell me more.",
                "I see what you mean.",
                "Fascinating perspective!",
                "Could you elaborate on that?"
            ]
            let reply = responses.randomElement() ?? "Thanks for sharing!"
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    // Resolve loader by identity on the main actor to avoid capturing non-Sendable state.
                    if let found = vm.messages.children.first(where: { ObjectIdentifier($0) == loaderID }) as? Loader {
                        vm.removeLoaderAndAppendReply(loader: found, reply: reply)
                    }
                }
            }
        }

        do {
            try vm.tui.start()
            RunLoop.main.run()
        } catch {
            fputs("Failed to start TUI: \(error)\n", stderr)
            exit(1)
        }
    }
}

private struct DemoCommand: SlashCommand {
    let name = "clear"
    let description: String? = "Clear all messages"

    func argumentCompletions(prefix: String) -> [AutocompleteItem] { [] }
}
