import NotchPrompterKit
import SwiftUI

/// A plain-text Markdown editor for the selected script.
struct ScriptEditor: View {

    @Bindable var library: ScriptLibrary
    let wordsPerMinute: Double

    var body: some View {
        if library.selectedFileName == nil {
            ContentUnavailableView(
                "No Script",
                systemImage: "text.alignleft",
                description: Text("Choose a script, or create one with ⌘N.")
            )
        } else {
            VStack(spacing: 0) {
                TextEditor(text: $library.text)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                Divider()
                statusBar
            }
        }
    }

    private var statusBar: some View {
        let document = library.document
        let duration = document.estimatedReadingTime(wordsPerMinute: wordsPerMinute)
        return HStack {
            Text("\(document.spokenWordCount) words")
            Text("about \(ElapsedTime.format(duration)) at \(Int(wordsPerMinute)) wpm")
            Spacer()
            Text(library.isDirty ? "Edited" : "Saved")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
