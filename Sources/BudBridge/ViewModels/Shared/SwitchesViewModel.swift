import Foundation
import Observation
import QCYKit

/// Switches from the settings list, including the confirmation for ones that restart the earbuds.
@Observable
final class SwitchesViewModel {
    /// A switch waiting for the user to confirm, because turning it on restarts the earbuds.
    private(set) var pendingRestart: ToggleItem?

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
    }

    func isOn(_ item: ToggleItem) -> Bool {
        item.isOn(in: store.state) ?? false
    }

    /// Disabled while the earbuds restart from a previous change.
    func isEnabled(_ item: ToggleItem) -> Bool {
        !(store.isRestarting && item.restartsEarbuds)
    }

    /// The panel's own explanation, shown under the switch (restart warnings go in the confirmation).
    func caption(for item: ToggleItem) -> String? {
        item.restartsEarbuds ? nil : item.message
    }

    func set(_ item: ToggleItem, on: Bool) {
        if on, item.restartsEarbuds {
            pendingRestart = item
        } else {
            store.set(item, on: on)
        }
    }

    func confirmRestart() {
        if let item = pendingRestart { store.set(item, on: true) }
        pendingRestart = nil
    }

    func cancelRestart() {
        pendingRestart = nil
    }

    /// The panel's warning, or a generic one.
    var restartMessage: String {
        pendingRestart?.message ?? String(localized: "The earbuds will restart.")
    }

    /// Gaming mode, if the model has it.
    var gamingMode: ToggleItem? {
        toggles.first { $0.stateCommand == CommandID.lowLatency.rawValue }
    }

    /// Gaming mode and dual-device connection when the model has them, else its first two switches.
    var quickToggles: [ToggleItem] {
        let preferred = toggles.filter {
            [CommandID.lowLatency.rawValue, CommandID.dualDevice.rawValue].contains($0.stateCommand ?? 0)
        }
        return preferred.isEmpty ? Array(toggles.prefix(2)) : preferred
    }

    private var toggles: [ToggleItem] {
        (store.panel?.settings ?? []).compactMap { item in
            if case .toggle(let toggle) = item { toggle } else { nil }
        }
    }
}
