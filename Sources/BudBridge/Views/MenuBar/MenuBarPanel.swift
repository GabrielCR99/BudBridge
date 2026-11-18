import QCYKit
import SwiftUI

struct MenuBarPanel: View {
    let viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(viewModel.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                LinkStatusBadge(status: viewModel.status)
                    .fixedSize()
            }

            BatteryFreshness(viewModel: viewModel.battery) {
                HStack(spacing: 18) {
                    ForEach(viewModel.battery.slots) { slot in
                        MiniBattery(slot: slot)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            switch viewModel.content {
            case .controls:
                if viewModel.noise.panel != nil {
                    NoiseModeTiles(viewModel: viewModel.noise)
                }
                if let gaming = viewModel.switches.gamingMode {
                    PanelToggle(viewModel: viewModel.switches, item: gaming)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .released:
                Button("Take Control from Phone") { viewModel.takeControl() }
            case .searching:
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
        .restartConfirmation(viewModel.switches)
        .onAppear { viewModel.connections.refreshAudio() }
    }

    @ViewBuilder private var audioButton: some View {
        let connections = viewModel.connections
        switch connections.audioAction {
        case .pair:
            Button("Pair…") { connections.performAudioAction() }.fixedSize()
        case .connect, .busy:
            Button("Connect Audio") { connections.performAudioAction() }
                .disabled(connections.audioAction == .busy)
                .fixedSize()
        case .disconnect:
            Button("Disconnect Audio") { connections.performAudioAction() }.fixedSize()
        }
    }

    private var openButton: some View {
        Button("Open Controls") {
            // Close the panel first, so it doesn't stay open on top of the window.
            dismiss()
            openWindow(id: "main")
            NSApp.activate()
        }
        .prominentButtonStyle()
        .fixedSize()
    }
}

private struct MiniBattery: View {
    let slot: BatteryViewModel.Slot

    var body: some View {
        VStack(spacing: 4) {
            Text(slot.level.map { "\($0.percent)%" } ?? "—")
                .font(.title3.monospacedDigit().weight(.medium))
            HStack(spacing: 2) {
                if slot.level?.isCharging == true { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                Text(slot.shortTitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Noise modes as equal-width tiles whose labels wrap, so long names (e.g. "Cancelamento de ruídos")
/// never widen the panel, and selecting a mode changes only its colour, not its size.
private struct NoiseModeTiles: View {
    let viewModel: NoiseModesViewModel

    var body: some View {
        let selected = viewModel.selectedMode?.id
        HStack(spacing: 6) {
            ForEach(viewModel.modes) { mode in
                let isSelected = mode.id == selected
                Button {
                    viewModel.select(mode)
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
