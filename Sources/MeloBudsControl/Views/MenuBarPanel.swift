import QCYKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(Headphones.self) private var headphones
    @Environment(\.openWindow) private var openWindow
    @State private var pending: ToggleItem?

    var body: some View {
        let control = headphones.control
        let audio = headphones.audio
        let battery = control.state.battery
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(control.isReady ? control.modelName : "QCY Earbuds").font(.headline)
                Spacer()
                LinkStatusBadge(control: control)
            }

            HStack(spacing: 18) {
                MiniBattery(title: "L", level: battery?.left)
                MiniBattery(title: "R", level: battery?.right)
                MiniBattery(title: "Case", level: battery?.chargingCase)
            }
            .frame(maxWidth: .infinity)

            if control.isReady {
                if let noise = control.panel?.noiseControl {
                    NoiseModePicker(control: control, panel: noise)
                }
                if let gaming = gamingToggle {
                    PanelToggle(control: control, item: gaming, pending: $pending)
                }
            } else if control.phase == .paused {
                Button("Take Control from Phone") { control.resume() }
            } else {
                Text("Searching for earbuds…").foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if audio.isPaired {
                    Button(audio.isConnected ? "Disconnect Audio" : "Connect Audio") {
                        audio.isConnected ? audio.disconnect() : audio.connect()
                    }
                    .disabled(audio.isBusy)
                } else {
                    Button("Pair…") { audio.openBluetoothSettings() }
                }
                Spacer()
                Button("Open Controls") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
        .restartConfirmation($pending, control: control)
        .onAppear { audio.refresh() }
    }

    private var gamingToggle: ToggleItem? {
        for case .toggle(let t) in headphones.control.panel?.settings ?? [] where t.stateCommand == CommandID.lowLatency.rawValue {
            return t
        }
        return nil
    }
}

private struct MiniBattery: View {
    let title: String
    let level: BatteryLevel?

    var body: some View {
        VStack(spacing: 4) {
            Text(level.map { "\($0.percent)%" } ?? "—")
                .font(.title3.monospacedDigit().weight(.medium))
            HStack(spacing: 2) {
                if level?.isCharging == true { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
