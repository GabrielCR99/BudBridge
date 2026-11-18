import QCYKit
import SwiftUI

/// Segmented picker over the model's noise-control modes.
struct NoiseModePicker: View {
    let viewModel: NoiseModesViewModel

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.selectedMode?.id ?? -1 },
            set: { viewModel.select(id: $0) }
        )) {
            ForEach(viewModel.modes) { mode in
                Text(mode.name).tag(mode.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A switch from the settings list.
struct PanelToggle: View {
    let viewModel: SwitchesViewModel
    let item: ToggleItem

    var body: some View {
        Toggle(isOn: Binding(get: { viewModel.isOn(item) }, set: { viewModel.set(item, on: $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let caption = viewModel.caption(for: item) {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(!viewModel.isEnabled(item))
    }
}

extension View {
    /// Asks before a switch that restarts the earbuds, showing the panel's own warning.
    func restartConfirmation(_ viewModel: SwitchesViewModel) -> some View {
        confirmationDialog(
            "Turn on \(viewModel.pendingRestart?.title ?? "")?",
            isPresented: Binding(get: { viewModel.pendingRestart != nil }, set: { if !$0 { viewModel.cancelRestart() } })
        ) {
            Button("Turn On and Restart") { viewModel.confirmRestart() }
        } message: {
            Text(viewModel.restartMessage)
        }
    }
}

/// Dims battery levels that may be out of date and says when they were last reported.
struct BatteryFreshness<Content: View>: View {
    let viewModel: BatteryViewModel
    @ViewBuilder var content: Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let stale = viewModel.isStale(at: context.date)
            VStack(spacing: 6) {
                content
                    .opacity(stale ? 0.45 : 1)
                if stale, let updated = viewModel.lastUpdated {
                    Text("Last updated \(updated, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BatteryCard: View {
    let slot: BatteryViewModel.Slot

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: slot.symbol)
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
            Text(slot.title)
                .font(.headline)
            if let level = slot.level {
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
    let viewModel: ConnectionsStatusViewModel

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("Audio")
                    Text(viewModel.audioDetail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: viewModel.audioSymbol)
                    .foregroundStyle(viewModel.isAudioConnected ? .green : .secondary)
            }
            Spacer()
            switch viewModel.audioAction {
            case .busy:
                ProgressView().controlSize(.small)
            case .pair:
                Button("Pair in Settings…") { viewModel.performAudioAction() }
            case .disconnect:
                Button("Disconnect") { viewModel.performAudioAction() }
            case .connect:
                Button("Connect") { viewModel.performAudioAction() }
                    .prominentButtonStyle()
            }
        }
    }
}

struct ControlConnectionRow: View {
    let viewModel: ConnectionsStatusViewModel

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("Controls")
                    Text(viewModel.controlDetail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(viewModel.isControlReady ? .green : .secondary)
            }
            Spacer()
            switch viewModel.controlAction {
            case .takeControl:
                Button("Take Control") { viewModel.performControlAction() }
                    .prominentButtonStyle()
            case .release:
                Button("Release to Phone") { viewModel.performControlAction() }
                    .help("Disconnects the control link so the QCY phone app can connect.")
            case .busy:
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// QCY devices seen nearby, with a Connect button for supported models.
struct NearbyDevicesList: View {
    let viewModel: NearbyDevicesViewModel

    var body: some View {
        if viewModel.isEmpty {
            Text("No QCY earbuds found yet. Take them out of the case.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        Text(row.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let battery = row.battery {
                        Text("\(battery)%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button("Connect") { viewModel.connect(row) }
                        .disabled(!row.canConnect)
                }
            }
        }
    }
}

struct LinkStatusBadge: View {
    let status: LinkStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var color: Color {
        switch status.tone {
        case .connected: .green
        case .busy: .orange
        case .searching: .yellow
        case .released: .gray
        case .problem: .red
        }
    }
}
