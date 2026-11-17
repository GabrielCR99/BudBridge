import QCYKit
import SwiftUI

struct OverviewView: View {
    @Environment(Headphones.self) private var headphones

    var body: some View {
        let control = headphones.control
        ScrollView {
            VStack(spacing: 20) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        BatteryCard(title: "Left", symbol: "earbud.left", level: control.battery?.left)
                        BatteryCard(title: "Right", symbol: "earbud.right", level: control.battery?.right)
                        BatteryCard(title: "Case", symbol: "earbuds.case", level: control.battery?.chargingCase)
                    }
                }

                if control.isReady, let noise = control.settings.noiseControl {
                    GroupBox("Noise Control") {
                        NoiseKindPicker(control: control, current: noise)
                            .padding(.vertical, 4)
                    }
                }

                GroupBox("Connections") {
                    VStack(alignment: .leading, spacing: 12) {
                        AudioConnectionRow(audio: headphones.audio)
                        Divider()
                        ControlConnectionRow(control: control)
                    }
                    .padding(.vertical, 4)
                }

                if control.isReady {
                    QuickTogglesView(control: control)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}

struct BatteryCard: View {
    let title: String
    let symbol: String
    let level: BatteryLevel?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            if let level {
                Gauge(value: Double(level.percent), in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    HStack(spacing: 2) {
                        if level.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                        Text("\(level.percent)%").monospacedDigit()
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint(level.percent))
            } else {
                Text("—")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func tint(_ percent: Int) -> Color {
        switch percent {
        case ..<15: .red
        case ..<35: .orange
        default: .green
        }
    }
}

struct NoiseKindPicker: View {
    let control: ControlLink
    let current: NoiseControl

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { current.kind },
            set: { kind in
                guard kind != current.kind else { return }
                control.set(noiseControl: kind.defaultSetting)
            }
        )) {
            ForEach(NoiseControl.Kind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct AudioConnectionRow: View {
    let audio: AudioLink

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("Audio")
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: audio.isConnected ? "headphones" : "headphones.slash")
                    .foregroundStyle(audio.isConnected ? .green : .secondary)
            }
            Spacer()
            if audio.isBusy {
                ProgressView().controlSize(.small)
            } else if !audio.isPaired {
                Button("Pair in Settings…") { audio.openBluetoothSettings() }
            } else if audio.isConnected {
                Button("Disconnect") { audio.disconnect() }
            } else {
                Button("Connect") { audio.connect() }
                    .buttonStyle(.glassProminent)
            }
        }
        .onAppear { audio.refresh() }
    }

    private var detail: String {
        if let error = audio.lastError { return error }
        guard audio.isPaired else { return "Not paired with this Mac" }
        return audio.isConnected ? "Connected to this Mac (AAC/SBC)" : "Paired, not connected"
    }
}

struct ControlConnectionRow: View {
    let control: ControlLink

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("Controls")
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(control.isReady ? .green : .secondary)
            }
            Spacer()
            if control.phase == .paused {
                Button("Take Control") { control.resume() }
                    .buttonStyle(.glassProminent)
            } else if control.isReady {
                Button("Release to Phone") { control.pause() }
                    .help("Disconnects the control link so the QCY phone app can connect.")
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var detail: String {
        switch control.phase {
        case .ready:
            control.firmware.map { "Firmware \($0.display)" } ?? "Connected over Bluetooth LE"
        case .paused: "Released — the phone app can connect"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission required"
        default: "Searching… close the QCY app on your phone if it's open"
        }
    }
}

struct QuickTogglesView: View {
    let control: ControlLink

    var body: some View {
        GroupBox("Quick Settings") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { control.settings.lowLatency ?? false },
                                     set: { control.set(lowLatency: $0) })) {
                    Label("Gaming Mode", systemImage: "gamecontroller")
                }
                Toggle(isOn: Binding(get: { control.settings.dualDevice ?? false },
                                     set: { control.set(dualDevice: $0) })) {
                    Label("Dual Device Connection", systemImage: "laptopcomputer.and.iphone")
                }
                .disabled(control.isRestarting)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
