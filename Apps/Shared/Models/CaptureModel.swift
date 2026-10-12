import AppKit
import AVFoundation
import NotchPrompterKit
import Observation

/// The camera, the microphone, their permissions, and the video effects.
@MainActor
@Observable
final class CaptureModel {

    private(set) var access = CaptureAccess(camera: .notDetermined, microphone: .notDetermined)
    private(set) var cameras: [CaptureDeviceInfo] = []
    private(set) var microphones: [CaptureDeviceInfo] = []
    private(set) var activeCameraID: String?
    private(set) var activeMicrophoneID: String?
    private(set) var effects = EffectsPresentation(.noCamera)
    /// The last take that finished writing.
    private(set) var lastRecording: URL?
    var errorMessage: String?

    /// Called when a take's movie file closes, whether it worked or not.
    @ObservationIgnored var onRecordingEnded: (@MainActor () -> Void)?

    /// The camera chosen in the window, remembered while it is disconnected.
    var preferredCameraID: String? {
        didSet {
            defaults.set(preferredCameraID, forKey: Keys.camera)
            applySelection()
        }
    }

    var preferredMicrophoneID: String? {
        didSet {
            defaults.set(preferredMicrophoneID, forKey: Keys.microphone)
            applySelection()
        }
    }

    /// While a take records, inputs must not change. Changes wait until this clears.
    var isConfigurationLocked = false {
        didSet {
            if !isConfigurationLocked {
                applySelection()
            }
        }
    }

    @ObservationIgnored let gateway = CaptureSessionGateway()
    @ObservationIgnored private let discovery = DeviceDiscovery()
    @ObservationIgnored private let effectsGateway = EffectsGateway()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var configuration: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    /// Whether the current take still wants a recording. Guards against a
    /// stop that arrives while the start is still on its way to the session.
    @ObservationIgnored private var wantsRecording = false
    @ObservationIgnored private var outcomeListener: Task<Void, Never>?

    private enum Keys {
        static let camera = "capture.cameraID"
        static let microphone = "capture.microphoneID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredCameraID = defaults.string(forKey: Keys.camera)
        preferredMicrophoneID = defaults.string(forKey: Keys.microphone)
        discovery.onChange = { [weak self] in self?.refreshDevices() }
        effectsGateway.onChange = { [weak self] in self?.refreshEffects() }
        outcomeListener = Task { [weak self, outcomes = gateway.recordingOutcomes] in
            for await outcome in outcomes {
                self?.recordingFinished(outcome)
            }
        }
    }

    // MARK: - Starting

    /// Asks for permission if needed, then starts the camera.
    func start() async {
        refreshAccess()
        if access.needsRequest {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshAccess()
        }
        hasStarted = true
        refreshDevices()
    }

    /// Rechecks permission, for when the person comes back from System Settings.
    func recheckAccess() {
        let before = access
        refreshAccess()
        if access != before {
            applySelection()
        }
    }

    func openPrivacySettings(for medium: CaptureAccess.Medium) {
        let pane = medium == .camera ? "Privacy_Camera" : "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAccess() {
        access = CaptureAccess(
            camera: Self.status(AVCaptureDevice.authorizationStatus(for: .video)),
            microphone: Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
        )
    }

    private static func status(_ status: AVAuthorizationStatus) -> CaptureAccess.Status {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    // MARK: - Devices

    private func refreshDevices() {
        cameras = discovery.cameras
        microphones = discovery.microphones
        applySelection()
    }

    /// Puts the resolved camera and microphone into the session.
    ///
    /// Configuration calls are chained so they reach the session in the
    /// order they were made, even when devices change in quick succession.
    private func applySelection() {
        guard hasStarted, !isConfigurationLocked else { return }
        let camera = access.canUseCamera ? PreferredSelection.resolve(
            preferred: preferredCameraID,
            available: cameras.map(\.id),
            fallbacks: [discovery.systemPreferredCameraID]
        ) : nil
        let microphone = access.canUseMicrophone ? PreferredSelection.resolve(
            preferred: preferredMicrophoneID,
            available: microphones.map(\.id),
            fallbacks: [discovery.defaultMicrophoneID]
        ) : nil
        guard camera != activeCameraID || microphone != activeMicrophoneID || configuration == nil else { return }
        activeCameraID = camera
        activeMicrophoneID = microphone
        effectsGateway.follow(deviceID: camera)

        let previous = configuration
        let gateway = gateway
        configuration = Task { [weak self] in
            await previous?.value
            do {
                try await gateway.use(videoDeviceID: camera, audioDeviceID: microphone)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Effects

    private func refreshEffects() {
        effects = EffectsPresentation(effectsGateway.snapshot)
    }

    func setCenterStage(_ enabled: Bool) {
        effectsGateway.setCenterStage(enabled)
        refreshEffects()
    }

    func performReaction(_ rawValue: String) {
        effectsGateway.performReaction(rawValue)
    }

    func showVideoEffectsPanel() {
        effectsGateway.showVideoEffectsPanel()
    }

    // MARK: - Recording

    private func recordingFinished(_ outcome: RecordingOutcome) {
        if let failure = outcome.failure {
            errorMessage = "The take did not finish recording: \(failure)"
        } else {
            lastRecording = outcome.url
            NSWorkspace.shared.activateFileViewerSelecting([outcome.url])
        }
        endRecording()
    }

    private func endRecording() {
        wantsRecording = false
        isConfigurationLocked = false
        onRecordingEnded?()
    }
}

extension CaptureModel: TakeRecorder {

    func startRecording(scriptTitle: String?) {
        wantsRecording = true
        isConfigurationLocked = true
        let pendingConfiguration = configuration
        let gateway = gateway
        Task { [weak self] in
            await pendingConfiguration?.value
            guard let self, wantsRecording else {
                self?.endRecording()
                return
            }
            do {
                let existing = try RecordingFolder.prepare()
                let name = RecordingNaming.uniqueFileName(
                    RecordingNaming.fileName(scriptTitle: scriptTitle, date: .now),
                    existing: existing
                )
                try await gateway.startRecording(to: RecordingFolder.url.appending(path: name))
                if !wantsRecording {
                    await gateway.stopRecording()
                }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                endRecording()
            }
        }
    }

    func stopRecording() {
        wantsRecording = false
        let gateway = gateway
        Task { await gateway.stopRecording() }
    }
}
