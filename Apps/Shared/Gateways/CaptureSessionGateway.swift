import AVFoundation
import NotchPrompterKit

enum CaptureError: LocalizedError {
    case deviceUnavailable
    case cannotAddInput(String)
    case noCamera

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The selected device is no longer connected."
        case .cannotAddInput(let name): "\(name) cannot be used right now. Another app may be using it."
        case .noCamera: "There is no camera to record from."
        }
    }
}

/// The camera format a configuration settled on, for the log.
struct CameraFormatSwitch: Sendable {
    let videoFormat: VideoFormat
    /// The format the camera was in before the switch. The name is kept for
    /// the log's existing callers; it is not necessarily the preset's choice.
    let presetSize: PixelSize
    /// The format the camera was asked for. On the crop path, where the app
    /// asks for nothing, it is the format the camera runs in.
    let requestedSize: PixelSize
    /// The format the camera runs in now, read after the configuration commits.
    let size: PixelSize
    /// Whether the camera was asked for a format with the take's shape.
    /// False is the crop path: the camera has no such format, the app holds
    /// no lock, and the session preset chooses the format.
    let isNative: Bool
    /// Whether the camera is in the format it was asked for. False means
    /// something changed it back between setting it and the commit.
    let isRequestedFormat: Bool
}

/// How a recording ended.
struct RecordingOutcome: Sendable {
    let url: URL
    /// `nil` when the movie file is complete and playable.
    let failure: String?
}

/// Owns the `AVCaptureSession`.
///
/// `AVCaptureSession` is not `Sendable`, and starting it blocks. Every call
/// that touches the session or its inputs runs on one private serial queue,
/// which is the confinement that makes `@unchecked Sendable` honest here.
/// The preview layer reads `session` from the main thread, which
/// AVFoundation supports.
final class CaptureSessionGateway: NSObject, @unchecked Sendable {

    let session = AVCaptureSession()
    /// One element per finished recording, successful or not.
    let recordingOutcomes: AsyncStream<RecordingOutcome>

    private let queue = DispatchQueue(label: "com.mojility.notch-prompter.capture")
    private let outcomeContinuation: AsyncStream<RecordingOutcome>.Continuation
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isRecordingRequested = false
    /// The video connection whose encoder settings were changed for a crop,
    /// so the next uncropped take can put them back.
    private var croppedConnection: AVCaptureConnection?
    /// The take shape the camera's format was last chosen for. A change of
    /// camera chooses again.
    private var appliedVideoFormat: VideoFormat?
    /// The camera whose configuration lock this gateway holds. On macOS the
    /// session stays on `.high` (there is no `.inputPriority` preset), and
    /// that preset may change its inputs' formats as it likes. Holding the
    /// lock is what keeps the app's chosen format in place. It is held while
    /// either shape uses a native format, released on the crop path, and
    /// released before the camera leaves the session. The session runs until the app quits, and process exit
    /// releases the lock then.
    private var lockedCamera: AVCaptureDevice?

    override init() {
        (recordingOutcomes, outcomeContinuation) = AsyncStream.makeStream()
        super.init()
    }

    /// Uses the given devices (by `uniqueID`, `nil` for none), puts the
    /// camera in the format for `videoFormat`, and keeps the session running.
    ///
    /// Returns the camera format it chose, or `nil` when the camera and the
    /// take shape are unchanged (or there is no camera), so nothing was chosen.
    func use(videoDeviceID: String?, audioDeviceID: String?, videoFormat: VideoFormat) async throws -> CameraFormatSwitch? {
        let formatSwitch = try await onQueue { () -> CameraFormatSwitch? in
            let cameraChanged = try self.configureInputs(videoDeviceID: videoDeviceID, audioDeviceID: audioDeviceID)
            guard cameraChanged || videoFormat != self.appliedVideoFormat else { return nil }
            return try self.applyCameraFormat(for: videoFormat)
        }
        try await onQueue {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        return formatSwitch
    }

    /// Starts writing a QuickTime movie of the current inputs to `url`, in
    /// the shape of `format`, and returns the crop it asked the encoder for.
    /// The result arrives on ``recordingOutcomes``.
    func startRecording(to url: URL, format: VideoFormat) async throws -> VideoCrop {
        try await onQueue {
            guard let device = self.videoInput?.device, let connection = self.movieOutput.connection(with: .video) else {
                throw CaptureError.noCamera
            }
            let crop = VideoCrop(source: device.activeFormat.pixelSize, format: format)
            self.applyEncoderSettings(for: crop, on: connection)
            self.applyAudioSettings()
            self.isRecordingRequested = true
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            return crop
        }
    }

    /// Stops the recording, if one was started. Safe to call more than once.
    func stopRecording() async {
        try? await onQueue {
            guard self.isRecordingRequested else { return }
            self.isRecordingRequested = false
            self.movieOutput.stopRecording()
        }
    }

    /// Runs `work` on the session queue. Only call from outside that queue.
    func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Has the encoder write the crop's size, cut from the centre of the
    /// camera's frame. Must run on `queue`.
    ///
    /// On macOS the movie output's video settings may carry a size and a
    /// scaling mode; aspect fill scales the frame to cover that size and cuts
    /// the overflow equally from both sides. When no crop is needed, the
    /// connection keeps the session preset's own settings, as it always has.
    private func applyEncoderSettings(for crop: VideoCrop, on connection: AVCaptureConnection) {
        if croppedConnection === connection {
            // nil puts back the settings the session preset chooses.
            movieOutput.setOutputSettings(nil, for: connection)
            croppedConnection = nil
        }
        guard crop.needsCrop else { return }
        let presetCodec = movieOutput.outputSettings(for: connection)[AVVideoCodecKey] as? String
        movieOutput.setOutputSettings([
            AVVideoCodecKey: presetCodec ?? AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey: crop.output.width,
            AVVideoHeightKey: crop.output.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ], for: connection)
        croppedConnection = connection
    }

    /// Records the voice at 48 kHz, the rate video tools expect. The session
    /// preset alone writes 24 kHz AAC. Every other choice the preset makes,
    /// such as the format and the channel count, stays as it is. Must run on
    /// `queue`.
    private func applyAudioSettings() {
        guard let connection = movieOutput.connection(with: .audio) else { return }
        var settings = movieOutput.outputSettings(for: connection)
        settings[AVSampleRateKey] = Self.audioSampleRate
        movieOutput.setOutputSettings(settings, for: connection)
    }

    private static let audioSampleRate = 48_000.0

    /// Puts the devices into the session. Returns whether the camera input
    /// changed. Must run on `queue`.
    private func configureInputs(videoDeviceID: String?, audioDeviceID: String?) throws -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let previousVideoInput = videoInput
        videoInput = try replacing(videoInput, with: videoDeviceID)
        audioInput = try replacing(audioInput, with: audioDeviceID)
        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        return videoInput !== previousVideoInput
    }

