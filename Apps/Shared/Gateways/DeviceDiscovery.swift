import AVFoundation
import NotchPrompterKit

/// Lists cameras and microphones and reports when they come and go.
///
/// Continuity Camera iPhones appear as `.continuityCamera` devices because
/// the Info.plist sets `NSCameraUseContinuityCameraDeviceType`.
@MainActor
final class DeviceDiscovery {

    var onChange: (@MainActor () -> Void)?

    private let cameraDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
        mediaType: .video,
        position: .unspecified
    )
    private let microphoneDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )
    private var tokens: [NSObjectProtocol] = []
    private var preferredCameraObserver: ClassKeyObserver?

    init() {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
        preferredCameraObserver = ClassKeyObserver(keyPaths: ["systemPreferredCamera"]) { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
    }

    var cameras: [CaptureDeviceInfo] {
        CaptureDeviceInfo.sortedForDisplay(cameraDiscovery.devices.map { device in
            let kind: CaptureDeviceInfo.Kind = switch device.deviceType {
            case .continuityCamera: .continuityCamera
            case .builtInWideAngleCamera where device.isContinuityCamera: .continuityCamera
            case .builtInWideAngleCamera: .builtInCamera
            default: .externalCamera
            }
            return CaptureDeviceInfo(id: device.uniqueID, name: device.localizedName, kind: kind)
        })
    }

    var microphones: [CaptureDeviceInfo] {
        CaptureDeviceInfo.sortedForDisplay(microphoneDiscovery.devices.map { device in
            CaptureDeviceInfo(id: device.uniqueID, name: device.localizedName, kind: .microphone)
        })
    }

    /// The camera macOS would pick: the user's choice in other apps, or a nearby iPhone.
    var systemPreferredCameraID: String? {
        AVCaptureDevice.systemPreferredCamera?.uniqueID
    }

    var defaultMicrophoneID: String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }
}

/// Key-value observes class properties of `AVCaptureDevice`.
///
/// Several effect switches (`centerStageEnabled`, `portraitEffectEnabled`,
/// and others) are class properties, which the block-based KVO API cannot
/// observe. This registers on the class object itself, as Apple's
/// Continuity Camera sample does.
final class ClassKeyObserver: NSObject, @unchecked Sendable {

    private let keyPaths: [String]
    private let handler: @Sendable () -> Void

    init(keyPaths: [String], handler: @escaping @Sendable () -> Void) {
        self.keyPaths = keyPaths
        self.handler = handler
        super.init()
        for keyPath in keyPaths {
            AVCaptureDevice.self.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
        }
    }

    deinit {
        for keyPath in keyPaths {
            AVCaptureDevice.self.removeObserver(self, forKeyPath: keyPath)
        }
    }

    // Block-based KVO needs an instance key path; these are class properties.
    // swiftlint:disable:next block_based_kvo
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        handler()
    }
}
