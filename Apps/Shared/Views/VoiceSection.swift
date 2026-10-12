import SwiftUI

/// The voice clean-up chain: whether it runs on each take, what is in it,
/// and the button that opens it.
struct VoiceSection: View {

    let voice: VoiceModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            Toggle("Clean up each take", isOn: Binding(get: { voice.chain.isEnabled }, set: { voice.setEnabled($0) }))
            LabeledContent("Chain") {
                Text(voice.chain.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let take = voice.takeBeingCleaned {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Cleaning up \(take.lastPathComponent)…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }
            Button("Edit Chain…") { openWindow(id: VoiceChainEditor.windowID) }
        } header: {
            Text("Voice")
        } footer: {
            Text("After each take, its audio goes through the chain of Audio Unit plug-ins. The take keeps its name, "
                + "and the take as recorded is kept beside it, ending in -original.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
