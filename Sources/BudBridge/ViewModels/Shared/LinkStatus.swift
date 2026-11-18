import Foundation

/// The control link's state as a short label and a tone, for status badges.
struct LinkStatus: Equatable {
    enum Tone: Equatable {
        case connected, busy, searching, released, problem
    }

    var text: String
    var tone: Tone

    init(store: HeadphonesStore) {
        switch store.phase {
        case .ready where store.isRestarting:
            text = String(localized: "Restarting…")
            tone = .busy
        case .ready:
            text = String(localized: "Connected")
            tone = .connected
        case .searching, .starting:
            text = String(localized: "Searching")
            tone = .searching
        case .connecting:
            text = String(localized: "Connecting")
            tone = .searching
        case .paused:
            text = String(localized: "Released")
            tone = .released
        case .bluetoothOff:
            text = String(localized: "Bluetooth off")
            tone = .problem
        case .unauthorized:
            text = String(localized: "No permission")
            tone = .problem
        }
    }
}
