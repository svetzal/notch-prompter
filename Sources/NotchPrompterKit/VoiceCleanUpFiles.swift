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
        let base = (takeName as NSString).deletingPathExtension
        let ext = (takeName as NSString).pathExtension
        working = ext.isEmpty ? ".\(base)-cleaning" : ".\(base)-cleaning.\(ext)"
        let taken = Set(existing.map { $0.lowercased() })
        keepsTakeAsOriginal = !taken.contains(original.lowercased())
    }

    /// `name` with `-original` before its extension.
    public static func originalName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(base)\(originalSuffix)" : "\(base)\(originalSuffix).\(ext)"
    }

    /// How to leave the files after a failed clean-up, given whether a file
    /// is still under the take's name.
    public func recovery(takeExists: Bool) -> Recovery {
        takeExists ? .keepBoth : .restoreOriginal
    }
}
