import QCYKit
import SwiftUI

struct OverviewView: View {
    @Environment(Headphones.self) private var headphones
    @State private var pending: ToggleItem?

    var body: some View {
        let control = headphones.control
        let battery = control.state.battery
        ScrollView {
            VStack(spacing: 20) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        BatteryCard(title: String(localized: "Left"), symbol: "earbud.left", level: battery?.left)
                        BatteryCard(title: String(localized: "Right"), symbol: "earbud.right", level: battery?.right)
                        BatteryCard(title: String(localized: "Case"), symbol: "earbuds.case", level: battery?.chargingCase)
                    }
                }

                if control.isReady, let noise = control.panel?.noiseControl {
                    GroupBox(noise.title) {
                        NoiseModePicker(control: control, panel: noise)
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

                if control.isReady, !quickToggles.isEmpty {
                    GroupBox("Quick Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(quickToggles, id: \.self) { item in
                                PanelToggle(control: control, item: item, pending: $pending)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .restartConfirmation($pending, control: control)
        .onAppear { headphones.audio.refresh() }
    }

    /// Gaming mode and dual-device connection when the model has them, else its first two switches.
    private var quickToggles: [ToggleItem] {
        let toggles = (headphones.control.panel?.settings ?? []).compactMap { item -> ToggleItem? in
            if case .toggle(let t) = item { t } else { nil }
        }
        let preferred = toggles.filter { [CommandID.lowLatency.rawValue, CommandID.dualDevice.rawValue].contains($0.stateCommand ?? 0) }
        return preferred.isEmpty ? Array(toggles.prefix(2)) : preferred
    }
}
