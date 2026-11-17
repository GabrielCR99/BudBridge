import QCYKit
import SwiftUI

struct ConnectionsView: View {
    @Environment(Headphones.self) private var headphones

    var body: some View {
        let control = headphones.control
        Form {
            Section("This Mac") {
                AudioConnectionRow(audio: headphones.audio)
                ControlConnectionRow(control: control)
            }

            if control.isReady {
                Section {
                    Button("Use Different Earbuds…") { control.forget() }
                } footer: {
                    Text("Disconnects \(control.modelName) and lists the QCY earbuds nearby.")
                }
            } else if control.phase != .paused {
                Section("Nearby") {
                    NearbyDevicesList(control: control)
                }
            }

            Section {
                Text("The earbuds accept one controller at a time. Use Release to Phone before opening the QCY app on your phone.")
                Text("macOS streams AAC or SBC. An LDAC switch changes the earbuds' setting for Android sources.")
            } header: {
                Text("Good to Know")
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { headphones.audio.refresh() }
    }
}
