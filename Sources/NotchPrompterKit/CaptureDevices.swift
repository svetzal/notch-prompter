/// A camera or microphone, described without AVFoundation types.
public struct CaptureDeviceInfo: Identifiable, Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        case builtInCamera
        /// An iPhone used as a webcam.
        case continuityCamera
        case externalCamera
        case microphone
    }

    /// `AVCaptureDevice.uniqueID`, stable across connections.
    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// Built-in first, then Continuity Camera, then other external devices,
    /// each group by name.
    public static func sortedForDisplay(_ devices: [CaptureDeviceInfo]) -> [CaptureDeviceInfo] {
        devices.sorted { lhs, rhs in
            if lhs.kind.order != rhs.kind.order {
                return lhs.kind.order < rhs.kind.order
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension CaptureDeviceInfo.Kind {
    var order: Int {
        switch self {
        case .builtInCamera: 0
        case .continuityCamera: 1
        case .externalCamera: 2
        case .microphone: 3
        }
    }
}

/// Camera and microphone permission, and what to tell the person about it.
public struct CaptureAccess: Equatable, Sendable {

    public enum Status: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        /// Blocked by a device management profile or parental controls.
        case restricted
    }

    public enum Medium: Equatable, Sendable {
        case camera
        case microphone
    }

    /// Something the window should say about permission, with a way to fix it if there is one.
    public struct Notice: Equatable, Sendable {
        public let medium: Medium
        public let title: String
        public let detail: String
        /// Whether System Settings can change it. Restricted access cannot be changed there.
        public let canOpenSettings: Bool
    }

    public var camera: Status
    public var microphone: Status

    public init(camera: Status, microphone: Status) {
        self.camera = camera
        self.microphone = microphone
    }

    /// Whether to ask before starting the camera.
    public var needsRequest: Bool {
        camera == .notDetermined || microphone == .notDetermined
    }

    public var canUseCamera: Bool {
        camera == .authorized
    }

    public var canUseMicrophone: Bool {
        microphone == .authorized
    }

    public var notices: [Notice] {
        [notice(for: .camera, status: camera), notice(for: .microphone, status: microphone)].compactMap { $0 }
    }

    private func notice(for medium: Medium, status: Status) -> Notice? {
        let (title, consequence) = switch medium {
        case .camera: ("Camera access is off", "Notch Prompter cannot show or record your camera.")
        case .microphone: ("Microphone access is off", "Takes will record without sound.")
        }
        switch status {
        case .authorized, .notDetermined:
            return nil
        case .denied:
            return Notice(
                medium: medium,
                title: title,
                detail: "\(consequence) Turn on access for Notch Prompter in Privacy & Security.",
                canOpenSettings: true
            )
        case .restricted:
            return Notice(
                medium: medium,
                title: title,
                detail: "\(consequence) Access is restricted on this Mac, so only its administrator can allow it.",
                canOpenSettings: false
            )
        }
    }
}
