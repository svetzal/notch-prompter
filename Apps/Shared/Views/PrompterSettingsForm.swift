import NotchPrompterKit
import SwiftUI

/// The prompter's look and placement, and the keys reference, shown in the
/// toolbar's Prompter Settings popover. Speed lives in the toolbar itself.
struct PrompterSettingsForm: View {

    @Bindable var prompter: PrompterController

    var body: some View {
        Form {
            Section("Prompter") {
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
                LabeledContent("Width") {
                    Slider(value: $prompter.settings.width, in: PrompterSettings.widthRange, step: 10)
                }
                LabeledContent("Countdown") {
                    Stepper(
                        "\(prompter.settings.countdownSeconds) s",
                        value: $prompter.settings.countdownSeconds,
                        in: PrompterSettings.countdownRange
                    )
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
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var displaySelection: Binding<CGDirectDisplayID?> {
        Binding(
            get: { prompter.activeDisplay?.id },
            set: { prompter.preferredDisplayID = $0 }
        )
    }
}
