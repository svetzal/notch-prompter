import Testing
@testable import NotchPrompterKit

@Suite("Microphone mode")
struct MicrophoneModeTests {

    @Test(
        "maps the system's raw values to the three modes",
        arguments: [
            (0, MicrophoneMode.standard),
            (1, MicrophoneMode.wideSpectrum),
            (2, MicrophoneMode.voiceIsolation)
        ]
    )
    func knownRawValues(rawValue: Int, mode: MicrophoneMode) {
        #expect(MicrophoneMode(systemRawValue: rawValue) == mode)
    }

    @Test("keeps a raw value it does not know, instead of failing", arguments: [-1, 3, 42])
    func unknownRawValues(rawValue: Int) {
        #expect(MicrophoneMode(systemRawValue: rawValue) == .unknown(rawValue: rawValue))
    }

    @Test(
        "names each mode as Control Center does",
        arguments: [
            (MicrophoneMode.standard, "Standard"),
            (MicrophoneMode.voiceIsolation, "Voice Isolation"),
            (MicrophoneMode.wideSpectrum, "Wide Spectrum"),
            (MicrophoneMode.unknown(rawValue: 7), "Unknown (7)")
        ]
    )
    func displayNames(mode: MicrophoneMode, name: String) {
        #expect(mode.displayName == name)
    }
}

@Suite("Microphone mode presentation")
struct MicrophoneModePresentationTests {

    @Test(
        "when the chosen mode is in use, shows it with no note",
        arguments: [MicrophoneMode.standard, .voiceIsolation, .wideSpectrum]
    )
    func chosenModeInUse(mode: MicrophoneMode) {
        let presentation = MicrophoneModePresentation(preferred: mode, active: mode)
        #expect(presentation.label == mode.displayName)
        #expect(presentation.note == nil)
        #expect(!presentation.isMismatched)
    }

    @Test("when the microphone cannot use the chosen mode, shows the mode in use and says so")
    func voiceIsolationNotInUse() {
        let presentation = MicrophoneModePresentation(preferred: .voiceIsolation, active: .standard)
        #expect(presentation.label == "Standard")
        #expect(presentation.note == "Voice Isolation chosen, Standard in use with this microphone.")
        #expect(presentation.isMismatched)
    }

    @Test(
        "any difference between the chosen and the active mode is visible",
        arguments: [
            (MicrophoneMode.wideSpectrum, MicrophoneMode.standard),
            (.standard, .voiceIsolation),
            (.voiceIsolation, .wideSpectrum)
        ]
    )
    func everyMismatchHasANote(preferred: MicrophoneMode, active: MicrophoneMode) {
        let presentation = MicrophoneModePresentation(preferred: preferred, active: active)
        #expect(presentation.isMismatched)
        #expect(presentation.label == active.displayName)
        #expect(presentation.note == "\(preferred.displayName) chosen, \(active.displayName) in use with this microphone.")
    }

    @Test("an unknown mode shows its raw value rather than a guess")
    func unknownActiveMode() {
        let presentation = MicrophoneModePresentation(preferred: .voiceIsolation, active: .unknown(rawValue: 3))
        #expect(presentation.label == "Unknown (3)")
        #expect(presentation.note == "Voice Isolation chosen, Unknown (3) in use with this microphone.")
        #expect(presentation.isMismatched)
    }

    @Test("the same unknown mode chosen and in use is not a mismatch")
    func sameUnknownMode() {
        let presentation = MicrophoneModePresentation(preferred: .unknown(rawValue: 3), active: .unknown(rawValue: 3))
        #expect(presentation.label == "Unknown (3)")
        #expect(presentation.note == nil)
        #expect(!presentation.isMismatched)
    }
}
