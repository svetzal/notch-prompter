import AppKit
import NotchPrompterKit
import SwiftUI

/// A plug-in's settings: its own view when it has one, or a list of its
/// parameters. A switch at the top moves between the two.
struct PluginEditorView: View {

    @Bindable var editor: PluginEditor

    var body: some View {
        VStack(spacing: 0) {
            if editor.viewController != nil {
                Picker("Show", selection: $editor.content) {
                    ForEach(PluginEditor.Content.allCases) { content in
                        Text(content.rawValue).tag(content)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(8)
                Divider()
            }
            switch editor.content {
            case .pluginView:
                if let controller = editor.viewController {
                    HostedViewController(controller: controller)
                }
            case .parameters:
                ParameterList(editor: editor)
            }
        }
        .frame(minWidth: 360, minHeight: 200)
    }
}

/// Shows a view controller the plug-in made, as it is.
private struct HostedViewController: NSViewControllerRepresentable {

    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        controller
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

private struct ParameterList: View {

    let editor: PluginEditor

    var body: some View {
        if editor.parameters.isEmpty {
            VStack(spacing: 8) {
                if editor.hasNoParameters {
                    Text("This plug-in shows no parameters to the app.")
                    Text("It still runs in the chain with its saved settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Waiting for the plug-in's parameters…").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            Form {
                ForEach(editor.parameters) { parameter in
                    ParameterRow(parameter: parameter, editor: editor)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ParameterRow: View {

    let parameter: PluginParameter
    let editor: PluginEditor

    var body: some View {
        switch parameter.control {
        case .toggle:
            Toggle(parameter.name, isOn: Binding(get: { parameter.value >= 0.5 }, set: { setValue($0 ? 1 : 0) }))
        case .choice(let names):
            Picker(parameter.name, selection: Binding(
                get: { Int((parameter.clampedValue - parameter.minValue).rounded()) },
                set: { setValue(parameter.minValue + Float($0)) }
            )) {
                ForEach(names.indices, id: \.self) { index in
                    Text(names[index]).tag(index)
                }
            }
        case .slider(let range):
            LabeledContent(parameter.name) {
                HStack {
                    Slider(value: Binding(get: { parameter.clampedValue }, set: { setValue($0) }), in: range)
                    Text(parameter.displayValue)
                        .monospacedDigit()
                        .frame(minWidth: 72, alignment: .trailing)
                }
            }
        case .readOnly:
            LabeledContent(parameter.name, value: parameter.displayValue)
        }
    }

    private func setValue(_ value: Float) {
        editor.setValue(value, for: parameter.address)
    }
}
