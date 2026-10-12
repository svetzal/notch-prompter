import NotchPrompterKit
import SwiftUI

/// The main window's toolbar: the prompter and the take, run from one place.
///
/// Leading: show or hide the prompter, and rehearse. Centre: the take's
/// status. Trailing: speed, prompter settings, the system Video Effects
/// panel, and Record, which becomes Stop while a run is under way. People
/// can rearrange it with Customize Toolbar.
struct MainToolbar: CustomizableToolbarContent {

    let model: AppModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "prompter", placement: .navigation) {
            PrompterToggle(prompter: model.prompter)
        }
        ToolbarItem(id: "rehearse", placement: .navigation) {
            RehearseButton(prompter: model.prompter)
        }
        ToolbarItem(id: "status", placement: .principal) {
            TakeStatusView(prompter: model.prompter)
        }
        ToolbarItem(id: "speed", placement: .primaryAction) {
            SpeedControl(prompter: model.prompter)
        }
        ToolbarItem(id: "settings", placement: .primaryAction) {
            PrompterSettingsButton(prompter: model.prompter)
        }
        ToolbarItem(id: "videoEffects", placement: .primaryAction) {
            Button {
                model.capture.showVideoEffectsPanel()
            } label: {
                Label("Video Effects", systemImage: "camera.filters")
            }
            .help("Open the system Video Effects panel: Portrait, Studio Light, and Background")
        }
        ToolbarItem(id: "record", placement: .primaryAction) {
            RecordButton(model: model)
        }
    }
}

private struct PrompterToggle: View {

    let prompter: PrompterController

    var body: some View {
        Toggle(isOn: isShown) {
            Label("Prompter", systemImage: "rectangle.topthird.inset.filled")
        }
        .disabled(!prompter.session.canBegin)
        .help("\(prompter.isPrompterVisible ? "Hide" : "Show") the prompter (\(Shortcuts.togglePrompter.label))")
    }

    private var isShown: Binding<Bool> {
        Binding(
            get: { prompter.isPrompterVisible },
            set: { if $0 != prompter.isPrompterVisible { prompter.togglePrompter() } }
        )
    }
}

private struct RehearseButton: View {

    let prompter: PrompterController

    var body: some View {
        Button {
            prompter.rehearse()
        } label: {
            Label("Rehearse", systemImage: "play")
        }
        .disabled(!prompter.session.canBegin)
        .help(
            "Run the prompter without recording (\(Shortcuts.rehearse.label), "
                + "or \(PrompterKeyCommand.togglePlayback.keyLabel) while the prompter shows)"
        )
    }
}

/// Ready, the countdown, a rehearsal, or the recording's elapsed time.
private struct TakeStatusView: View {

    let prompter: PrompterController

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !prompter.session.isRunning)) { context in
            content(for: prompter.session.status(at: context.date))
                .font(.headline.monospacedDigit())
                .frame(minWidth: 110)
        }
    }

    @ViewBuilder
    private func content(for status: TakeStatus) -> some View {
        switch status {
        case .ready:
            Text("Ready").foregroundStyle(.secondary)
        case .countingDown(let mode, let remaining):
            Text("\(mode == .recording ? "Recording" : "Rehearsing") in \(remaining)")
        case .rehearsing(let isPaused):
            Text(isPaused ? "Rehearsing, paused" : "Rehearsing")
        case .recording(let elapsed):
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(ElapsedTime.format(elapsed))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording, \(ElapsedTime.format(elapsed))")
        case .saving:
            Text("Saving…").foregroundStyle(.secondary)
        }
    }
}

/// Slower, the speed, and faster: adjusted while reading, so it stays in reach.
private struct SpeedControl: View {

    let prompter: PrompterController

    var body: some View {
        let speed = prompter.settings.wordsPerMinute
        ControlGroup {
            Button {
                prompter.settings.slower()
            } label: {
                Label("Slower", systemImage: "minus")
            }
            .disabled(speed <= PrompterSettings.speedRange.lowerBound)
            .help(help(for: .slower))
            Text("\(Int(speed)) wpm")
                .monospacedDigit()
                .frame(minWidth: 64)
            Button {
                prompter.settings.faster()
            } label: {
                Label("Faster", systemImage: "plus")
            }
            .disabled(speed >= PrompterSettings.speedRange.upperBound)
            .help(help(for: .faster))
        } label: {
            Label("Speed", systemImage: "gauge.with.dots.needle.50percent")
        }
    }

    private func help(for command: PrompterKeyCommand) -> String {
        "\(command.summary) by \(Int(PrompterSettings.speedStep)) wpm (\(command.keyLabel) while the prompter shows)"
    }
}

private struct PrompterSettingsButton: View {

    let prompter: PrompterController
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Prompter Settings", systemImage: "slider.horizontal.3")
        }
        .help("Prompter settings: text size, lines, width, countdown, display, and keys")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PrompterSettingsForm(prompter: prompter)
        }
    }
}

/// Record, or Stop while a countdown, a run, or saving is under way.
private struct RecordButton: View {

    let model: AppModel

    var body: some View {
        let session = model.prompter.session
        Group {
            if session.isRunning {
                Button {
                    model.prompter.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(session.phase == .finishing)
                .help("Stop (\(PrompterKeyCommand.stop.keyLabel) or \(Shortcuts.stop.label))")
            } else {
                Button {
                    model.prompter.record()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .disabled(!model.canRecord)
                .help(recordHelp)
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private var recordHelp: String {
        if !model.capture.access.canUseCamera {
            return "Record needs camera access"
        }
        return "Count down, then record a take with the prompter (\(Shortcuts.record.label))"
    }
}
