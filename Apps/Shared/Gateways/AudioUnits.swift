import AVFoundation
import NotchPrompterKit

enum AudioUnitLoadError: LocalizedError {
    case notInstalled(String)
    case loadedInProcess(String)
    case unreadableSettings(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            "\(name) is not installed."
        case .loadedInProcess(let name):
            "\(name) cannot run in a separate process, and the app only loads plug-ins that way."
        case .unreadableSettings(let name):
            "The saved settings for \(name) cannot be read."
        }
    }
}

/// The installed Audio Units, loaded out of process.
///
/// Every plug-in runs in a separate system process, never in the app. A
/// plug-in that crashes then cannot take the app or a take down with it,
/// and the app's hardened runtime does not need to load third-party code.
/// A plug-in that will only load in process is refused.
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

    /// Loads `component` in a separate process and gives it `state`, the
    /// settings saved from it before, if any.
    static func load(_ component: AudioUnitComponent, state: Data? = nil) async throws -> AVAudioUnit {
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
        let unit = try await AVAudioUnit.instantiate(with: description, options: .loadOutOfProcess)
        // Out of process is a request that the system may quietly ignore.
        guard !unit.auAudioUnit.isLoadedInProcess else {
            throw AudioUnitLoadError.loadedInProcess(component.name)
        }
        if let state {
            guard let settings = settings(from: state) else {
                throw AudioUnitLoadError.unreadableSettings(component.name)
            }
            unit.auAudioUnit.fullState = settings
        }
        return unit
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
