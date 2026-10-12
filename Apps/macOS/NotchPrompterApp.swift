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
        }
    }
}
