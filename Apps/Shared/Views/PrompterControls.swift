import NotchPrompterKit
import SwiftUI

/// Prompter settings and the rehearsal controls, in the session column.
struct PrompterControls: View {

    @Bindable var prompter: PrompterController

    var body: some View {
        Section("Prompter") {
            HStack {
                Button(prompter.isPrompterVisible ? "Hide Prompter" : "Show Prompter") {
                    prompter.togglePrompter()
                }
                .disabled(!(prompter.session.phase == .hidden || prompter.session.phase == .ready))
                Button("Rehearse") { prompter.rehearse() }
                    .disabled(!prompter.session.canBegin)
            }
            LabeledContent("Speed") {
                Stepper(
                    "\(Int(prompter.settings.wordsPerMinute)) wpm",
                    value: $prompter.settings.wordsPerMinute,
                    in: PrompterSettings.speedRange,
                    step: PrompterSettings.speedStep
                )
            }
            LabeledContent("Text size") {
                Stepper(
                    "\(Int(prompter.settings.fontSize)) pt",
                    value: $prompter.settings.fontSize,
                    in: PrompterSettings.fontSizeRange,
                    step: PrompterSettings.fontSizeStep
                )
            }
            LabeledContent("Lines") {
                Stepper(
                    "\(prompter.settings.visibleLines)",
                    value: $prompter.settings.visibleLines,
                    in: PrompterSettings.visibleLinesRange
                )
            }
            LabeledContent("Countdown") {
                Stepper(
                    "\(prompter.settings.countdownSeconds) s",
                    value: $prompter.settings.countdownSeconds,
                    in: PrompterSettings.countdownRange
                )
            }
            LabeledContent("Width") {
                Slider(value: $prompter.settings.width, in: PrompterSettings.widthRange, step: 10)
            }
            Picker("Display", selection: displaySelection) {
                ForEach(prompter.displays) { display in
                    Text(display.hasNotch ? "\(display.name) (notch)" : display.name)
                        .tag(Optional(display.id))
                }
            }
        }
        Section("Keys while the prompter shows") {
            ForEach(PrompterKeyCommand.allCases, id: \.self) { command in
                LabeledContent(command.summary) {
                    Text(command.keyLabel).monospaced()
                }
                .font(.caption)
            }
        }
    }

    private var displaySelection: Binding<CGDirectDisplayID?> {
        Binding(
            get: { prompter.activeDisplay?.id },
            set: { prompter.preferredDisplayID = $0 }
        )
    }
}
