import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, noise, sound, controls, connectivity, device

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .noise: "Noise Control"
        case .sound: "Sound Effects"
        case .controls: "Touch Controls"
        case .connectivity: "Connectivity"
        case .device: "Device"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .noise: "waveform.circle"
        case .sound: "slider.vertical.3"
        case .controls: "hand.tap"
        case .connectivity: "antenna.radiowaves.left.and.right"
        case .device: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(Headphones.self) private var headphones
    @SceneStorage("section") private var selection: Page = .overview

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .navigationTitle(selection.title)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        LinkStatusBadge(control: headphones.control)
                    }
                }
        }
    }

    @ViewBuilder private var detail: some View {
        let control = headphones.control
        switch selection {
        case .overview: OverviewView()
        case .noise: RequiresControl(control: control) { NoiseControlView(control: control) }
        case .sound: RequiresControl(control: control) { SoundView(control: control) }
        case .controls: RequiresControl(control: control) { TouchControlsView(control: control) }
        case .connectivity: ConnectivityView()
        case .device: RequiresControl(control: control) { DeviceView() }
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
                Text("Allow MeloBuds Control in System Settings › Privacy & Security › Bluetooth.")
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
                    .buttonStyle(.glassProminent)
            }
        case .starting, .searching, .connecting, .ready:
            ContentUnavailableView {
                Label(control.phase == .connecting ? "Connecting…" : "Looking for MeloBuds Pro…",
                      systemImage: "earbuds")
                    .symbolEffect(.pulse)
            } description: {
                Text("Take the earbuds out of the case. If the QCY app on your phone is open, close it — the earbuds accept only one controller at a time.")
            }
        }
    }
}

struct LinkStatusBadge: View {
    let control: ControlLink

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var color: Color {
        switch control.phase {
        case .ready: control.isRestarting ? .orange : .green
        case .searching, .connecting, .starting: .yellow
        case .paused: .gray
        case .bluetoothOff, .unauthorized: .red
        }
    }

    private var text: String {
        switch control.phase {
        case .ready: control.isRestarting ? "Restarting…" : "Connected"
        case .searching, .starting: "Searching"
        case .connecting: "Connecting"
        case .paused: "Released"
        case .bluetoothOff: "Bluetooth off"
        case .unauthorized: "No permission"
        }
    }
}
