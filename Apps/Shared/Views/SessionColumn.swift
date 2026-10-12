import SwiftUI

/// The right-hand column: the camera, its effects, and the last take.
///
/// The controls for running a take are in the window's toolbar.
struct SessionColumn: View {

    @Bindable var model: AppModel

    var body: some View {
        Form {
            CameraSection(capture: model.capture)
            EffectsSection(capture: model.capture)
            LastTakeSection(capture: model.capture)
        }
        .formStyle(.grouped)
    }
}
