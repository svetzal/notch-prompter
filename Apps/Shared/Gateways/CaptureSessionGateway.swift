import AVFoundation

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

    /// Starts writing a QuickTime movie of the current inputs to `url`.
    /// The result arrives on ``recordingOutcomes``.
    func startRecording(to url: URL) async throws {
        try await onQueue {
            guard self.videoInput != nil, self.movieOutput.connection(with: .video) != nil else {
                throw CaptureError.noCamera
            }
            self.isRecordingRequested = true
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
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
