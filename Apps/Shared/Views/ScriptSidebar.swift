import AppKit
import SwiftUI

/// The list of scripts in the scripts folder.
struct ScriptSidebar: View {

    @Bindable var library: ScriptLibrary
    @State private var renaming: ScriptLibrary.Script?
    @State private var newTitle = ""

    var body: some View {
        List(selection: selection) {
            ForEach(library.scripts) { script in
                Text(script.title)
                    .tag(script.fileName)
                    .contextMenu {
                        Button("Rename…") { beginRename(script) }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [library.folder.appending(path: script.fileName)]
                            )
                        }
                    }
            }
        }
        .navigationTitle("Scripts")
        .toolbar {
            ToolbarItem {
                Button("New Script", systemImage: "square.and.pencil") { library.createScript() }
                    .help("New script (⌘N)")
            }
        }
        .safeAreaInset(edge: .bottom) { folderBar }
        .alert("Rename Script", isPresented: isRenaming, presenting: renaming) { script in
            TextField("Title", text: $newTitle)
            Button("Rename") { library.rename(script.fileName, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { library.selectedFileName }, set: { library.select($0) })
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func beginRename(_ script: ScriptLibrary.Script) {
        newTitle = script.title
        renaming = script
    }

    private var folderBar: some View {
        HStack {
            Image(systemName: "folder")
            Text(library.folder.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(library.folder.path)
            Spacer()
            Button("Change…", action: chooseFolder)
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = library.folder
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            library.useFolder(url)
        }
    }
}
