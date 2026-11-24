import SwiftUI

/// The app's settings window (⌘,).
struct GeneralSettingsView: View {
    @Bindable var viewModel: GeneralSettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $viewModel.launchesAtLogin)
                if viewModel.loginItemNeedsApproval {
                    LabeledContent("Allow BudBridge in System Settings to open it at login.") {
                        Button("Open Login Items…") { viewModel.openLoginItemsSettings() }
                    }
                }
                if let error = viewModel.loginItemError {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text("BudBridge waits in the background, so it can notice your earbuds connecting.")
            }

            Section {
                Toggle("Show only while earbuds are connected", isOn: $viewModel.showsOnlyWhenConnected)
                Toggle("Open the window when earbuds connect", isOn: $viewModel.opensWindowOnConnect)
            } footer: {
                Text("When your earbuds disconnect, BudBridge closes its window and leaves the menu bar and the Dock. It comes back when they reconnect, or when you open it.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { viewModel.refresh() }
    }
}
