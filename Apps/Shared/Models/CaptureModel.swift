import AppKit
import AVFoundation
import NotchPrompterKit
import Observation
import os

/// The camera, the microphone, their permissions, the video effects, and the video format.
@MainActor
@Observable
final class CaptureModel {

    private(set) var access = CaptureAccess(camera: .notDetermined, microphone: .notDetermined)
    private(set) var cameras: [CaptureDeviceInfo] = []
    private(set) var microphones: [CaptureDeviceInfo] = []
    private(set) var activeCameraID: String?
    private(set) var activeMicrophoneID: String?
    /// The take shape the session was last configured for.
    @ObservationIgnored private var activeVideoFormat: VideoFormat?
    private(set) var effects = EffectsPresentation(.noCamera)
    /// The camera's current frame size, `nil` without a camera.
    private(set) var cameraSize: PixelSize?
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

    /// The shape the next take records in. Changing it switches the camera
    /// to a native format for that shape, when it has one, right away rather
    /// than at Record, so the preview shows what the take will record.
    var videoFormat: VideoFormat {
        didSet {
            defaults.set(videoFormat.rawValue, forKey: Keys.videoFormat)
            applySelection()
        }
    }

    /// The part of the camera's frame the next take keeps, for the preview.
    var previewCrop: VideoCrop? {
        cameraSize.map { VideoCrop(source: $0, format: videoFormat) }
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
    /// The format of the take being recorded, for checking the finished file.
    @ObservationIgnored private var recordingFormat = VideoFormat.horizontal

    private enum Keys {
        static let camera = "capture.cameraID"
        static let microphone = "capture.microphoneID"
        static let videoFormat = "capture.videoFormat"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredCameraID = defaults.string(forKey: Keys.camera)
        preferredMicrophoneID = defaults.string(forKey: Keys.microphone)
        videoFormat = defaults.string(forKey: Keys.videoFormat).flatMap(VideoFormat.init(rawValue:)) ?? .horizontal
        discovery.onChange = { [weak self] in self?.refreshDevices() }
        effectsGateway.onChange = { [weak self] in self?.refreshCameraState() }
        outcomeListener = Task { [weak self, outcomes = gateway.recordingOutcomes] in
            for await outcome in outcomes {
                await self?.recordingFinished(outcome)
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
        let format = videoFormat
        guard camera != activeCameraID || microphone != activeMicrophoneID || format != activeVideoFormat
            || configuration == nil else { return }
        activeCameraID = camera
        activeMicrophoneID = microphone
        activeVideoFormat = format
        effectsGateway.follow(deviceID: camera)

        let previous = configuration
        let gateway = gateway
        configuration = Task { [weak self] in
            await previous?.value
            do {
                let formatSwitch = try await gateway.use(videoDeviceID: camera, audioDeviceID: microphone, videoFormat: format)
                if let formatSwitch {
                    Self.logFormatSwitch(formatSwitch)
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            // The camera's format may have changed; the preview and the effects read it again.
            self?.refreshCameraState()
        }
    }

    private static func logFormatSwitch(_ formatSwitch: CameraFormatSwitch) {
        let format = formatSwitch.videoFormat.rawValue
        if formatSwitch.isNative {
            Logger.recording.notice("""
                Camera switched from the session preset's \(formatSwitch.presetSize, privacy: .public) \
                to its native \(formatSwitch.size, privacy: .public) format for \(format, privacy: .public) takes
                """)
        } else if formatSwitch.videoFormat == .vertical {
            Logger.recording.notice("""
                Camera has no native vertical format; it uses the session preset's \
                \(formatSwitch.size, privacy: .public) and each vertical take is cropped
                """)
        } else {
            Logger.recording.notice(
                "Camera uses the session preset's \(formatSwitch.size, privacy: .public) for \(format, privacy: .public) takes"
            )
        }
    }

    // MARK: - Effects and format

    private func refreshCameraState() {
        effects = EffectsPresentation(effectsGateway.snapshot)
        cameraSize = effectsGateway.formatSize
    }

    func setCenterStage(_ enabled: Bool) {
        effectsGateway.setCenterStage(enabled)
        refreshCameraState()
    }

    func performReaction(_ rawValue: String) {
        effectsGateway.performReaction(rawValue)
    }

    func showVideoEffectsPanel() {
        effectsGateway.showVideoEffectsPanel()
    }

    // MARK: - Recording

    /// Checks the finished take's shape before showing it. The take stays
    /// "Saving" until the check, and any re-crop, is done.
    private func recordingFinished(_ outcome: RecordingOutcome) async {
        if let failure = outcome.failure {
            errorMessage = "The take did not finish recording: \(failure)"
        } else {
            do {
                try await Self.confirmShape(of: outcome.url, format: recordingFormat)
            } catch {
                Logger.recording.error("Could not give the take its shape: \(error.localizedDescription, privacy: .public)")
                errorMessage = "The take was saved, but could not be made \(recordingFormat.displayName.lowercased()): "
                    + error.localizedDescription
            }
            lastRecording = outcome.url
            NSWorkspace.shared.activateFileViewerSelecting([outcome.url])
        }
        endRecording()
    }

    /// The self-check on a finished take. If the encoder did not write the
    /// format's shape, the movie is cut to it from the centre and replaced.
    nonisolated private static func confirmShape(of url: URL, format: VideoFormat) async throws {
        let track = try await MovieFile.videoTrack(of: url)
        let shown = track.displayedSize
        if format.hasShape(of: shown) {
            Logger.recording.notice(
                "Take is \(shown, privacy: .public), the \(format.rawValue, privacy: .public) shape; no re-crop needed"
            )
            return
        }
        let crop = VideoCrop(source: shown, format: format)
        Logger.recording.notice("""
            Take is \(shown, privacy: .public), not the \(format.rawValue, privacy: .public) shape: \
            the encoder did not crop it. Fallback: re-cropping to \(crop.output, privacy: .public) by export
            """)
        try await MovieFile.replace(url, croppingTo: crop, track: track)
        Logger.recording.notice("Fallback re-crop finished; the take is now \(crop.output, privacy: .public)")
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
                let format = videoFormat
                recordingFormat = format
                let existing = try RecordingFolder.prepare()
                let name = RecordingNaming.uniqueFileName(
                    RecordingNaming.fileName(scriptTitle: scriptTitle, date: .now, format: format),
                    existing: existing
                )
                let crop = try await gateway.startRecording(to: RecordingFolder.url.appending(path: name), format: format)
                Self.logStart(of: crop)
                Self.logEdgeLight(effectsGateway.snapshot.edgeLight)
                if !wantsRecording {
                    await gateway.stopRecording()
                }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                endRecording()
            }
        }
    }

    private static func logStart(of crop: VideoCrop) {
        let format = crop.format.rawValue
        if !crop.needsCrop, crop.format == .vertical {
            Logger.recording.notice("vertical take: native \(crop.source, privacy: .public) format; no crop")
        } else if crop.needsCrop {
            Logger.recording.notice("""
                \(format, privacy: .public) take: camera \(crop.source, privacy: .public), \
                encoder asked for \(crop.output, privacy: .public) with aspect fill
                """)
        } else {
            Logger.recording.notice(
                "\(format, privacy: .public) take: camera \(crop.source, privacy: .public) already has the shape; no crop"
            )
        }
    }

    /// Edge Light changes how a take looks but leaves no mark in the file,
    /// so this log line is the only record of whether it was on. Below
    /// macOS 26.2 every value reads false.
    private static func logEdgeLight(_ reading: EffectReading) {
        Logger.recording.notice("""
            Edge Light at take start: enabled \(reading.isEnabled, privacy: .public), \
            active \(reading.isActive, privacy: .public), \
            format supported \(reading.isSupported, privacy: .public)
            """)
    }

    func stopRecording() {
        wantsRecording = false
        let gateway = gateway
        Task { await gateway.stopRecording() }
    }
}
