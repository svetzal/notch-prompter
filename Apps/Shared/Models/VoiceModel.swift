import Foundation
import NotchPrompterKit
import Observation
import os

/// The voice clean-up chain, and the clean-up of each take.
///
/// After a take is saved, its audio runs through the chain and the result
/// takes the take's name; the recorded take stays beside it as
/// `<name>-original.mov`. ``TakeVoiceCleanUp`` does the file work, from
/// the Kit's ``VoiceCleanUpFiles``, so a take is never lost.
@MainActor
@Observable
final class VoiceModel {

    private(set) var chain: VoiceChain {
        didSet { save() }
    }
    /// The take whose voice is being cleaned up, if one is.
    private(set) var takeBeingCleaned: URL?
    var errorMessage: String?

    @ObservationIgnored private let store: VoiceChainStore

    init(store: VoiceChainStore = VoiceChainStore()) {
        self.store = store
        do {
            chain = try store.load() ?? VoiceChain()
        } catch {
            Logger.recording.error("Voice chain could not be read: \(error.localizedDescription, privacy: .public)")
            chain = VoiceChain()
        }
    }

    var isCleaningUp: Bool {
        takeBeingCleaned != nil
    }

    /// Runs `take` through the chain's active plug-ins, reading its
    /// `-original` if it has one. Afterwards the take's name holds the
    /// processed take or, if the clean-up failed, the recorded take.
    func cleanUp(take: URL) async {
        guard !isCleaningUp else { return }
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
