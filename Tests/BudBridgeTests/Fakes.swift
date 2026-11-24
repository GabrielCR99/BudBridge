@testable import BudBridge
import Foundation
import QCYKit
import Testing

/// A `ControlTransport` that records what the store asks for and lets tests play the earbuds' part.
final class FakeTransport: ControlTransport {
    weak var delegate: (any ControlTransportDelegate)?
    var radio: RadioState = .unknown
    var maximumWriteLength = 214
    /// Peripherals the "system" knows; `connect` fails for others.
    var knownPeripherals: Set<UUID> = []

    private(set) var writes: [(characteristic: String, bytes: [UInt8])] = []
    private(set) var reads: [Set<String>] = []
    private(set) var connected: [UUID] = []
    private(set) var isScanning = false
    private(set) var cancelCount = 0

    func startScanning() { isScanning = true }
    func stopScanning() { isScanning = false }

    func connect(_ peripheral: UUID) -> Bool {
        guard knownPeripherals.contains(peripheral) else { return false }
        connected.append(peripheral)
        return true
    }

    func cancelConnection() { cancelCount += 1 }
    func write(_ bytes: [UInt8], to characteristic: String) { writes.append((characteristic, bytes)) }
    func read(_ characteristics: Set<String>) { reads.append(characteristics) }

    /// Frames written to the command characteristic, as hex.
    var commandFrames: [String] {
        writes.filter { $0.characteristic == QCYGATT.command }.map(\.bytes.hex)
    }

    func clearWrites() { writes = [] }

    // MARK: - Playing the earbuds

    func powerOn() {
        radio = .poweredOn
        delegate?.transportDidUpdateRadio(.poweredOn)
    }

    func advertise(_ device: DiscoveredPeripheral) {
        knownPeripherals.insert(device.id)
        delegate?.transportDidDiscover(device)
    }

    /// Simulates a full connection: connect, then services ready.
    func finishConnecting(_ id: UUID) {
        delegate?.transportDidConnect(id)
        delegate?.transportDidBecomeReady(id)
    }

    func notify(_ characteristic: String, _ hex: String) {
        delegate?.transportDidReceive([UInt8](hex: hex) ?? [], from: characteristic)
    }
}

/// The real model catalog plus the settings-list fixtures in `Tests/Fixtures/Panels`; never the network.
final class FakePanels: PanelProviding {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private let catalog = PanelRepository(resources: FakePanels.root.appending(path: "Resources"), cacheDirectory: nil,
                                          language: "en")
    /// Models whose list is "cached"; others need a download, which the fake answers from `downloads`.
    var cached: Set<UInt16> = [19786, 19745, 18863, 19393]
    var downloads: [UInt16: ControlPanel] = [:]
    private(set) var refreshRequests: [(UInt16, String?)] = []

    func model(_ vendorID: UInt16) -> ModelInfo? { catalog.model(vendorID) }
    func isSupported(_ vendorID: UInt16) -> Bool { catalog.isSupported(vendorID) }

    func panel(for vendorID: UInt16) -> ControlPanel? {
        cached.contains(vendorID) ? Self.fixture(vendorID) : nil
    }

    func refresh(vendorID: UInt16, firmware: String?) async -> ControlPanel? {
        refreshRequests.append((vendorID, firmware))
        return downloads[vendorID]
    }

    static func fixture(_ vendorID: UInt16) -> ControlPanel? {
        let url = root.appending(path: "Tests/Fixtures/Panels/\(vendorID).json")
        return (try? Data(contentsOf: url)).flatMap { try? ControlPanel(json: $0) }
    }
}

final class FakeAudio: AudioConnecting {
    var name: String? = "QCY MeloBuds Pro"
    var address: String? = "C4:AC:60:00:11:22"
    var isPaired = true
    var isConnected = false
    var isBusy = false
    var lastError: String?
    var pairedAddresses = ["c4-ac-60-00-11-22"]
    private(set) var focused: [QCYAdvertisement?] = []
    private(set) var actions: [String] = []

    func focus(on advertisement: QCYAdvertisement?) { focused.append(advertisement) }
    func refresh() { actions.append("refresh") }
    func connect() { actions.append("connect") }
    func disconnect() { actions.append("disconnect") }
    func openBluetoothSettings() { actions.append("settings") }
}

final class FakeFinder: FindTonePlaying {
    var isPlaying = false
    func toggle() { isPlaying.toggle() }
}

/// Fixtures captured from a MeloBuds Pro (model 0x4D4A, firmware 2.0.6).
enum Fixtures {
    static let meloBudsID = UUID()
    static let strangerID = UUID()

    /// The MeloBuds Pro advertisement: battery 90/88, Classic address …:AC:60:00:11:22.
    static let meloBuds = DiscoveredPeripheral(
        id: meloBudsID, name: "QCY MeloBuds Pro-APP",
        advertisement: advertisement("1c524d4a34a06a5a5800b88937ac846022110001ac8460554433"), rssi: -45)

