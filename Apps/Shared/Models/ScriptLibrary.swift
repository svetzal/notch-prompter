import Foundation
import NotchPrompterKit
import Observation

/// The scripts folder and the script open in the editor.
///
/// Edits save on their own a moment after typing stops, and before switching
/// scripts or starting a take, so the file on disk is never far behind.
@MainActor
@Observable
final class ScriptLibrary {

    struct Script: Identifiable, Hashable {
        let fileName: String
        var id: String { fileName }
        var title: String { ScriptNaming.title(forFileName: fileName) }
    }

    private(set) var folder: URL
    private(set) var scripts: [Script] = []
    private(set) var selectedFileName: String? {
        didSet { onChange?() }
    }
    private(set) var isDirty = false
    var errorMessage: String?

    /// The editor buffer for the selected script.
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            onChange?()
            guard selectedFileName != nil else { return }
            isDirty = true
            scheduleAutosave()
        }
    }

    /// Called when the text or the selected script changes.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// The prompter content for the editor buffer, including unsaved edits.
    var document: PrompterDocument {
        PrompterDocument(markdown: text)
    }

    var selectedTitle: String? {
        selectedFileName.map(ScriptNaming.title(forFileName:))
    }

    private let store: ScriptStore
    private let defaults: UserDefaults
    private var autosaveTask: Task<Void, Never>?

    private static let folderKey = "scriptsFolder"
    private static let selectionKey = "selectedScript"

    static var defaultFolder: URL {
        URL.documentsDirectory.appending(path: "Notch Prompter/Scripts", directoryHint: .isDirectory)
    }

    init(store: ScriptStore = FileScriptStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.folderKey) {
            folder = URL(filePath: path, directoryHint: .isDirectory)
        } else {
            folder = Self.defaultFolder
        }
        load()
    }

    // MARK: - Folder

    func load() {
        do {
            if try store.prepareFolder(folder) {
                try store.write(SampleScript.markdown, to: folder.appending(path: SampleScript.fileName))
            }
            try refreshList()
            let remembered = defaults.string(forKey: Self.selectionKey)
            let initial = scripts.first { $0.fileName == remembered } ?? scripts.first
            open(initial?.fileName)
        } catch {
            errorMessage = "Could not open the scripts folder: \(error.localizedDescription)"
        }
    }

    func useFolder(_ url: URL) {
        saveNow()
        folder = url
        defaults.set(url.path, forKey: Self.folderKey)
        defaults.removeObject(forKey: Self.selectionKey)
        selectedFileName = nil
        load()
    }

    private func refreshList() throws {
        let names = try store.fileNames(in: folder).filter(ScriptNaming.isScript(fileName:))
        scripts = ScriptNaming.sortedForDisplay(names).map(Script.init(fileName:))
    }

    // MARK: - Selection and editing

    func select(_ fileName: String?) {
        guard fileName != selectedFileName else { return }
        saveNow()
        open(fileName)
    }

    private func open(_ fileName: String?) {
        autosaveTask?.cancel()
        selectedFileName = nil
        guard let fileName else {
            text = ""
            isDirty = false
            return
        }
        do {
            text = try store.read(folder.appending(path: fileName))
            selectedFileName = fileName
            isDirty = false
            defaults.set(fileName, forKey: Self.selectionKey)
        } catch {
            text = ""
            errorMessage = "Could not read \(fileName): \(error.localizedDescription)"
        }
    }

    func createScript() {
        saveNow()
        let existing = Set(scripts.map(\.fileName))
        let fileName = ScriptNaming.uniqueFileName(forTitle: ScriptNaming.untitled, existing: existing)
        do {
            try store.write("", to: folder.appending(path: fileName))
            try refreshList()
            open(fileName)
        } catch {
            errorMessage = "Could not create a script: \(error.localizedDescription)"
        }
    }

    func rename(_ fileName: String, to title: String) {
        let others = Set(scripts.map(\.fileName)).subtracting([fileName])
        let newName = ScriptNaming.uniqueFileName(forTitle: title, existing: others)
        guard newName != fileName else { return }
        if fileName == selectedFileName {
            saveNow()
        }
        do {
            try store.move(folder.appending(path: fileName), to: folder.appending(path: newName))
            try refreshList()
            if fileName == selectedFileName {
                selectedFileName = newName
                defaults.set(newName, forKey: Self.selectionKey)
            }
        } catch {
            errorMessage = "Could not rename \(fileName): \(error.localizedDescription)"
        }
    }

    // MARK: - Saving

    func saveNow() {
        autosaveTask?.cancel()
        guard isDirty, let selectedFileName else { return }
        do {
            try store.write(text, to: folder.appending(path: selectedFileName))
            isDirty = false
        } catch {
            errorMessage = "Could not save \(selectedFileName): \(error.localizedDescription)"
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
