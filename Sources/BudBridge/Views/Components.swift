import QCYKit
import SwiftUI

/// Segmented picker over the model's noise-control modes (e.g. Noise canceling · Transparency · Normal).
struct NoiseModePicker: View {
    let control: ControlLink
    let panel: NoiseControlPanel

    var body: some View {
        let current = NoiseValue.value(in: control.state).flatMap(panel.mode(for:))
        Picker("Mode", selection: Binding(
            get: { current?.id ?? -1 },
            set: { id in
                guard id != current?.id, let mode = panel.modes.first(where: { $0.id == id }) else { return }
                control.setNoise(mode.defaultValue)
            }
        )) {
            ForEach(panel.modes) { mode in
                Text(mode.name).tag(mode.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A panel switch bound to the earbuds' reported state.
struct PanelToggle: View {
    let control: ControlLink
    let item: ToggleItem
    @Binding var pending: ToggleItem?

    var body: some View {
        Toggle(isOn: Binding(
            get: { item.isOn(in: control.state) ?? false },
            set: { on in
                if on, item.restartsEarbuds { pending = item } else { control.set(item, on: on) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let message = item.message, !item.restartsEarbuds {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(control.isRestarting && item.restartsEarbuds)
    }
}

extension View {
    /// Asks before a switch that restarts the earbuds, showing the panel's own warning.
    func restartConfirmation(_ pending: Binding<ToggleItem?>, control: ControlLink) -> some View {
        confirmationDialog(
            "Turn on \(pending.wrappedValue?.title ?? "")?",
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            presenting: pending.wrappedValue
        ) { item in
            Button("Turn On and Restart") { control.set(item, on: true) }
        } message: { item in
            Text(item.message ?? String(localized: "The earbuds will restart."))
        }
    }
}

/// Dims battery levels that may be out of date and says when they were last reported.
struct BatteryFreshness<Content: View>: View {
    let control: ControlLink
    @ViewBuilder var content: Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let stale = control.isBatteryStale(at: context.date)
            VStack(spacing: 6) {
                content
                    .opacity(stale ? 0.45 : 1)
                if stale, let updated = control.batteryUpdated {
                    Text("Last updated \(updated, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        .glassCard(cornerRadius: 18)
    }

    private func tint(_ percent: Int) -> Color {
        switch percent {
        case ..<15: .red
        case ..<35: .orange
        default: .green
        }
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
                Image(systemName: audio.isConnected ? "headphones" : Symbols.headphonesOff)
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
                    .prominentButtonStyle()
            }
        }
    }

    private var detail: String {
        if let error = audio.lastError { return error }
        guard audio.isPaired, let name = audio.name else { return String(localized: "Not paired with this Mac") }
        return audio.isConnected
            ? String(localized: "\(name) · connected to this Mac (AAC/SBC)")
            : String(localized: "\(name) · paired, not connected")
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
                    .prominentButtonStyle()
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
            [control.modelName, control.state.firmware.map { String(localized: "firmware \($0.display)") }].compactMap(\.self).joined(separator: " · ")
        case .paused: String(localized: "Released, so the phone app can connect")
        case .bluetoothOff: String(localized: "Bluetooth is off")
        case .unauthorized: String(localized: "Bluetooth permission required")
        default: String(localized: "Searching… close the QCY app on your phone if it's open")
        }
    }
}

/// QCY devices seen nearby, with a Connect button for supported models.
struct NearbyDevicesList: View {
    let control: ControlLink

    var body: some View {
        if control.nearby.isEmpty {
            Text("No QCY earbuds found yet. Take them out of the case.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(control.nearby.sorted { $0.rssi > $1.rssi }) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(device.model?.localizedNote
                             ?? (device.isSupported ? String(localized: "Supported") : String(localized: "This model isn't supported yet")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let level = device.advertisement.battery.lowestBud {
                        Text("\(level)%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button("Connect") { control.connect(to: device) }
                        .disabled(!device.isSupported)
                }
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
        case .ready: control.isRestarting ? String(localized: "Restarting…") : String(localized: "Connected")
        case .searching, .starting: String(localized: "Searching")
        case .connecting: String(localized: "Connecting")
        case .paused: String(localized: "Released")
        case .bluetoothOff: String(localized: "Bluetooth off")
        case .unauthorized: String(localized: "No permission")
        }
    }
}
