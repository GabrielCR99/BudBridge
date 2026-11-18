import Foundation

/// What BudBridge remembers about earbuds across launches, in user defaults.
struct RememberedEarbuds {
    private let defaults: UserDefaults

    private enum Keys {
        static let peripheral = "peripheralID"
        static let vendor = "vendorID"
        static func caseBattery(_ vendorID: UInt16) -> String { "reportsCaseBattery.\(vendorID)" }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The last earbuds used: their LE peripheral and model.
    var last: (peripheral: UUID, vendor: UInt16)? {
        get {
            guard let id = defaults.string(forKey: Keys.peripheral).flatMap(UUID.init(uuidString:)),
                  let vendor = defaults.object(forKey: Keys.vendor) as? Int else { return nil }
            return (id, UInt16(vendor))
        }
        nonmutating set {
            defaults.set(newValue?.peripheral.uuidString, forKey: Keys.peripheral)
            defaults.set(newValue.map { Int($0.vendor) }, forKey: Keys.vendor)
        }
    }

    /// Whether this model has ever reported a charging-case level.
    func reportsCaseBattery(_ vendorID: UInt16) -> Bool {
        defaults.bool(forKey: Keys.caseBattery(vendorID))
    }

    func rememberCaseBattery(_ vendorID: UInt16) {
        defaults.set(true, forKey: Keys.caseBattery(vendorID))
    }
}
