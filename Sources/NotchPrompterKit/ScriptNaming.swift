import Foundation

/// File naming rules for the scripts folder.
///
/// A script's title is its file name without the extension. Keeping the
/// rules here, apart from the file system, lets the app create and rename
/// scripts without guessing at collisions or illegal characters.
public enum ScriptNaming {

    /// The extension new scripts get.
    public static let fileExtension = "md"

    /// Extensions the library lists as scripts.
    public static let recognizedExtensions: Set<String> = ["md", "markdown"]

    /// The title for a script that has none.
    public static let untitled = "Untitled"

    /// Whether a file in the scripts folder is a script.
    public static func isScript(fileName: String) -> Bool {
        guard !fileName.hasPrefix(".") else { return false }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return recognizedExtensions.contains(ext)
    }

    /// The display title for a script file.
    public static func title(forFileName fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// A title that is safe to use as a file name on macOS.
    ///
    /// Path separators and colons become hyphens, control characters are
    /// dropped, and a leading dot is removed so the file does not hide itself.
    public static func sanitizedTitle(_ title: String) -> String {
        let mapped = title.unicodeScalars.compactMap { scalar -> Character? in
            if scalar == "/" || scalar == ":" { return "-" }
            if CharacterSet.controlCharacters.contains(scalar) { return nil }
            return Character(scalar)
        }
        var clean = String(mapped).trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix(".") {
            clean.removeFirst()
        }
        clean = clean.trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? untitled : clean
    }

    /// A file name for `title` that does not collide with `existing`.
    ///
    /// Collisions are case-insensitive, matching the default macOS file system.
    /// The second "Intro" becomes "Intro 2.md".
    public static func uniqueFileName(forTitle title: String, existing: Set<String>) -> String {
        let base = sanitizedTitle(title)
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(base).\(fileExtension)"
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(counter).\(fileExtension)"
            counter += 1
        }
        return candidate
    }

    /// Sorts script file names for display: by title, ignoring case, in a
    /// human-friendly numeric order ("Take 2" before "Take 10").
    public static func sortedForDisplay(_ fileNames: [String]) -> [String] {
        fileNames.sorted {
            title(forFileName: $0).localizedStandardCompare(title(forFileName: $1)) == .orderedAscending
        }
    }
}
