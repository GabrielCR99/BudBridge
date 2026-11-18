import Foundation
import Observation
import QCYKit

/// The model's noise-control modes (e.g. Noise canceling · Transparency · Normal) and the current one.
@Observable
final class NoiseModesViewModel {
    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
    }

    /// The model's noise controls once connected, or as a placeholder while the earbuds connect.
    var panel: NoiseControlPanel? {
        store.isReady || store.isLoadingSettings ? store.panel?.noiseControl : nil
    }

    var title: String { panel?.title ?? "" }
    var modes: [NoiseMode] { panel?.modes ?? [] }

    /// The raw value the earbuds reported, if any.
    var value: Int? { NoiseValue.value(in: store.state) }

    var selectedMode: NoiseMode? {
        guard let value else { return nil }
        return panel?.mode(for: value)
    }

    func select(_ mode: NoiseMode) {
        guard mode.id != selectedMode?.id else { return }
        store.setNoise(mode.defaultValue)
    }

    func select(id: Int) {
        if let mode = modes.first(where: { $0.id == id }) { select(mode) }
    }

    /// Sends a specific value (a scene, strength or level within the current mode).
    func setValue(_ value: Int) {
        store.setNoise(value)
    }
}
