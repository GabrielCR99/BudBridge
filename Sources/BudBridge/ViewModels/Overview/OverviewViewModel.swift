import Foundation
import Observation

/// The overview page: battery, noise mode, connections and quick switches.
@Observable
final class OverviewViewModel {
    let battery: BatteryViewModel
    let noise: NoiseModesViewModel
    let connections: ConnectionsStatusViewModel
    let switches: SwitchesViewModel

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore, audio: any AudioConnecting) {
        self.store = store
        battery = BatteryViewModel(store: store)
        noise = NoiseModesViewModel(store: store)
        connections = ConnectionsStatusViewModel(store: store, audio: audio)
        switches = SwitchesViewModel(store: store)
    }

    var showsNoiseControl: Bool { noise.panel != nil }

    var showsQuickSettings: Bool { (store.isReady || isLoading) && !switches.quickToggles.isEmpty }

    /// The earbuds are connecting: noise control and quick settings are shown as placeholders.
    var isLoading: Bool { store.isLoadingSettings }

    // MARK: - Settings list download

    /// Connected, but the model's settings list hasn't arrived from QCY yet.
    var showsSettingsDownload: Bool { store.isReady && store.panel == nil }
    var settingsDownloadFailed: Bool { store.panelDownloadFailed }

    var settingsDownloadText: String {
        store.panelDownloadFailed
            ? String(localized: "Couldn't download the settings for \(store.modelName). BudBridge needs the internet once for each model.")
            : String(localized: "Downloading the settings for \(store.modelName)…")
    }

    func retrySettingsDownload() {
        store.retryPanelDownload()
    }
}
