import SwiftUI

struct ConnectionsView: View {
    let viewModel: ConnectionsViewModel

    var body: some View {
        Form {
            Section("This Mac") {
                AudioConnectionRow(viewModel: viewModel.status)
                ControlConnectionRow(viewModel: viewModel.status)
            }
            if viewModel.isControlReady {
                Section {
                    Button("Use Different Earbuds…") { viewModel.useDifferentEarbuds() }
                } footer: {
                    Text("Disconnects \(viewModel.modelName) and lists the QCY earbuds nearby.")
                }
            } else if viewModel.showsNearby {
                Section("Nearby") {
                    NearbyDevicesList(viewModel: viewModel.nearby)
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
        .onAppear { viewModel.status.refreshAudio() }
    }
}
