import SwiftUI

/// The right-hand column: the camera, its effects, the voice clean-up, and
/// the last take.
///
/// The controls for running a take are in the window's toolbar.
struct SessionColumn: View {

    @Bindable var model: AppModel

    var body: some View {
        Form {
            CameraSection(capture: model.capture, isTakeInProgress: model.prompter.session.isTakeInProgress)
            EffectsSection(capture: model.capture)
            VoiceSection(voice: model.voice)
            LastTakeSection(
                capture: model.capture,
                voice: model.voice,
                isTakeBusy: model.prompter.session.isTakeInProgress || model.prompter.session.isFinishingTake
            )
        }
        .formStyle(.grouped)
    }
}
