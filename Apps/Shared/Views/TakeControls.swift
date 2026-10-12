import AppKit
import NotchPrompterKit
import SwiftUI

/// Record and stop, the recording indicator, and the last take.
struct TakeControls: View {

    let prompter: PrompterController
    let capture: CaptureModel

    var body: some View {
        Section {
            if prompter.session.isRecording {
                recordingIndicator
            } else {
                Button {
                    prompter.record()
                } label: {
                    Label("Record Take", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!prompter.session.canBegin || !capture.access.canUseCamera)
            }
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
            }
        } header: {
            Text("Take")
        } footer: {
            Text("A take counts down, then starts the prompter and the recording together. "
                + "Esc stops both. Takes are saved in Movies/Notch Prompter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingIndicator: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(statusText(at: context.date))
                    .monospacedDigit()
                Spacer()
                Button("Stop") { prompter.stop() }
                    .disabled(prompter.session.phase == .finishing)
            }
        }
    }

    private func statusText(at date: Date) -> String {
        if prompter.session.phase == .finishing {
            return "Saving…"
        }
        return "Recording \(ElapsedTime.format(prompter.session.elapsed(at: date) ?? 0))"
    }
}
