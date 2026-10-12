import AppKit
import SwiftUI

/// Where takes go, a link to the last one, and its voice clean-up. Record
/// and Stop are in the toolbar.
struct LastTakeSection: View {

    let capture: CaptureModel
    let voice: VoiceModel
    /// A recorded take is under way or finishing, so its files are busy.
    let isTakeBusy: Bool

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
                cleanUpControls(for: lastRecording)
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

    @ViewBuilder
    private func cleanUpControls(for take: URL) -> some View {
        let original = voice.original(of: take)
        HStack {
            Button(original == nil ? "Clean Up Voice" : "Clean Up Again") {
                Task { await voice.cleanUp(take: take) }
            }
            .disabled(!voice.canCleanUpByHand || isTakeBusy)
            .help("Run the take as recorded through the voice chain, replacing any earlier clean-up")
            if let original {
                Button("Reveal Both") {
                    NSWorkspace.shared.activateFileViewerSelecting([take, original])
                }
                .help("Show the cleaned-up take and the take as recorded in Finder")
            }
        }
    }
}
