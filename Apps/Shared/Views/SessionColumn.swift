import SwiftUI

/// The right-hand column: everything about running a take.
struct SessionColumn: View {

    @Bindable var model: AppModel

    var body: some View {
        Form {
            TakeControls(prompter: model.prompter, capture: model.capture)
            CameraSection(capture: model.capture)
            EffectsSection(capture: model.capture)
            PrompterControls(prompter: model.prompter)
        }
        .formStyle(.grouped)
    }
}
