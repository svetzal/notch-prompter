import AVFoundation
import NotchPrompterKit

/// Reads and observes the system video effects for one camera, and carries
/// out the two controls Apple allows: Center Stage and reactions.
///
/// Portrait, Studio Light, background replacement, and Edge Light are
/// read-only class properties. Do not try to set them; send people to the
/// Video Effects panel instead. Edge Light (macOS 26.2 and later) is drawn by
/// the system on a display, so its enabled and active state are class-wide.
/// Below macOS 26.2 it reads as unsupported. Center Stage runs in `.cooperative` mode so Control Center
/// keeps working. Never switch it to `.app`, which would grey out the
/// user's own control.
@MainActor
final class EffectsGateway {

    var onChange: (@MainActor () -> Void)?

    private var device: AVCaptureDevice?
    private var deviceObservations: [NSKeyValueObservation] = []
    private var classObserver: ClassKeyObserver?

    init() {
        if AVCaptureDevice.centerStageControlMode != .cooperative {
            AVCaptureDevice.centerStageControlMode = .cooperative
        }
        var classKeys = [
            "centerStageEnabled", "centerStageControlMode", "portraitEffectEnabled",
            "studioLightEnabled", "backgroundReplacementEnabled", "reactionEffectsEnabled"
        ]
        if #available(macOS 26.2, *) {
            classKeys += ["edgeLightEnabled", "edgeLightActive"]
        }
        classObserver = ClassKeyObserver(keyPaths: classKeys) { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
    }

    /// Follows a different camera, or none.
    func follow(deviceID: String?) {
        guard deviceID != device?.uniqueID else { return }
        deviceObservations = []
        device = deviceID.flatMap(AVCaptureDevice.init(uniqueID:))
        if let device {
            let notify: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.onChange?() }
            }
            deviceObservations = [
                device.observe(\.isPortraitEffectActive) { _, _ in notify() },
                device.observe(\.isStudioLightActive) { _, _ in notify() },
                device.observe(\.isBackgroundReplacementActive) { _, _ in notify() },
                device.observe(\.isCenterStageActive) { _, _ in notify() },
                device.observe(\.canPerformReactionEffects) { _, _ in notify() },
                device.observe(\.activeFormat) { _, _ in notify() }
            ]
        }
        onChange?()
    }

    var snapshot: EffectsSnapshot {
        guard let device else { return .noCamera }
        let format = device.activeFormat
        return EffectsSnapshot(
            portrait: EffectReading(
                isSupported: format.isPortraitEffectSupported,
                isEnabled: AVCaptureDevice.isPortraitEffectEnabled,
                isActive: device.isPortraitEffectActive
            ),
            studioLight: EffectReading(
                isSupported: format.isStudioLightSupported,
                isEnabled: AVCaptureDevice.isStudioLightEnabled,
                isActive: device.isStudioLightActive
            ),
            backgroundReplacement: EffectReading(
                isSupported: format.isBackgroundReplacementSupported,
                isEnabled: AVCaptureDevice.isBackgroundReplacementEnabled,
                isActive: device.isBackgroundReplacementActive
            ),
            edgeLight: Self.edgeLight(format: format),
            centerStage: EffectReading(
                isSupported: format.isCenterStageSupported,
                isEnabled: AVCaptureDevice.isCenterStageEnabled,
                isActive: device.isCenterStageActive
            ),
            centerStageControl: Self.control(AVCaptureDevice.centerStageControlMode),
            reactionsEnabled: AVCaptureDevice.reactionEffectsEnabled,
            canPerformReactions: device.canPerformReactionEffects,
            availableReactions: Set(device.availableReactionTypes.map(\.rawValue))
        )
    }

    /// The followed camera's current frame size. It lives here because this
    /// gateway already observes `activeFormat`, and a format change is what
    /// changes both the effects a camera supports and the shape of its frame.
    var formatSize: PixelSize? {
        guard let device else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return PixelSize(width: Int(dimensions.width), height: Int(dimensions.height))
    }

    func setCenterStage(_ enabled: Bool) {
        guard AVCaptureDevice.centerStageControlMode == .cooperative else { return }
        AVCaptureDevice.isCenterStageEnabled = enabled
    }

    func performReaction(_ rawValue: String) {
        let reaction = AVCaptureReactionType(rawValue: rawValue)
        // performEffect(for:) throws an Objective-C exception for a type not in availableReactionTypes.
        guard let device, device.canPerformReactionEffects, device.availableReactionTypes.contains(reaction) else { return }
        device.performEffect(for: reaction)
    }

    func showVideoEffectsPanel() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    static func systemImage(forReaction rawValue: String) -> String {
        AVCaptureReactionType(rawValue: rawValue).systemImageName
    }

    private static func edgeLight(format: AVCaptureDevice.Format) -> EffectReading {
        guard #available(macOS 26.2, *) else { return .unsupported }
        return EffectReading(
            isSupported: format.isEdgeLightSupported,
            isEnabled: AVCaptureDevice.isEdgeLightEnabled,
            isActive: AVCaptureDevice.isEdgeLightActive
        )
    }

    private static func control(_ mode: AVCaptureDevice.CenterStageControlMode) -> EffectsSnapshot.CenterStageControl {
        switch mode {
        case .app: .app
        case .cooperative: .cooperative
        default: .user
        }
    }
}
