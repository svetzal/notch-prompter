import Foundation
import NotchPrompterKit

/// Keeps the voice chain in `~/Library/Application Support/Notch Prompter/voice-chain.json`.
///
/// A file, not `UserDefaults`, because each plug-in's saved settings can run
/// to many kilobytes.
struct VoiceChainStore {

    var url = URL.applicationSupportDirectory.appending(path: "Notch Prompter/voice-chain.json")

    /// The saved chain, or `nil` when none has been saved yet.
    func load() throws -> VoiceChain? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(VoiceChain.self, from: Data(contentsOf: url))
    }

    func save(_ chain: VoiceChain) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(chain).write(to: url, options: .atomic)
    }
}