    /// Another MeloBuds Pro nearby, not paired with this Mac.
    static let stranger = DiscoveredPeripheral(
        id: strangerID, name: "QCY MeloBuds Pro-APP",
        advertisement: advertisement("1c524d4a34a06a5a5800b88937ac8460aabbccddeeff6041c0d7"), rssi: -80)

    /// The full settings read of characteristic 1002.
    static let fullSettings =
        "FF302C0401030101080336360F09010217030200001001001601320401022301002401001F0205001D02060F190457513030"

    static func advertisement(_ hex: String) -> QCYAdvertisement {
        guard let bytes = [UInt8](hex: hex), let ad = QCYAdvertisement(manufacturerData: bytes) else {
            preconditionFailure("bad fixture")
        }
        return ad
    }

    /// A store with fakes, its defaults isolated in a fresh suite.
    static func makeStore() -> (HeadphonesStore, FakeTransport, FakeAudio) {
        let transport = FakeTransport()
        let audio = FakeAudio()
        let suite = "BudBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = HeadphonesStore(transport: transport, panels: FakePanels(), defaults: defaults)
        store.pairedAudioAddresses = { [audio] in audio.pairedAddresses }
        store.onAdvertisementChange = { [audio] ad in audio.focus(on: ad) }
        return (store, transport, audio)
    }

    /// A store whose panels have nothing cached, so every model's list must be downloaded.
    static func makeStoreWithoutCache() -> (HeadphonesStore, FakeTransport, FakePanels) {
        let transport = FakeTransport()
        let panels = FakePanels()
        panels.cached = []
        let suite = "BudBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = HeadphonesStore(transport: transport, panels: panels, defaults: defaults)
        store.pairedAudioAddresses = { ["c4-ac-60-00-11-22"] }
        return (store, transport, panels)
    }

    /// A store as it starts when BudBridge relaunches: the MeloBuds Pro is remembered from the last run.
    static func relaunchedStore(loadingTimeout: Duration = .seconds(8)) -> (HeadphonesStore, FakeTransport) {
        let transport = FakeTransport()
        transport.knownPeripherals.insert(meloBudsID)
        let suite = "BudBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(meloBudsID.uuidString, forKey: "peripheralID")
        defaults.set(Int(QCYAdvertisement.meloBudsPro), forKey: "vendorID")
        let store = HeadphonesStore(transport: transport, panels: FakePanels(), defaults: defaults,
                                    loadingTimeout: loadingTimeout)
        return (store, transport)
    }

    /// A store already connected to the MeloBuds Pro with its settings read.
    static func connectedStore() -> (HeadphonesStore, FakeTransport, FakeAudio) {
        let (store, transport, audio) = makeStore()
        transport.powerOn()
        transport.advertise(meloBuds)
        transport.finishConnecting(meloBudsID)
        transport.notify(QCYGATT.settings, fullSettings)
        transport.notify(QCYGATT.version, "020006020006")
        transport.clearWrites()
        return (store, transport, audio)
    }
}

// MARK: - AppPresence

final class FakePresenceHost: PresenceHost {
    var onMainWindowChange: ((Bool) -> Void)?
    var isMainWindowOpen = false
    var isMainWindowKey = false
    var onOtherWindowsChange: (() -> Void)?
    var hasOtherWindowsOpen = false
    private(set) var dockIcon: [Bool] = []
    private(set) var closeCount = 0

    func setDockIconVisible(_ visible: Bool) { dockIcon.append(visible) }

    func closeMainWindow() {
        closeCount += 1
        if isMainWindowOpen { userClosesWindow() }
    }

    func userOpensWindow() {
        isMainWindowOpen = true
        onMainWindowChange?(true)
    }

    func userClosesWindow() {
        isMainWindowOpen = false
        onMainWindowChange?(false)
    }

    func userOpensSettings() {
        hasOtherWindowsOpen = true
        onOtherWindowsChange?()
    }

    func userClosesSettings() {
        hasOtherWindowsOpen = false
        onOtherWindowsChange?()
    }
}

final class FakeLoginItem: LoginItem {
    struct Failure: Error {}

    var isEnabled = false
    var needsApproval = false
    var fails = false
    private(set) var openedSettings = false

    func setEnabled(_ enabled: Bool) throws {
        if fails { throw Failure() }
        isEnabled = enabled
    }

    func openSystemSettings() { openedSettings = true }
}

struct PresenceSetup {
    let presence: AppPresence
    let host: FakePresenceHost
    let login: FakeLoginItem
    let defaults: UserDefaults
}

/// An `AppPresence` with fakes, its defaults isolated in a fresh suite, and short timers.
func makePresence(grace: Duration = .milliseconds(20),
                  requestTimeout: Duration = .milliseconds(30)) -> PresenceSetup {
    let host = FakePresenceHost()
    let login = FakeLoginItem()
    let suite = "BudBridgeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    let presence = AppPresence(host: host, loginItem: login, defaults: defaults, gracePeriod: grace,
                                windowRequestTimeout: requestTimeout)
    return PresenceSetup(presence: presence, host: host, login: login, defaults: defaults)
}

/// Waits up to a second for `condition`, for timers such as the grace period.
func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
