import AVFoundation
import CoreAudioKit
import NotchPrompterKit

enum AudioUnitLoadError: LocalizedError {
    case notInstalled(String)
    case unreadableSettings(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            "\(name) is not installed."
        case .unreadableSettings(let name):
            "The saved settings for \(name) cannot be read."
        }
    }
}

/// The installed Audio Units, loaded into the app's own process.
///
/// Out of process, the installed plug-ins showed the app neither their
/// windows nor their parameters, so on 2026-10-12 Stacey chose to load them
/// in process, like other hosts. That needs the
/// `com.apple.security.cs.disable-library-validation` entitlement, because
/// the hardened runtime otherwise refuses code signed by other developers.
/// A plug-in that crashes now ends the app; the launch sweep in
/// ``TakeVoiceCleanUp/recoverInterrupted(in:)`` puts an interrupted take back.
enum AudioUnits {

    /// Every installed Audio Unit. The Kit decides which ones the chain offers.
    static func installed() -> [AudioUnitComponent] {
        AVAudioUnitComponentManager.shared()
            .components(matching: AudioComponentDescription())
            .map { component in
                let description = component.audioComponentDescription
                return AudioUnitComponent(
                    type: description.componentType,
                    subtype: description.componentSubType,
                    manufacturer: description.componentManufacturer,
                    name: component.name,
                    manufacturerName: component.manufacturerName
                )
            }
    }

    /// Loads `component` in process and gives it `state`, the settings saved
    /// from it before, if any.
    static func load(_ component: AudioUnitComponent, state: Data? = nil) async throws -> sending AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: component.type,
            componentSubType: component.subtype,
            componentManufacturer: component.manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard !AVAudioUnitComponentManager.shared().components(matching: description).isEmpty else {
            throw AudioUnitLoadError.notInstalled(component.name)
        }
        let unit = try await AVAudioUnit.instantiate(with: description, options: .loadInProcess)
        if let state {
            guard let settings = settings(from: state) else {
                throw AudioUnitLoadError.unreadableSettings(component.name)
            }
            unit.auAudioUnit.fullState = settings
        }
        return unit
    }

    /// The plug-in's settings interface: its own view, or the generic
    /// CoreAudioKit view of its parameters when it has none.
    ///
    /// The plug-in's render resources are allocated first. Some plug-ins,
    /// such as iZotope RX, crash when their view goes into a window before
    /// that. Release them with `deallocateRenderResources()` when the window
    /// closes.
    @MainActor
    static func settingsController(for unit: AVAudioUnit) async throws -> NSViewController {
        try unit.auAudioUnit.allocateRenderResources()
        if let controller = await viewController(for: unit) {
            return controller
        }
        let generic = NSViewController()
        generic.view = AUGenericView(audioUnit: unit.audioUnit)
        return generic
    }

    /// The plug-in's own view, or `nil` when it has none.
    @MainActor
    static func viewController(for unit: AVAudioUnit) async -> NSViewController? {
        let audioUnit = unit.auAudioUnit
        return await withCheckedContinuation { continuation in
            // Called on a queue of the framework's choosing; the controller
            // is only handed on to the main actor here.
            audioUnit.requestViewController { controller in
                continuation.resume(returning: controller)
            }
        }
    }

    /// The plug-in's current settings, as a binary property list.
    static func state(of unit: AVAudioUnit) -> Data? {
        guard let settings = unit.auAudioUnit.fullState else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
    }

    private static func settings(from state: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: state, format: nil) as? [String: Any]
    }
}
