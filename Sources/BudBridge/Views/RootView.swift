import QCYKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, noise, sound, controls, settings, connections

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .noise: String(localized: "Noise Control")
        case .sound: String(localized: "Sound")
        case .controls: String(localized: "Touch Controls")
        case .settings: String(localized: "Settings")
        case .connections: String(localized: "Connections")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .noise: "waveform.circle"
        case .sound: "slider.vertical.3"
        case .controls: "hand.tap"
        case .settings: "gearshape"
        case .connections: "antenna.radiowaves.left.and.right"
        }
    }

    /// Pages appear only when the connected model's settings list has something for them.
    func isAvailable(for panel: ControlPanel?) -> Bool {
        switch self {
        case .overview, .connections: true
        case .noise: panel?.noiseControl != nil
        case .sound: panel?.equalizer != nil || panel?.balance != nil
        case .controls: panel?.touch != nil
        case .settings: panel != nil
        }
    }
}

struct RootView: View {
    @Environment(Headphones.self) private var headphones
    @SceneStorage("page") private var selection: Page = .overview

    var body: some View {
        let control = headphones.control
        let pages = Page.allCases.filter { $0.isAvailable(for: control.panel) }
        NavigationSplitView {
            List(pages, selection: $selection) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail(pages.contains(selection) ? selection : .overview)
                .navigationTitle(control.isReady ? control.modelName : "BudBridge")
                .navigationSubtitle(selection.title)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        LinkStatusBadge(control: control)
                    }
                }
        }
        .onChange(of: control.advertisement) { _, ad in headphones.audio.focus(on: ad) }
    }

    @ViewBuilder private func detail(_ page: Page) -> some View {
        let control = headphones.control
        switch page {
        case .overview: OverviewView()
        case .noise: RequiresControl(control: control) { NoiseControlView(control: control) }
        case .sound: RequiresControl(control: control) { SoundView(control: control) }
        case .controls: RequiresControl(control: control) { TouchControlsView(control: control) }
        case .settings: RequiresControl(control: control) { SettingsView() }
        case .connections: ConnectionsView()
        }
    }
}

/// Shows the page only while the BLE control link is up; otherwise explains why it isn't.
struct RequiresControl<Content: View>: View {
    let control: ControlLink
    @ViewBuilder var content: Content

    var body: some View {
        if control.isReady {
            content
        } else {
            ControlUnavailableView(control: control)
        }
    }
}

struct ControlUnavailableView: View {
    let control: ControlLink

    var body: some View {
        switch control.phase {
        case .bluetoothOff:
            ContentUnavailableView("Bluetooth Is Off", systemImage: "bolt.horizontal.circle",
                description: Text("Turn on Bluetooth to control your earbuds."))
        case .unauthorized:
            ContentUnavailableView {
                Label("Bluetooth Access Needed", systemImage: "lock.shield")
            } description: {
                Text("Allow this app in System Settings › Privacy & Security › Bluetooth.")
            } actions: {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                }
            }
        case .paused:
            ContentUnavailableView {
                Label("Control Released", systemImage: "pause.circle")
            } description: {
                Text("The earbuds are free for the QCY app on your phone.")
            } actions: {
                Button("Take Control") { control.resume() }
                    .prominentButtonStyle()
            }
        case .starting, .searching, .connecting, .ready:
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label(control.phase == .connecting ? "Connecting…" : "Looking for QCY Earbuds…",
                          systemImage: "earbuds")
                        .symbolEffect(.pulse)
                } description: {
                    Text("Earbuds paired with this Mac connect automatically. Close the QCY app on your phone if it's open: the earbuds accept only one controller at a time.")
                }
                if !control.nearby.isEmpty {
                    Form {
                        Section("Nearby") { NearbyDevicesList(control: control) }
                    }
                    .formStyle(.grouped)
                    .frame(maxWidth: 520, maxHeight: 280)
                }
            }
        }
    }
}
