import AVFoundation
import NotchPrompterKit

/// Reads and observes the system microphone mode, and opens the system
/// Microphone Modes panel.
///
/// `preferredMicrophoneMode` and `activeMicrophoneMode` are read-only class
/// properties. The app cannot set the mode; the panel is the only control.
@MainActor
final class MicrophoneModeGateway {

    var onChange: (@MainActor () -> Void)?

    private var classObserver: ClassKeyObserver?

    init() {
        classObserver = ClassKeyObserver(keyPaths: ["preferredMicrophoneMode", "activeMicrophoneMode"]) { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
    }

    /// The user's choice in Control Center.
    var preferred: MicrophoneMode {
        MicrophoneMode(systemRawValue: AVCaptureDevice.preferredMicrophoneMode.rawValue)
    }

    /// The mode in use with the app's current audio route.
    var active: MicrophoneMode {
        MicrophoneMode(systemRawValue: AVCaptureDevice.activeMicrophoneMode.rawValue)
    }

    func showMicrophoneModesPanel() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}