    /// Puts the camera in the format for `videoFormat`. Must run on `queue`.
    ///
    /// On macOS the app cannot know which format the `.high` preset will
    /// choose, and the camera may still be in a format set earlier, even by
    /// a previous run. So the app chooses the format itself for both shapes,
    /// with `NativeFormat`. When it finds one, the camera switches to it
    /// inside one configuration block and keeps its configuration lock, so
    /// the preset cannot take it back. When it finds none (the crop path),
    /// the lock is released and the preset chooses.
    private func applyCameraFormat(for videoFormat: VideoFormat) throws -> CameraFormatSwitch? {
        guard let device = videoInput?.device else {
            appliedVideoFormat = videoFormat
            return nil
        }
        let before = device.activeFormat
        let formats = device.formats
        guard let native = NativeFormat.index(for: videoFormat, in: formats.map(CameraFormat.init)) else {
            releaseCameraLock()
            appliedVideoFormat = videoFormat
            let current = device.activeFormat
            return CameraFormatSwitch(
                videoFormat: videoFormat,
                presetSize: before.pixelSize,
                requestedSize: current.pixelSize,
                size: current.pixelSize,
                isNative: false,
                isRequestedFormat: true
            )
        }
        let requested = formats[native]

        session.beginConfiguration()
        do {
            if lockedCamera !== device {
                try device.lockForConfiguration()
                lockedCamera = device
            }
        } catch {
            session.commitConfiguration()
            throw error
        }
        device.activeFormat = requested
        session.commitConfiguration()

        appliedVideoFormat = videoFormat
        let current = device.activeFormat
        return CameraFormatSwitch(
            videoFormat: videoFormat,
            presetSize: before.pixelSize,
            requestedSize: requested.pixelSize,
            size: current.pixelSize,
            isNative: true,
            isRequestedFormat: current == requested
        )
    }

    /// Releases the camera's configuration lock, if this gateway holds one.
    /// Must run on `queue`.
    private func releaseCameraLock() {
        lockedCamera?.unlockForConfiguration()
        lockedCamera = nil
    }

    /// Swaps one input for another. Must run on `queue`, inside a configuration block.
    private func replacing(_ current: AVCaptureDeviceInput?, with deviceID: String?) throws -> AVCaptureDeviceInput? {
        if let current, current.device.uniqueID == deviceID {
            return current
        }
        if let current {
            // Never leave a camera locked once it is out of the session.
            if current.device === lockedCamera {
                releaseCameraLock()
            }
            session.removeInput(current)
        }
        guard let deviceID else { return nil }
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw CaptureError.deviceUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput(device.localizedName) }
        session.addInput(input)
        return input
    }
}

extension CaptureSessionGateway: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        // AVFoundation reports some complete recordings (a size or duration
        // limit reached) with an error that says the file finished anyway.
        let finished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
        let failure = (error == nil || finished == true) ? nil : error?.localizedDescription
        outcomeContinuation.yield(RecordingOutcome(url: outputFileURL, failure: failure))
    }
}

extension AVCaptureDevice.Format {

    var pixelSize: PixelSize {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return PixelSize(width: Int(dimensions.width), height: Int(dimensions.height))
    }
}

extension CameraFormat {

    /// The format's size, top frame rate, and effect support, for `NativeFormat`.
    init(_ format: AVCaptureDevice.Format) {
        var effects: Set<VideoEffect> = []
        if format.isPortraitEffectSupported { effects.insert(.portrait) }
        if format.isStudioLightSupported { effects.insert(.studioLight) }
        if format.isBackgroundReplacementSupported { effects.insert(.backgroundReplacement) }
        if format.isCenterStageSupported { effects.insert(.centerStage) }
        if #available(macOS 26.2, *), format.isEdgeLightSupported { effects.insert(.edgeLight) }
        self.init(
            size: format.pixelSize,
            maxFrameRate: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0,
            supportedEffects: effects
        )
    }
}
