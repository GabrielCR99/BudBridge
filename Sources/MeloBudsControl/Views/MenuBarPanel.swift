import QCYKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(Headphones.self) private var headphones
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let control = headphones.control
        let audio = headphones.audio
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MeloBuds Pro").font(.headline)
                Spacer()
                LinkStatusBadge(control: control)
            }

            HStack(spacing: 18) {
                MiniBattery(title: "L", level: control.battery?.left)
                MiniBattery(title: "R", level: control.battery?.right)
                MiniBattery(title: "Case", level: control.battery?.chargingCase)
            }
            .frame(maxWidth: .infinity)

            if control.isReady, let noise = control.settings.noiseControl {
                NoiseKindPicker(control: control, current: noise)
                Toggle("Gaming Mode", isOn: Binding(get: { control.settings.lowLatency ?? false },
                                                    set: { control.set(lowLatency: $0) }))
                    .toggleStyle(.switch)
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
        .onAppear { audio.refresh() }
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
