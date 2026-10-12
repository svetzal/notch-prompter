/// The system microphone mode, as Control Center's Mic Mode sets it.
///
/// It mirrors `AVCaptureDevice.MicrophoneMode`. The app can read the mode
/// but cannot set it; only the user can, in the system Microphone Modes
/// panel. A raw value the app does not know reads as ``unknown(rawValue:)``,
/// so a mode added in a later macOS shows up instead of failing.
public enum MicrophoneMode: Equatable, Hashable, Sendable {
    case standard
    case voiceIsolation
    case wideSpectrum
    case unknown(rawValue: Int)

    /// Maps the raw value of `AVCaptureDevice.MicrophoneMode`: standard is
    /// 0, wide spectrum is 1, and voice isolation is 2 (`AVCaptureDevice.h`).
    public init(systemRawValue: Int) {
        switch systemRawValue {
        case 0: self = .standard
        case 1: self = .wideSpectrum
        case 2: self = .voiceIsolation
        default: self = .unknown(rawValue: systemRawValue)
        }
    }

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .voiceIsolation: "Voice Isolation"
        case .wideSpectrum: "Wide Spectrum"
        case .unknown(let rawValue): "Unknown (\(rawValue))"
        }
    }
}

/// What the window shows for the microphone mode.
///
/// `preferred` is the user's choice in Control Center. `active` is the mode
/// in use, which differs when the app's audio route does not support the
/// choice. Whether a mode applies to a capture session's recording at all is
/// not known yet, so a difference is always shown, never hidden.
public struct MicrophoneModePresentation: Equatable, Sendable {

    public let preferred: MicrophoneMode
    public let active: MicrophoneMode

    public init(preferred: MicrophoneMode, active: MicrophoneMode) {
        self.preferred = preferred
        self.active = active
    }

    /// The chosen mode is not the one in use.
    public var isMismatched: Bool {
        preferred != active
    }

    /// The mode in use.
    public var label: String {
        active.displayName
    }

    /// Says which mode was chosen when it is not the one in use.
    public var note: String? {
        guard isMismatched else { return nil }
        return "\(preferred.displayName) chosen, \(active.displayName) in use with this microphone."
    }
}
