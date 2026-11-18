import Foundation
import QCYKit

/// A page of the main window's sidebar.
enum Page: String, CaseIterable, Identifiable {
    case overview, noise, sound, controls, settings, connections

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .noise: String(localized: "Noise Control")
        case .sound: String(localized: "Sound")
        case .controls: String(localized: "Touch Controls")
        case .settings: String(localized: "Settings")
        case .connections: String(localized: "Connections")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .noise: "waveform.circle"
        case .sound: "slider.vertical.3"
        case .controls: "hand.tap"
        case .settings: "gearshape"
        case .connections: "antenna.radiowaves.left.and.right"
        }
    }

    /// Whether the page needs the BLE control link to show anything.
    var needsControl: Bool {
        ![.overview, .connections].contains(self)
    }

    /// Pages appear only when the connected model's settings list has something for them.
    func isAvailable(for panel: ControlPanel?) -> Bool {
        switch self {
        case .overview, .connections: true
        case .noise: panel?.noiseControl != nil
        case .sound: panel?.equalizer != nil || panel?.balance != nil
        case .controls: panel?.touch != nil
        case .settings: panel != nil
        }
    }
}
