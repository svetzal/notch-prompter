import SwiftUI

/// The right-hand column: everything about running a take.
struct SessionColumn: View {

    @Bindable var model: AppModel

    var body: some View {
        Form {
            CameraSection(capture: model.capture)
            EffectsSection(capture: model.capture)
            PrompterControls(prompter: model.prompter)
        }
        .formStyle(.grouped)
    }
}
