import QCYKit
import SwiftUI

struct TouchControlsView: View {
    let control: ControlLink

    var body: some View {
        if let touch = control.panel?.touch {
            Form {
                ForEach(touch.groups) { group in
                    Section(group.name) {
                        ForEach(group.controls) { item in
                            Picker(item.gesture, selection: Binding(
                                get: { item.selection(in: control.state)?.value ?? [] },
                                set: { value in
                                    if let option = item.options.first(where: { $0.value == value }) {
                                        control.set(option, for: item)
                                    }
                                }
                            )) {
                                if item.selection(in: control.state) == nil {
                                    Text("—").tag([UInt8]())
                                }
                                ForEach(item.options) { option in
                                    Text(option.name).tag(option.value)
                                }
                            }
                        }
                    }
                }
                if !touch.callGestures.isEmpty {
                    Section {
                        ForEach(touch.callGestures, id: \.self) { gesture in
                            LabeledContent(gesture.name) {
                                Text(gesture.left == gesture.right ? gesture.left : "L: \(gesture.left) · R: \(gesture.right)")
                                    .foregroundStyle(.secondary)
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
    }
}
