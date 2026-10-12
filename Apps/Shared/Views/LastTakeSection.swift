import AppKit
import SwiftUI

/// Where takes go, and a link to the last one. Record and Stop are in the toolbar.
struct LastTakeSection: View {

    let capture: CaptureModel

    var body: some View {
        Section {
            if let lastRecording = capture.lastRecording {
                LabeledContent("Last take") {
                    Button(lastRecording.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Show in Finder")
                }
            } else {
                Text("No takes yet").foregroundStyle(.secondary)
            }
        } header: {
            Text("Takes")
        } footer: {
            Text("Record counts down, then starts the prompter and the recording together. "
                + "Esc stops both. Takes are saved in Movies/Notch Prompter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
