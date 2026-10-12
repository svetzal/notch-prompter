import SwiftUI

/// The main window: scripts on the left, the selected script on the right.
struct RootView: View {

    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            ScriptSidebar(library: model.library)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            HStack(spacing: 0) {
                ScriptEditor(library: model.library, wordsPerMinute: model.prompter.settings.wordsPerMinute)
                    .frame(minWidth: 360)
                Divider()
                SessionColumn(model: model)
                    .frame(width: 340)
            }
            .navigationTitle(model.library.selectedTitle ?? "Notch Prompter")
        }
        .alert("Something went wrong", isPresented: hasError) {
            Button("OK") { model.library.errorMessage = nil }
        } message: {
            Text(model.library.errorMessage ?? "")
        }
    }

    private var hasError: Binding<Bool> {
        Binding(
            get: { model.library.errorMessage != nil },
            set: { if !$0 { model.library.errorMessage = nil } }
        )
    }
}
