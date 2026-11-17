import QCYKit
import SwiftUI

struct TouchControlsView: View {
    let control: ControlLink

    var body: some View {
        Form {
            ForEach([true, false], id: \.self) { left in
                Section(left ? "Left Earbud" : "Right Earbud") {
                    ForEach(TouchGesture.allCases.filter { $0.isLeft == left }) { gesture in
                        Picker(gesture.title, selection: Binding(
                            get: { control.touchControls[gesture] ?? TouchAction.none },
                            set: { control.set($0, for: gesture) }
                        )) {
                            ForEach(TouchAction.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                    }
                }
            }
            Section {
                LabeledContent("Calls") {
                    Text("Double tap answers or ends · Long press (1.5 s) declines")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Call gestures are fixed by the firmware.")
            }
        }
        .formStyle(.grouped)
    }
}
