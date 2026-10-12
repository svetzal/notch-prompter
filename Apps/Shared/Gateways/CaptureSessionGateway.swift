import AVFoundation

enum CaptureError: LocalizedError {
    case deviceUnavailable
    case cannotAddInput(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The selected device is no longer connected."
        case .cannotAddInput(let name): "\(name) cannot be used right now. Another app may be using it."
        }
    }
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
    private let queue = DispatchQueue(label: "com.mojility.notch-prompter.capture")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

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
        }
        try await onQueue {
            if !self.session.isRunning {
                self.session.startRunning()
            }
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
