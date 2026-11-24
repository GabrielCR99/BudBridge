import Foundation
import Observation

/// The menu-bar extra: battery, noise mode, gaming mode and the audio connection.
@Observable
final class MenuBarViewModel {
    /// What the panel shows under the battery.
    enum Content: Equatable {
        case controls
        case released
        case searching
    }

    let battery: BatteryViewModel
    let noise: NoiseModesViewModel
    let switches: SwitchesViewModel
    let connections: ConnectionsStatusViewModel

    /// Called when the user opens the main window from the panel.
    @ObservationIgnored var onOpenControls: (() -> Void)?
    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore, audio: any AudioConnecting) {
        self.store = store
        battery = BatteryViewModel(store: store)
        noise = NoiseModesViewModel(store: store)
        switches = SwitchesViewModel(store: store)
        connections = ConnectionsStatusViewModel(store: store, audio: audio)
    }

    var title: String { store.isReady ? store.modelName : "BudBridge" }
    var status: LinkStatus { LinkStatus(store: store) }

    var content: Content {
        switch store.phase {
        case .ready: .controls
        case .paused: .released
        default: .searching
        }
    }

    func openControls() {
        onOpenControls?()
    }

    func takeControl() {
        store.resume()
    }
}
