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

    override init() {
        (recordingOutcomes, outcomeContinuation) = AsyncStream.makeStream()
        super.init()
    }

    /// Uses the given devices (by `uniqueID`, `nil` for none) and keeps the session running.
    func use(videoDeviceID: String?, audioDeviceID: String?) async throws {
        try await onQueue {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }
            self.videoInput = try self.replacing(self.videoInput, with: videoDeviceID)
            self.audioInput = try self.replacing(self.audioInput, with: audioDeviceID)
            if !self.session.outputs.contains(self.movieOutput), self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
        }
        try await onQueue {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// Starts writing a QuickTime movie of the current inputs to `url`, in
    /// the shape of `format`, and returns the crop it asked the encoder for.
    /// The result arrives on ``recordingOutcomes``.
    func startRecording(to url: URL, format: VideoFormat) async throws -> VideoCrop {
        try await onQueue {
            guard let device = self.videoInput?.device, let connection = self.movieOutput.connection(with: .video) else {
                throw CaptureError.noCamera
            }
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let crop = VideoCrop(
                source: PixelSize(width: Int(dimensions.width), height: Int(dimensions.height)),
                format: format
            )
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

    func stop() async {
        try? await onQueue {
            self.session.stopRunning()
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

    /// Swaps one input for another. Must run on `queue`, inside a configuration block.
    private func replacing(_ current: AVCaptureDeviceInput?, with deviceID: String?) throws -> AVCaptureDeviceInput? {
        if let current, current.device.uniqueID == deviceID {
            return current
        }
        if let current {
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
