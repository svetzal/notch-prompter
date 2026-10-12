import NotchPrompterKit
import SwiftUI

/// The voice clean-up chain window: the installed effects on the left, the
/// chain in order on the right.
struct VoiceChainEditor: View {

    static let windowID = "voiceChain"

    let voice: VoiceModel
    @State private var selectedEffect: AudioUnitComponent?

    var body: some View {
        HSplitView {
            installedEffects
                .frame(minWidth: 240, idealWidth: 280)
            chain
                .frame(minWidth: 380)
        }
        .frame(minWidth: 680, minHeight: 400)
        .task {
            voice.refreshInstalledEffects()
            voice.checkLoads()
        }
    }

    // MARK: - Installed effects

    private var installedEffects: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedEffect) {
                ForEach(makers, id: \.self) { maker in
                    Section(maker) {
                        ForEach(voice.installedEffects.filter { $0.manufacturerName == maker }, id: \.self) { effect in
                            Text(effect.name)
                                .help(effect.codes)
                                .tag(Optional(effect))
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: AudioUnitComponent.self) { _ in
            } primaryAction: { effects in
                effects.forEach(voice.add)
            }
            Divider()
            HStack {
                Text("Audio Unit effects on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add to Chain") {
                    if let selectedEffect {
                        voice.add(selectedEffect)
                    }
                }
                .disabled(selectedEffect == nil)
            }
            .padding(10)
        }
    }

    /// Makers in the order the effects are sorted.
    private var makers: [String] {
        var seen = Set<String>()
        return voice.installedEffects.map(\.manufacturerName).filter { seen.insert($0).inserted }
    }

    // MARK: - The chain

    private var chain: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Clean up each take", isOn: Binding(get: { voice.chain.isEnabled }, set: { voice.setEnabled($0) }))
                .toggleStyle(.switch)
                .padding(10)
            Divider()
            if voice.chain.entries.isEmpty {
                Text("Add effects from the list on the left. A take's audio goes through them from top to bottom.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List {
                    ForEach(Array(voice.chain.entries.enumerated()), id: \.element.id) { index, entry in
                        ChainRow(position: index + 1, entry: entry, voice: voice)
                    }
                    .onMove { voice.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            Divider()
            Text(
                "Drag to reorder. Each plug-in runs in its own process, and its settings are saved when you close "
                    + "its window. Takes are cleaned up after they are recorded, never live."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
        }
    }
}

private struct ChainRow: View {

    let position: Int
    let entry: VoiceChain.Entry
    let voice: VoiceModel

    var body: some View {
        let failure = voice.loadFailures[entry.component]
        HStack(alignment: .firstTextBaseline) {
            Text("\(position).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Toggle("Active", isOn: Binding(
                get: { !entry.isBypassed },
                set: { voice.setBypassed(!$0, for: entry.id) }
            ))
            .labelsHidden()
            .help(entry.isBypassed ? "Bypassed: kept in the chain, but does not process" : "Active: processes each take")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.component.name)
                    .foregroundStyle(entry.isBypassed ? .secondary : .primary)
                Text(entry.component.manufacturerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failure {
                    Label("Not loadable: \(failure)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Settings…") {
                Task { await voice.openSettings(for: entry.id) }
            }
            .disabled(failure != nil)
            Button {
                voice.remove(entry.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from the chain")
        }
        .padding(.vertical, 2)
    }
}
