import Foundation

/// File-system access for the scripts folder.
///
/// A thin gateway over `FileManager`. Naming, filtering, and collision rules
/// live in `ScriptNaming` in the Kit, so nothing here needs a test of its own.
protocol ScriptStore: Sendable {
    /// Creates the folder if needed. Returns `true` when it did not exist before.
    func prepareFolder(_ folder: URL) throws -> Bool
    func fileNames(in folder: URL) throws -> [String]
    func read(_ url: URL) throws -> String
    func write(_ text: String, to url: URL) throws
    func move(_ source: URL, to destination: URL) throws
}

struct FileScriptStore: ScriptStore {

    func prepareFolder(_ folder: URL) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return false }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return true
    }

    func fileNames(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
