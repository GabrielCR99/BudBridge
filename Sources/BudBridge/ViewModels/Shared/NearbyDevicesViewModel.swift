import Foundation
import Observation

/// QCY devices seen nearby, with a Connect action for supported models.
@Observable
final class NearbyDevicesViewModel {
    /// One nearby device, ready to display.
    struct Row: Identifiable, Equatable {
        var id: UUID
        var name: String
        var detail: String
        var battery: Int?
        var canConnect: Bool
    }

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
    }

    /// Strongest signal first.
    var rows: [Row] {
        store.nearby.sorted { $0.rssi > $1.rssi }.map { device in
            Row(
                id: device.id,
                name: device.name,
                detail: device.model?.localizedNote
                    ?? (device.isSupported ? String(localized: "Supported") : String(localized: "This model isn't supported yet")),
                battery: device.advertisement.battery.lowestBud,
                canConnect: device.isSupported
            )
        }
    }

    var isEmpty: Bool { store.nearby.isEmpty }

    func connect(_ row: Row) {
        if let device = store.nearby.first(where: { $0.id == row.id }) { store.connect(to: device) }
    }
}
