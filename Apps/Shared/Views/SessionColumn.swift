import SwiftUI

/// The right-hand column: everything about running a take.
struct SessionColumn: View {

    @Bindable var model: AppModel

    var body: some View {
        Form {
            PrompterControls(prompter: model.prompter)
        }
        .formStyle(.grouped)
    }
}
