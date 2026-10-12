import SwiftUI

@main
struct NotchPrompterApp: App {

    @State private var model = AppModel()

    var body: some Scene {
        Window("Notch Prompter", id: "main") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script") { model.library.createScript() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.library.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Prompter") {
                Button(model.prompter.isPrompterVisible ? "Hide Prompter" : "Show Prompter") {
                    model.prompter.togglePrompter()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!(model.prompter.session.phase == .hidden || model.prompter.session.phase == .ready))
                Button("Record Take") { model.prompter.record() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.prompter.session.canBegin || !model.capture.access.canUseCamera)
                Button("Rehearse") { model.prompter.rehearse() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.prompter.session.canBegin)
                Button("Stop") { model.prompter.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.prompter.isPrompterVisible)
            }
        }
    }
}
