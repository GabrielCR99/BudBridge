import Foundation
import Observation

/// The audio and control connection rows shared by the overview, connections page and menu bar.
@Observable
final class ConnectionsStatusViewModel {
    /// What the audio row's button does.
    enum AudioAction: Equatable {
        case pair, connect, disconnect, busy
    }

    /// What the control row's button does.
    enum ControlAction: Equatable {
        case takeControl, release, busy
    }

    @ObservationIgnored private let store: HeadphonesStore
    @ObservationIgnored private let audio: any AudioConnecting

    init(store: HeadphonesStore, audio: any AudioConnecting) {
        self.store = store
        self.audio = audio
    }

    // MARK: - Audio

    var isAudioConnected: Bool { audio.isConnected }

    var audioSymbol: String {
        audio.isConnected ? "headphones" : Symbols.headphonesOff
    }

    var audioDetail: String {
        if let error = audio.lastError { return error }
        guard audio.isPaired, let name = audio.name else { return String(localized: "Not paired with this Mac") }
        return audio.isConnected
            ? String(localized: "\(name) · connected to this Mac (AAC/SBC)")
            : String(localized: "\(name) · paired, not connected")
    }

    var audioAction: AudioAction {
        if audio.isBusy { return .busy }
        guard audio.isPaired else { return .pair }
        return audio.isConnected ? .disconnect : .connect
    }

    var audioAddress: String? { audio.address }

    func performAudioAction() {
        switch audioAction {
        case .pair: audio.openBluetoothSettings()
        case .connect: audio.connect()
        case .disconnect: audio.disconnect()
        case .busy: break
        }
    }

    func refreshAudio() {
        audio.refresh()
    }

    // MARK: - Control

    var isControlReady: Bool { store.isReady }

    var controlDetail: String {
        switch store.phase {
        case .ready:
            [store.modelName, store.state.firmware.map { String(localized: "firmware \($0.display)") }]
                .compactMap(\.self).joined(separator: " · ")
        case .paused: String(localized: "Released, so the phone app can connect")
        case .bluetoothOff: String(localized: "Bluetooth is off")
        case .unauthorized: String(localized: "Bluetooth permission required")
        case .starting, .searching, .connecting: String(localized: "Searching… close the QCY app on your phone if it's open")
        }
    }

    var controlAction: ControlAction {
        switch store.phase {
        case .paused: .takeControl
        case .ready: .release
        default: .busy
        }
    }

    func performControlAction() {
        switch controlAction {
        case .takeControl: store.resume()
        case .release: store.pause()
        case .busy: break
        }
    }
}
