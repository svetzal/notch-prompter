import SwiftUI

@main
struct NotchPrompterApp: App {

    @State private var model = AppModel()

    var body: some Scene {
        Window("Notch Prompter", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1000, minHeight: 560)
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
                .keyboardShortcut(Shortcuts.togglePrompter)
                .disabled(!(model.prompter.session.phase == .hidden || model.prompter.session.phase == .ready))
                Button("Record Take") { model.prompter.record() }
                    .keyboardShortcut(Shortcuts.record)
                    .disabled(!model.canRecord)
                Button("Rehearse") { model.prompter.rehearse() }
                    .keyboardShortcut(Shortcuts.rehearse)
                    .disabled(!model.prompter.session.canBegin)
                Button("Stop") { model.prompter.stop() }
                    .keyboardShortcut(Shortcuts.stop)
                    .disabled(!model.prompter.isPrompterVisible)
            }
        }
        Window("Voice Clean-up Chain", id: VoiceChainEditor.windowID) {
            VoiceChainEditor(voice: model.voice)
        }
        .defaultSize(width: 760, height: 460)
    }
}
