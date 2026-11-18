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
                Text(control.isReady ? control.modelName : "BudBridge")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                LinkStatusBadge(control: control)
                    .fixedSize()
            }

            BatteryFreshness(control: control) {
                HStack(spacing: 18) {
                    MiniBattery(title: String(localized: "L", comment: "Left earbud, short"), level: battery?.left)
                    MiniBattery(title: String(localized: "R", comment: "Right earbud, short"), level: battery?.right)
                    if control.reportsCaseBattery {
                        MiniBattery(title: String(localized: "Case"), level: battery?.chargingCase)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if control.isReady {
                if let noise = control.panel?.noiseControl {
                    NoiseModeTiles(control: control, panel: noise)
                }
                if let gaming = gamingToggle {
                    PanelToggle(control: control, item: gaming, pending: $pending)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if control.phase == .paused {
                Button("Take Control from Phone") { control.resume() }
            } else {
                Text("Searching for earbuds…").foregroundStyle(.secondary)
            }

            Divider()

            // Side by side when they fit; stacked when translations are long.
            ViewThatFits(in: .horizontal) {
                HStack {
                    audioButton
                    Spacer(minLength: 8)
                    openButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    audioButton
                    openButton
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .restartConfirmation($pending, control: control)
        .onAppear { audio.refresh() }
    }

    @ViewBuilder private var audioButton: some View {
        let audio = headphones.audio
        if audio.isPaired {
            Button(audio.isConnected ? "Disconnect Audio" : "Connect Audio") {
                audio.isConnected ? audio.disconnect() : audio.connect()
            }
            .disabled(audio.isBusy)
            .fixedSize()
        } else {
            Button("Pair…") { audio.openBluetoothSettings() }
                .fixedSize()
        }
    }

    private var openButton: some View {
        Button("Open Controls") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .prominentButtonStyle()
        .fixedSize()
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

/// Noise modes as equal-width tiles whose labels wrap, so long names (e.g. "Cancelamento de ruídos")
/// never widen the panel, and selecting a mode changes only its colour, not its size.
private struct NoiseModeTiles: View {
    let control: ControlLink
    let panel: NoiseControlPanel

    var body: some View {
        let current = NoiseValue.value(in: control.state).flatMap(panel.mode(for:))
        HStack(spacing: 6) {
            ForEach(panel.modes) { mode in
                let isSelected = mode.id == current?.id
                Button {
                    if !isSelected { control.setNoise(mode.defaultValue) }
                } label: {
                    Text(mode.name)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: .rect(cornerRadius: 10))
                        .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
