import Foundation

/// Which files a voice clean-up reads, writes, and keeps.
///
/// The recorded take is never lost. The first clean-up renames the take to
/// `<name>-original.mov` and writes the processed audio under the take's own
/// name, so the take's name always holds the version to use. Cleaning up
/// again always reads the `-original`, never an earlier result, so processing
/// never stacks.
public struct VoiceCleanUpFiles: Equatable, Sendable {

    public static let originalSuffix = "-original"
    static let workingSuffix = "-cleaning"

    /// One step to finish what an interrupted clean-up left in a takes folder.
    public enum SweepStep: Equatable, Sendable {
        /// The take's name is empty, so the recorded take goes back under it.
        case restoreOriginal(original: String, take: String)
        /// A working file that never replaced its take.
        case removeWorkingFile(String)
    }

    /// What to do with the files after a clean-up fails.
    public enum Recovery: Equatable, Sendable {
        /// The take's name is empty: the recorded take goes back under it.
        case restoreOriginal
        /// The take's name still holds a movie (an earlier result), so both
        /// files stay as they are.
        case keepBoth
    }

    /// The take's file name: where the processed take goes.
    public let take: String
    /// The unprocessed take, beside the take. The clean-up reads this.
    public let original: String
    /// A hidden file the clean-up writes before it replaces the take.
    public let working: String
    /// Whether the take must first be renamed to ``original``: true for its
    /// first clean-up, false when an original is already there.
    public let keepsTakeAsOriginal: Bool

    /// The files for cleaning up `takeName`, with `existing` the names already in its folder.
    public init(takeName: String, existing: Set<String>) {
        take = takeName
        original = Self.originalName(for: takeName)
        working = Self.workingName(for: takeName)
        let taken = Set(existing.map { $0.lowercased() })
        keepsTakeAsOriginal = !taken.contains(original.lowercased())
    }

    /// `name` with `-original` before its extension.
    public static func originalName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(base)\(originalSuffix)" : "\(base)\(originalSuffix).\(ext)"
    }

    /// The hidden file a clean-up of `name` writes before it replaces the take.
    public static func workingName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? ".\(base)\(workingSuffix)" : ".\(base)\(workingSuffix).\(ext)"
    }

    /// The take's name for an `-original` name, or `nil` when `name` is not one.
    public static func takeName(forOriginal name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard base.lowercased().hasSuffix(originalSuffix), base.count > originalSuffix.count else { return nil }
        let take = String(base.dropLast(originalSuffix.count))
        return ext.isEmpty ? take : "\(take).\(ext)"
    }

    /// Whether `name` is a clean-up's hidden working file.
    public static func isWorkingFile(_ name: String) -> Bool {
        name.hasPrefix(".") && (name as NSString).deletingPathExtension.hasSuffix(workingSuffix)
    }

    /// How to leave the files after a failed clean-up, given whether a file
    /// is still under the take's name.
    public func recovery(takeExists: Bool) -> Recovery {
        takeExists ? .keepBoth : .restoreOriginal
    }

    // MARK: - After an interruption

    /// What to do in a takes folder holding `names` after a clean-up was cut
    /// off, for example by a plug-in crash or a power cut.
    ///
    /// A clean-up renames the take to its `-original` before it writes, so
    /// an `-original` without its take means the take was never replaced: it
    /// goes back under the take's name, as after any failed clean-up (see
    /// ``recovery(takeExists:)``). Working files left behind are removed.
    /// Working files come first, then restores, each in name order.
    public static func interruptedCleanUps(in names: Set<String>) -> [SweepStep] {
        let sorted = names.sorted()
        let removals = sorted.filter(isWorkingFile).map(SweepStep.removeWorkingFile)
        let taken = Set(names.map { $0.lowercased() })
        let restores: [SweepStep] = sorted.compactMap { name in
            guard !isWorkingFile(name), let take = takeName(forOriginal: name) else { return nil }
            let files = VoiceCleanUpFiles(takeName: take, existing: names)
            guard files.recovery(takeExists: taken.contains(take.lowercased())) == .restoreOriginal else { return nil }
            return .restoreOriginal(original: name, take: take)
        }
        return removals + restores
    }
}
