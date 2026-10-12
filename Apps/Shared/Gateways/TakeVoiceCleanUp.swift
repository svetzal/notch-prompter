import Foundation
import NotchPrompterKit

/// Cleans up a take's voice in place, never losing the recorded take.
///
/// The Kit's ``VoiceCleanUpFiles`` decides the names. The first clean-up
/// renames the take to its `-original` name; every clean-up reads the
/// `-original` and writes the result under the take's own name. If anything
/// fails, the take's name gets the recorded take back, unless it still holds
/// an earlier result, and both files stay.
enum TakeVoiceCleanUp {

    struct Result: Sendable {
        /// The processed take, under the take's own name.
        let take: URL
        /// The recorded take, unprocessed.
        let original: URL
        let report: VoiceProcessingReport
    }

    /// The `-original` beside `take`, if there is one.
    static func original(of take: URL) -> URL? {
        let url = take.deletingLastPathComponent().appending(path: VoiceCleanUpFiles.originalName(for: take.lastPathComponent))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func run(take: URL, through entries: [VoiceChain.Entry]) async throws -> Result {
        let fileManager = FileManager.default
        let folder = take.deletingLastPathComponent()
        let files = VoiceCleanUpFiles(
            takeName: take.lastPathComponent,
            existing: Set(try fileManager.contentsOfDirectory(atPath: folder.path))
        )
        let original = folder.appending(path: files.original)
        let working = folder.appending(path: files.working)
        try? fileManager.removeItem(at: working)
        if files.keepsTakeAsOriginal {
            try fileManager.moveItem(at: take, to: original)
        }
        do {
            let report = try await VoiceProcessor.process(original, into: working, through: entries)
            if fileManager.fileExists(atPath: take.path) {
                _ = try fileManager.replaceItemAt(take, withItemAt: working)
            } else {
                try fileManager.moveItem(at: working, to: take)
            }
            return Result(take: take, original: original, report: report)
        } catch {
            try? fileManager.removeItem(at: working)
            if files.recovery(takeExists: fileManager.fileExists(atPath: take.path)) == .restoreOriginal {
                try? fileManager.moveItem(at: original, to: take)
            }
            throw error
        }
    }
}
