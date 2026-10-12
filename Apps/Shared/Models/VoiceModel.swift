import AppKit
import NotchPrompterKit
import Observation
import os

/// The voice clean-up chain, its plug-ins' settings windows, and the
/// clean-up of each take.
///
/// After a take is saved, its audio runs through the chain and the result
/// takes the take's name; the recorded take stays beside it as
/// `<name>-original.mov`. ``TakeVoiceCleanUp`` does the file work, from
/// the Kit's ``VoiceCleanUpFiles``, so a take is never lost.
///
/// Every plug-in loads out of process. One that cannot is listed in
/// ``loadFailures`` and shown as not loadable.
@MainActor
@Observable
final class VoiceModel {

    private(set) var chain: VoiceChain {
        didSet { save() }
    }
    /// The take whose voice is being cleaned up, if one is.
    private(set) var takeBeingCleaned: URL?
    /// The effects the chain can use, for the chain window.
    private(set) var installedEffects: [AudioUnitComponent] = []
    /// Plug-ins that could not be loaded out of process, with the reason.
    private(set) var loadFailures: [AudioUnitComponent: String] = [:]
    var errorMessage: String?

    @ObservationIgnored private let store: VoiceChainStore
    @ObservationIgnored private let windows = PluginWindows()
    @ObservationIgnored private var editors: [UUID: PluginEditor] = [:]
    @ObservationIgnored private var opening: Set<UUID> = []
    @ObservationIgnored private var checkedComponents: Set<AudioUnitComponent> = []

    init(store: VoiceChainStore = VoiceChainStore()) {
        self.store = store
        do {
            chain = try store.load() ?? VoiceChain()
        } catch {
            Logger.recording.error("Voice chain could not be read: \(error.localizedDescription, privacy: .public)")
            chain = VoiceChain()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOpenSettings() }
        }
    }

    var isCleaningUp: Bool {
        takeBeingCleaned != nil
    }

    /// Whether a take can be run through the chain by hand: the chain has an
    /// active plug-in, and no clean-up is under way. The chain's switch only
    /// decides whether new takes are cleaned up on their own.
    var canCleanUpByHand: Bool {
        !chain.activeEntries.isEmpty && !isCleaningUp
    }

    /// The unprocessed take kept beside `take`, if there is one.
    func original(of take: URL) -> URL? {
        TakeVoiceCleanUp.original(of: take)
    }

    // MARK: - Editing the chain

    func setEnabled(_ isEnabled: Bool) {
        chain.isEnabled = isEnabled
    }

    func refreshInstalledEffects() {
        installedEffects = AudioUnitComponent.offeredEffects(from: AudioUnits.installed())
    }

    func add(_ component: AudioUnitComponent) {
        chain.add(component)
        checkLoads()
    }

    func remove(_ id: UUID) {
        windows.close(id)
        chain.remove(id)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        chain.move(fromOffsets: source, toOffset: destination)
    }

    func setBypassed(_ isBypassed: Bool, for id: UUID) {
        chain.setBypassed(isBypassed, for: id)
    }

    /// Loads each plug-in in the chain once, out of process, to find any
    /// that cannot run that way.
    func checkLoads() {
        for component in Set(chain.entries.map(\.component)).subtracting(checkedComponents) {
            checkedComponents.insert(component)
            Task {
                do {
                    _ = try await AudioUnits.load(component)
                    loadFailures[component] = nil
                } catch {
                    loadFailures[component] = error.localizedDescription
                    Logger.recording.error("""
                        Plug-in \(component.name, privacy: .public) [\(component.codes, privacy: .public)] \
                        is not loadable out of process: \(error.localizedDescription, privacy: .public)
                        """)
                }
            }
        }
    }

    // MARK: - Plug-in settings windows

    /// Opens the entry's plug-in in its own window, with its saved settings.
    func openSettings(for id: UUID) async {
        guard !windows.bringToFront(id), !opening.contains(id),
              let entry = chain.entries.first(where: { $0.id == id }) else { return }
        opening.insert(id)
        defer { opening.remove(id) }
        do {
            let unit = try await AudioUnits.load(entry.component, state: entry.state)
            let editor = PluginEditor(id: id, component: entry.component, unit: unit)
            await editor.load()
            editors[id] = editor
            windows.show(editor) { [weak self] in self?.editorDidClose(id) }
        } catch {
            loadFailures[entry.component] = error.localizedDescription
            errorMessage = "\(entry.component.name) could not be opened: \(error.localizedDescription)"
        }
    }

    /// Saves the settings of every open plug-in window into the chain.
    func saveOpenSettings() {
        for (id, editor) in editors {
            chain.setState(editor.state, for: id)
        }
    }

    private func editorDidClose(_ id: UUID) {
        guard let editor = editors.removeValue(forKey: id) else { return }
        chain.setState(editor.state, for: id)
        editor.close()
    }

    // MARK: - Cleaning up takes

    /// Runs `take` through the chain's active plug-ins, reading its
    /// `-original` if it has one. Afterwards the take's name holds the
    /// processed take or, if the clean-up failed, the recorded take.
    func cleanUp(take: URL) async {
        guard !isCleaningUp else { return }
        // Settings changed in an open window count, without closing it first.
        saveOpenSettings()
        let entries = chain.activeEntries
        takeBeingCleaned = take
        defer { takeBeingCleaned = nil }
        let name = take.lastPathComponent
        Logger.recording.notice("Voice clean-up of \(name, privacy: .public) started: \(self.chain.summary, privacy: .public)")
        let started = Date.now
        do {
            let result = try await TakeVoiceCleanUp.run(take: take, through: entries)
            Self.log(result, seconds: Date.now.timeIntervalSince(started))
        } catch VoiceProcessorError.noAudio {
            Logger.recording.notice("Voice clean-up of \(name, privacy: .public) skipped: the take has no audio")
        } catch {
            Logger.recording.error("""
                Voice clean-up of \(name, privacy: .public) failed after \
                \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public) s: \
                \(error.localizedDescription, privacy: .public). The recorded take is kept.
                """)
            errorMessage = "The take was saved, but its voice could not be cleaned up: \(error.localizedDescription)"
        }
    }

    private static func log(_ result: TakeVoiceCleanUp.Result, seconds: TimeInterval) {
        let report = result.report
        for plugin in report.plugins {
            Logger.recording.notice("""
                Voice clean-up plug-in \(plugin.name, privacy: .public) [\(plugin.codes, privacy: .public)]: \
                latency \(plugin.latency * 1_000, format: .fixed(precision: 2), privacy: .public) ms
                """)
        }
        let trimmed = Double(report.latencyFrames) / report.sampleRate * 1_000
        Logger.recording.notice("""
            Voice clean-up of \(result.take.lastPathComponent, privacy: .public) finished in \
            \(seconds, format: .fixed(precision: 2), privacy: .public) s: \
            \(report.inputFrames, privacy: .public) frames in, \(report.outputFrames, privacy: .public) frames out, \
            \(report.channelCount, privacy: .public) channel(s) at \(Int(report.sampleRate), privacy: .public) Hz, \
            trimmed \(report.latencyFrames, privacy: .public) frames \
            (\(trimmed, format: .fixed(precision: 2), privacy: .public) ms) of latency; \
            unprocessed take kept as \(result.original.lastPathComponent, privacy: .public)
            """)
    }

    private func save() {
        do {
            try store.save(chain)
        } catch {
            Logger.recording.error("Voice chain could not be saved: \(error.localizedDescription, privacy: .public)")
            errorMessage = "The voice clean-up chain could not be saved: \(error.localizedDescription)"
        }
    }
}
