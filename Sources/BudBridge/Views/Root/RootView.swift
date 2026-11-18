import SwiftUI

/// The main window: a sidebar of the pages the connected model supports.
struct RootView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        let root = coordinator.root
        NavigationSplitView {
            List(root.pages, selection: $coordinator.selectedPage) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            let page = root.page(for: coordinator.selectedPage)
            detail(page)
                .navigationTitle(root.title)
                .navigationSubtitle(page.title)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        LinkStatusBadge(status: root.status)
                    }
                }
        }
    }

    @ViewBuilder
    private func detail(_ page: Page) -> some View {
        if page.needsControl, !coordinator.root.isControlReady {
            ControlUnavailableView(viewModel: coordinator.root)
        } else {
            switch page {
            case .overview: OverviewView(viewModel: coordinator.overview)
            case .noise: NoiseControlView(viewModel: coordinator.noiseControl)
            case .sound: SoundView(viewModel: coordinator.sound)
            case .controls: TouchControlsView(viewModel: coordinator.touchControls)
            case .settings: SettingsView(viewModel: coordinator.settings)
            case .connections: ConnectionsView(viewModel: coordinator.connections)
            }
        }
    }
}

/// Explains why a page that needs the control link isn't available yet.
struct ControlUnavailableView: View {
    let viewModel: RootViewModel

    var body: some View {
        switch viewModel.unavailable {
        case .bluetoothOff:
            ContentUnavailableView("Bluetooth Is Off", systemImage: "bolt.horizontal.circle",
                                   description: Text("Turn on Bluetooth to control your earbuds."))
        case .unauthorized:
            ContentUnavailableView {
                Label("Bluetooth Access Needed", systemImage: "lock.shield")
            } description: {
                Text("Allow this app in System Settings › Privacy & Security › Bluetooth.")
            } actions: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(url) }
                }
            }
        case .released:
            ContentUnavailableView {
                Label("Control Released", systemImage: "pause.circle")
            } description: {
                Text("The earbuds are free for the QCY app on your phone.")
            } actions: {
                Button("Take Control") { viewModel.takeControl() }
                    .prominentButtonStyle()
            }
        case .searching(let connecting):
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label(connecting ? "Connecting…" : "Looking for QCY Earbuds…", systemImage: "earbuds")
                        .symbolEffect(.pulse)
                } description: {
                    Text("Earbuds paired with this Mac connect automatically. Close the QCY app on your phone if it's open: the earbuds accept only one controller at a time.")
                }
                if !viewModel.nearby.isEmpty {
                    Form {
                        Section("Nearby") { NearbyDevicesList(viewModel: viewModel.nearby) }
                    }
                    .formStyle(.grouped)
                    .frame(maxWidth: 520, maxHeight: 280)
                }
            }
        }
    }
}
