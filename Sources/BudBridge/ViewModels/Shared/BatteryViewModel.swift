import Foundation
import Observation
import QCYKit

/// Battery levels for the overview cards and the menu-bar panel.
@Observable
final class BatteryViewModel {
    /// One battery to show.
    struct Slot: Identifiable, Equatable {
        enum Kind: Equatable {
            case left, right, chargingCase
        }

        var kind: Kind
        var level: BatteryLevel?
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .left: String(localized: "Left")
            case .right: String(localized: "Right")
            case .chargingCase: String(localized: "Case")
            }
        }

        var shortTitle: String {
            switch kind {
            case .left: String(localized: "L", comment: "Left earbud, short")
            case .right: String(localized: "R", comment: "Right earbud, short")
            case .chargingCase: String(localized: "Case")
            }
        }

        var symbol: String {
            switch kind {
            case .left: Symbols.leftEarbud
            case .right: Symbols.rightEarbud
            case .chargingCase: "earbuds.case"
            }
        }
    }

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
    }

    /// Left and right, plus the case for models that report it.
    var slots: [Slot] {
        let battery = store.state.battery
        var slots = [Slot(kind: .left, level: battery?.left), Slot(kind: .right, level: battery?.right)]
        if store.reportsCaseBattery { slots.append(Slot(kind: .chargingCase, level: battery?.chargingCase)) }
        return slots
    }

    /// The lowest earbud level, for the menu-bar title.
    var lowestBud: Int? {
        store.isReady ? store.state.battery?.lowestBud : nil
    }

    func isStale(at date: Date) -> Bool {
        store.isBatteryStale(at: date)
    }

    var lastUpdated: Date? { store.batteryUpdated }
}
