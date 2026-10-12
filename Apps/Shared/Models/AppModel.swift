import Foundation
import Observation

/// The composition root: one instance per app run, owning every model.
@MainActor
@Observable
final class AppModel {

    let library: ScriptLibrary
    let prompter: PrompterController
    let capture: CaptureModel

    init(
        library: ScriptLibrary = ScriptLibrary(),
        prompter: PrompterController = PrompterController(),
        capture: CaptureModel = CaptureModel()
    ) {
        self.library = library
        self.prompter = prompter
        self.capture = capture
        prompter.setDocument(library.document)
        prompter.scriptTitle = library.selectedTitle
        library.onChange = { [weak prompter, weak library] in
            guard let prompter, let library else { return }
            let switchedScript = prompter.scriptTitle != library.selectedTitle
            prompter.setDocument(library.document)
            prompter.scriptTitle = library.selectedTitle
            if switchedScript {
                prompter.rewindIfIdle()
            }
        }
        prompter.recorder = capture
        capture.onRecordingEnded = { [weak prompter] in prompter?.recordingDidEnd() }
        Task { await capture.start() }
    }

    /// The first error any model is holding, for the window's alert.
    var errorMessage: String? {
        library.errorMessage ?? capture.errorMessage
    }

    func clearErrors() {
        library.errorMessage = nil
        capture.errorMessage = nil
    }
}
