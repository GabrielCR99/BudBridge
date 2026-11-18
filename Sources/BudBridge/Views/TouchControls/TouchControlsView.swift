import QCYKit
import SwiftUI

struct TouchControlsView: View {
    let viewModel: TouchControlsViewModel

    var body: some View {
        Form {
            ForEach(viewModel.groups) { group in
                Section(group.name) {
                    ForEach(group.controls) { control in
                        picker(for: control)
                    }
                }
            }
            if !viewModel.callGestures.isEmpty {
                Section {
                    ForEach(viewModel.callGestures) { gesture in
                        LabeledContent(gesture.name) {
                            Text(gesture.detail).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Calls")
                } footer: {
                    Text("Call gestures are fixed by the firmware.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func picker(for control: TouchControl) -> some View {
        let selection = viewModel.selection(for: control)
        return Picker(control.gesture, selection: Binding(
            get: { selection?.value ?? [] },
            set: { value in
                if let option = control.options.first(where: { $0.value == value }) {
                    viewModel.select(option, for: control)
                }
            }
        )) {
            if selection == nil {
                Text("—").tag([UInt8]())
            }
            ForEach(control.options) { option in
                Text(option.name).tag(option.value)
            }
        }
    }
}
