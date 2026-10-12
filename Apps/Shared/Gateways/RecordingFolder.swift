import Foundation

/// Where takes are saved: `~/Movies/Notch Prompter/`.
enum RecordingFolder {

    static var url: URL {
        URL.moviesDirectory.appending(path: "Notch Prompter", directoryHint: .isDirectory)
    }

    /// Creates the folder if needed and returns the names already in it.
    static func prepare() throws -> Set<String> {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Set(try FileManager.default.contentsOfDirectory(atPath: url.path))
    }
}
