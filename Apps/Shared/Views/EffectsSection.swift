import NotchPrompterKit
import SwiftUI

/// Live state of the system video effects, with the controls Apple allows.
struct EffectsSection: View {

    let capture: CaptureModel

    var body: some View {
        Section {
            ForEach(capture.effects.rows) { row in
                LabeledContent(row.effect.title) {
                    control(for: row)
                }
            }
            reactions
            Button("Open Video Effects…") { capture.showVideoEffectsPanel() }
        } header: {
            Text("Video effects")
        } footer: {
            Text(
                "Portrait, Studio Light, and Background can only be changed in the Video Effects panel. "
                    + "Recordings include every effect."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func control(for row: EffectsPresentation.Row) -> some View {
        switch row.control {
        case .toggle(let isOn):
            Toggle(row.status.label, isOn: Binding(get: { isOn }, set: { capture.setCenterStage($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
        case .systemPanel, .none:
            Text(row.status.label)
                .foregroundStyle(row.status == .active ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var reactions: some View {
        if let reason = capture.effects.reactionsUnavailableReason {
            LabeledContent("Reactions") {
                Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        } else {
            LabeledContent("Reactions") {
                HStack(spacing: 4) {
                    ForEach(capture.effects.reactions, id: \.self) { reaction in
                        Button {
                            capture.performReaction(reaction)
                        } label: {
                            Image(systemName: EffectsGateway.systemImage(forReaction: reaction))
                        }
                        .buttonStyle(.borderless)
                        .help(ReactionNames.title(for: reaction))
                    }
                }
            }
        }
    }
}
