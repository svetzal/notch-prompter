import AppKit
import AVFoundation
import NotchPrompterKit
import Observation

/// One plug-in of the chain, loaded so the presenter can change its
/// settings in its own window.
///
/// The plug-in runs out of process like every other. Its own view comes
/// from `requestViewController`. The parameter list is the fallback, for a
/// plug-in whose view cannot be shown out of process: it reads and writes
/// the parameter tree, which a plug-in in another process may only publish
/// a moment after it loads.
@MainActor
@Observable
final class PluginEditor: Identifiable {

    enum Content: String, CaseIterable, Identifiable {
        case pluginView = "Plug-in"
        case parameters = "Parameters"
        var id: Self { self }
    }

    let id: UUID
    let component: AudioUnitComponent
    /// The plug-in's own view, `nil` until it arrives or when it has none.
    private(set) var viewController: NSViewController?
    private(set) var parameters: [PluginParameter] = []
    /// True when the plug-in published no parameters within the wait.
    private(set) var hasNoParameters = false
    var content = Content.parameters

    @ObservationIgnored let unit: AVAudioUnit
    @ObservationIgnored private var observerToken: AUParameterObserverToken?
    @ObservationIgnored private var observedTree: AUParameterTree?
    @ObservationIgnored private var treeWatch: Task<Void, Never>?

    /// How long to wait for a plug-in in another process to publish its parameters.
    private static let parameterWait = Duration.seconds(10)

    init(id: UUID, component: AudioUnitComponent, unit: AVAudioUnit) {
        self.id = id
        self.component = component
        self.unit = unit
    }

    /// The plug-in's settings now, to save in the chain.
    var state: Data? {
        AudioUnits.state(of: unit)
    }

    /// Asks for the plug-in's view, then watches for its parameters.
    func load() async {
        viewController = await AudioUnits.viewController(for: unit)
        content = viewController == nil ? .parameters : .pluginView
        treeWatch = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.parameterWait
            while !Task.isCancelled, ContinuousClock.now < deadline {
                guard let self else { return }
                if self.attachTree() { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.hasNoParameters = !Task.isCancelled
        }
    }

    func setValue(_ value: Float, for address: UInt64) {
        guard let index = parameters.firstIndex(where: { $0.address == address }) else { return }
        parameters[index].value = value
        let clamped = parameters[index].clampedValue
        observedTree?.parameter(withAddress: address)?.setValue(clamped, originator: observerToken)
    }

    /// Stops watching the plug-in, before its window goes away.
    func close() {
        treeWatch?.cancel()
        if let observerToken {
            observedTree?.removeParameterObserver(observerToken)
        }
        observerToken = nil
        observedTree = nil
    }

    /// Reads the parameter tree once the plug-in has one with parameters,
    /// and follows its changes. False while there is nothing to read yet.
    private func attachTree() -> Bool {
        guard let tree = unit.auAudioUnit.parameterTree, !tree.allParameters.isEmpty else { return false }
        observedTree = tree
        parameters = tree.allParameters.map(Self.parameter)
        observerToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            Task { @MainActor in
                guard let self, let index = self.parameters.firstIndex(where: { $0.address == address }) else { return }
                self.parameters[index].value = value
            }
        })
        return true
    }

    private static func parameter(_ parameter: AUParameter) -> PluginParameter {
        PluginParameter(
            address: parameter.address,
            name: parameter.displayName,
            minValue: parameter.minValue,
            maxValue: parameter.maxValue,
            value: parameter.value,
            unit: parameter.unit.rawValue,
            unitName: parameter.unitName,
            valueStrings: parameter.valueStrings,
            isWritable: parameter.flags.contains(.flag_IsWritable)
        )
    }
}
