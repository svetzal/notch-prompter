import Foundation
import Observation

/// The composition root: one instance per app run, owning every model.
@MainActor
@Observable
final class AppModel {

    let library: ScriptLibrary
    let prompter: PrompterController
    let capture: CaptureModel
    let voice: VoiceModel

    init(
        library: ScriptLibrary = ScriptLibrary(),
        prompter: PrompterController = PrompterController(),
        capture: CaptureModel = CaptureModel(),
        voice: VoiceModel = VoiceModel()
    ) {
        self.library = library
        self.prompter = prompter
        self.capture = capture
        self.voice = voice
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
        capture.finishTake = { [weak self] take in await self?.cleanUpVoice(of: take) }
        Task { await capture.start() }
    }

    /// Whether a recorded take can start now: nothing running, no voice
    /// clean-up under way, and the camera allowed.
    var canRecord: Bool {
        prompter.session.canBegin && !voice.isCleaningUp && capture.access.canUseCamera
    }

    /// The first error any model is holding, for the window's alert.
    var errorMessage: String? {
        library.errorMessage ?? capture.errorMessage ?? voice.errorMessage
    }

    func clearErrors() {
        library.errorMessage = nil
        capture.errorMessage = nil
        voice.errorMessage = nil
    }

    /// A saved take goes through the voice chain when the chain is on.
    private func cleanUpVoice(of take: URL) async {
        guard voice.chain.cleansTakes else { return }
        prompter.voiceCleanUpDidStart()
        await voice.cleanUp(take: take)
    }
}
