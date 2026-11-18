import Foundation
import Observation
import OSLog
import QCYKit

/// Single source of truth for the connected QCY earbuds, driven by the model's settings list.
///
/// It owns the device state, the settings list and the connect policy, and turns user actions into
/// protocol commands. Bluetooth itself is behind `ControlTransport`, so the store has no CoreBluetooth
/// code and can be tested with a fake transport.
@Observable
final class HeadphonesStore {
    enum Phase: Equatable {
        case starting, bluetoothOff, unauthorized, searching, connecting, ready, paused
    }

    private(set) var phase: Phase = .starting
    private(set) var state = DeviceState()
    private(set) var panel: ControlPanel?
    private(set) var model: ModelInfo?
    private(set) var advertisement: QCYAdvertisement?
    private(set) var nearby: [NearbyDevice] = []
    /// Set while a change (LDAC, dual device, spatial EQ…) restarts the earbuds.
    private(set) var isRestarting = false
    /// When the battery levels were last reported, by the link or by an advertisement.
    private(set) var batteryUpdated: Date?
    /// The earbuds have reported their settings since they connected.
    private(set) var hasReadSettings = false
    /// The model's settings list is being downloaded from QCY (it isn't bundled with the app).
    private(set) var isDownloadingPanel = false
    /// The last download failed (usually no internet); `retryPanelDownload()` tries again.
    private(set) var panelDownloadFailed = false

    var isReady: Bool { phase == .ready }
    /// The screens are known (from the settings list) but the earbuds haven't reported their values yet:
    /// they're still connecting, or connected and answering the first read.
    var isLoadingSettings: Bool {
        guard loading.isOn, panel != nil else { return false }
        return switch phase {
        case .starting, .searching, .connecting: true
        case .ready: !hasReadSettings
        case .bluetoothOff, .unauthorized, .paused: false
        }
    }
    var modelID: UInt16? { vendorID }
    var family: ModelFamily? { vendorID.map(ModelFamily.init) }
    var modelName: String { model?.name ?? String(localized: "QCY Earbuds") }

    /// Whether this model has ever reported a charging-case level. Some (like the MeloBuds Pro)
    /// always send 0 for the case, so the case slot is hidden for them.
    var reportsCaseBattery: Bool {
        guard let vendorID else { return false }
        return state.battery?.chargingCase != nil || remembered.reportsCaseBattery(vendorID)
    }

    /// Battery levels that may be out of date: not connected, and nothing heard for a while
    /// (e.g. the case lid is closed, so the earbuds have stopped broadcasting).
    func isBatteryStale(at now: Date = .now) -> Bool {
        guard !isReady, let batteryUpdated else { return !isReady && state.battery != nil }
        return now.timeIntervalSince(batteryUpdated) > 30
    }

    /// Classic addresses paired with this Mac; a nearby device matching one is connected automatically.
    @ObservationIgnored var pairedAudioAddresses: () -> [String] = { [] }
    /// Called when the selected earbuds change, so the audio link can follow them.
    @ObservationIgnored var onAdvertisementChange: (QCYAdvertisement?) -> Void = { _ in }

    @ObservationIgnored private let transport: any ControlTransport
    @ObservationIgnored private let panels: any PanelProviding
    @ObservationIgnored private let remembered: RememberedEarbuds
    @ObservationIgnored private var peripheral: UUID?
    @ObservationIgnored private var vendorID: UInt16?
    @ObservationIgnored private var refreshedFirmware: String?
    @ObservationIgnored private var poller: Task<Void, Never>?
    /// Placeholders are shown until the earbuds report their settings, for at most the loading timeout.
    @ObservationIgnored private let loading: ExpiringFlag
    @ObservationIgnored private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "store")

    /// - Parameter loadingTimeout: How long to show the placeholder before explaining why the earbuds
    ///   haven't connected (they may be in their case or out of range).
    init(transport: any ControlTransport, panels: any PanelProviding, defaults: UserDefaults = .standard,
         loadingTimeout: Duration = .seconds(8)) {
        self.transport = transport
        self.panels = panels
        remembered = RememberedEarbuds(defaults: defaults)
        loading = ExpiringFlag(timeout: loadingTimeout)
        transport.delegate = self
        preloadKnownDevice()
    }

    /// Loads the remembered earbuds' model and cached settings list, so the sidebar and the page
    /// layouts appear at once instead of when the earbuds connect.
    private func preloadKnownDevice() {
        guard let known = remembered.last, let cached = panels.panel(for: known.vendor) else { return }
        vendorID = known.vendor
        model = panels.model(known.vendor)
        panel = cached
        loading.turnOn()
    }

    // MARK: - Connection control

    func resume() {
        guard phase == .paused || phase == .searching else { return }
        phase = .searching
        startDiscovery()
    }

    /// Drops the control link so the phone app can take over.
    func pause() {
        phase = .paused
        transport.stopScanning()
        transport.cancelConnection()
    }

    /// Connects to a device picked from the nearby list.
    func connect(to device: NearbyDevice) {
        guard device.isSupported else { return }
        adopt(device.advertisement)
        connect(peripheral: device.id)
    }

    /// Forgets the current earbuds and looks for others.
    func forget() {
        loading.turnOff()
        remembered.last = nil
        transport.cancelConnection()
        peripheral = nil
        resetDevice()
        onAdvertisementChange(nil)
        phase = .searching
        transport.startScanning()
    }

    /// Reads every characteristic the settings list needs and requests the records it lists.
    func refresh() {
        guard isReady else { return }
        // A read of 1002 returns most settings at once; the rest are requested one by one.
        var reads: Set<String> = [QCYGATT.settings, QCYGATT.battery, QCYGATT.version, QCYGATT.touchControls]
        if let eq = panel?.equalizer, eq.format == .legacy { reads.insert(eq.characteristic) }
        for group in panel?.touch?.groups ?? [] {
            for control in group.controls {
                if case .characteristic(let characteristic) = control.target { reads.insert(characteristic) }
            }
        }
        for item in panel?.settings ?? [] {
            switch item {
            case .toggle(let toggle) where toggle.stateCommand == nil:
                reads.insert(toggle.characteristic)
            case .choice(let choice):
                if case .characteristic(let characteristic) = choice.target { reads.insert(characteristic) }
            default:
                break
            }
        }
        transport.read(reads)
        for cmd in panel?.readCommands ?? [] {
            send(Record(CommandID.request, [cmd]))
        }
    }

    // MARK: - Settings

    func setNoise(_ value: Int) {
        apply(NoiseValue.record(value))
    }

    func set(_ toggle: ToggleItem, on: Bool) {
        if let cmd = toggle.stateCommand {
            state.records[cmd] = [on ? 1 : 0]
        } else {
            state.characteristics[toggle.characteristic] = on ? toggle.on : toggle.off
        }
        if toggle.restartsEarbuds { expectRestart() }
        transport.write(on ? toggle.on : toggle.off, to: toggle.characteristic)
    }

    func select(_ option: ChoiceOption, in choice: ChoiceItem) {
        switch choice.target {
        case .record(let cmd):
            apply(Record(cmd, option.payload))
        case .characteristic(let characteristic):
            state.characteristics[characteristic] = option.payload
            transport.write(option.payload, to: characteristic)
        }
    }

    func apply(preset: EQPreset) {
        guard let eq = panel?.equalizer else { return }
        if preset.warning != nil { expectRestart() }
        perform(eq.command(for: preset, slots: eqSlots))
    }

    func apply(customGains gains: [Double]) {
        guard let eq = panel?.equalizer else { return }
        perform(eq.customCommand(gains: gains, slots: eqSlots))
    }

    /// Re-sends a saved curve exactly as it was captured.
    func apply(effect: SoundEffect) {
        perform(effect.command)
    }

    func set(_ option: TouchOption, for control: TouchControl) {
        switch control.target {
        case .characteristic(let characteristic):
            state.characteristics[characteristic] = option.value
            transport.write(option.value, to: characteristic)
        case .event(let eventID):
            setTouchAction(option.value[0], for: eventID)
        }
    }

    func set(balance value: Int) {
        apply(Command.balance(value))
    }

    func set(wearDetection value: WearDetection) {
        apply(Command.wearDetection(value))
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(Command.rename(trimmed, maxLength: panel?.rename?.maxLength ?? 30))
    }

    func run(_ action: ActionItem) {
        transport.write(action.bytes, to: action.characteristic)
    }

    /// Tries the settings-list download again after a failure.
    func retryPanelDownload() {
        panelDownloadFailed = false
        downloadPanelIfNeeded()
    }

    // MARK: - Private: commands

    private var eqSlots: Int {
        EQConfiguration.slots(forWriteLength: transport.maximumWriteLength)
    }

    /// Updates the state right away (optimistic UI), then sends the record.
    private func apply(_ record: Record) {
        state.apply(record)
        send(record)
    }

    private func send(_ record: Record) {
        transport.write(Frame.encode(record), to: QCYGATT.command)
    }

    private func perform(_ command: EQCommand) {
        switch command {
        case .record(let record):
            apply(record)
        case .characteristic(let characteristic, let bytes):
            state.characteristics[characteristic] = bytes
            transport.write(bytes, to: characteristic)
        }
    }

    private func setTouchAction(_ action: UInt8, for eventID: UInt8) {
        var pairs = state.characteristics[QCYGATT.touchControls] ?? []
        if let index = stride(from: 0, to: pairs.count - 1, by: 2).first(where: { pairs[$0] == eventID }) {
            pairs[index + 1] = action
        } else {
            pairs += [eventID, action]
        }
        state.characteristics[QCYGATT.touchControls] = pairs
        guard let family else { return }
        if family.isZR {
            // ZR firmware takes the whole map, with its own gesture numbering.
            let wire = stride(from: 0, to: pairs.count - 1, by: 2).flatMap { [family.wireGesture(pairs[$0]), pairs[$0 + 1]] }
            transport.write(wire, to: QCYGATT.touchControls)
        } else {
            let sent: UInt8 = action == 0 && family.sendsNoActionAsFF && firmwareAtLeast(1, 1, 0) ? 0xFF : action
            transport.write([eventID, sent], to: QCYGATT.touchControls)
        }
    }

    private func firmwareAtLeast(_ major: Int, _ minor: Int, _ patch: Int) -> Bool {
        guard let parts = state.firmware?.left.split(separator: ".").compactMap({ Int($0) }), parts.count == 3 else {
            return false
        }
        return (parts[0], parts[1], parts[2]) >= (major, minor, patch)
    }

    private func expectRestart() {
        isRestarting = true
        Task {
            try? await Task.sleep(for: .seconds(15))
            isRestarting = false
        }
    }

    // MARK: - Private: discovery and device

    private func startDiscovery() {
        guard transport.radio == .poweredOn, phase != .paused else { return }
        if let known = remembered.last, transport.connect(known.peripheral) {
            vendorID = known.vendor
            peripheral = known.peripheral
            if phase != .ready { phase = .connecting }
        }
        transport.startScanning()
    }

    private func adopt(_ ad: QCYAdvertisement) {
        if vendorID != ad.vendorID { resetDevice() }
        advertisement = ad
        vendorID = ad.vendorID
        model = panels.model(ad.vendorID)
        panel = panels.panel(for: ad.vendorID)
        if state.battery == nil { updateBattery(ad.battery) }
        onAdvertisementChange(ad)
        downloadPanelIfNeeded()
    }

    private func resetDevice() {
        state = DeviceState()
        hasReadSettings = false
        panel = nil
        model = nil
        advertisement = nil
        refreshedFirmware = nil
    }

    private func connect(peripheral id: UUID) {
        guard transport.connect(id) else { return }
        peripheral = id
        if phase != .ready { phase = .connecting }
    }

    /// Downloads the latest settings list when none is cached yet, so the screens can appear before
    /// the firmware is known. The firmware-specific list follows in `refreshPanel(firmware:)`.
    private func downloadPanelIfNeeded() {
        guard panel == nil, !isDownloadingPanel, let vendorID, panels.isSupported(vendorID) else { return }
        isDownloadingPanel = true
        panelDownloadFailed = false
        Task {
            let fresh = await panels.refresh(vendorID: vendorID, firmware: state.firmware?.left)
            isDownloadingPanel = false
            guard self.vendorID == vendorID else { return }
            if let fresh {
                panel = fresh
                refresh()
            } else {
                panelDownloadFailed = panel == nil
            }
        }
    }

    /// Once the firmware is known, fetch the settings list QCY serves for it (as the phone app does).
    private func refreshPanel(firmware: FirmwareVersion) {
        guard let vendorID, refreshedFirmware != firmware.left else { return }
        refreshedFirmware = firmware.left
        Task {
            guard let fresh = await panels.refresh(vendorID: vendorID, firmware: firmware.left),
                  self.vendorID == vendorID else { return }
            panel = fresh
            refresh()
        }
    }

    private func updateBattery(_ battery: BatteryStatus) {
        state.battery = battery
        batteryUpdated = .now
        if battery.chargingCase != nil, let vendorID {
            remembered.rememberCaseBattery(vendorID)
        }
    }

    private func startBatteryPolling() {
        poller?.cancel()
        // Battery notifies on change, but a slow poll keeps the case level fresh like the phone app does.
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.transport.read([QCYGATT.battery])
            }
        }
    }
}

// MARK: - ControlTransportDelegate

extension HeadphonesStore: ControlTransportDelegate {
    func transportDidUpdateRadio(_ radio: RadioState) {
        switch radio {
        case .poweredOn:
            if phase != .paused {
                phase = .searching
                startDiscovery()
            }
        case .unauthorized: phase = .unauthorized
        case .poweredOff, .unknown: phase = .bluetoothOff
        }
    }

    func transportDidDiscover(_ discovered: DiscoveredPeripheral) {
        let ad = discovered.advertisement
        let info = panels.model(ad.vendorID)
        let name = info?.name ?? discovered.name?.replacingOccurrences(of: "-APP", with: "") ?? String(localized: "QCY device")
        let device = NearbyDevice(id: discovered.id, name: name, advertisement: ad, model: info,
                                  isSupported: panels.isSupported(ad.vendorID), rssi: discovered.rssi)
        if let index = nearby.firstIndex(where: { $0.id == device.id }) { nearby[index] = device } else { nearby.append(device) }

        // Like the phone app, keep the battery fresh from our earbuds' broadcasts while not connected.
        let isOurs = discovered.id == peripheral || discovered.id == remembered.last?.peripheral
        if isOurs, !isReady { updateBattery(ad.battery) }

        guard phase == .searching || phase == .starting, device.isSupported else { return }
        // Connect automatically only to earbuds this Mac knows: the last ones used, or ones paired for audio.
        let isKnown = remembered.last?.peripheral == discovered.id
        let isPaired = pairedAudioAddresses().contains { ad.matchesClassicAddress($0) }
        guard isKnown || isPaired else { return }
        adopt(ad)
        connect(peripheral: discovered.id)
    }

    func transportDidConnect(_ id: UUID) {
        if let vendorID { remembered.last = (id, vendorID) }
    }

    func transportDidBecomeReady(_ id: UUID) {
        if let vendorID {
            if model == nil { model = panels.model(vendorID) }
            if panel == nil { panel = panels.panel(for: vendorID) }
        }
        downloadPanelIfNeeded()
        if hasReadSettings { loading.turnOff() } else { loading.turnOn() }
        phase = .ready
        isRestarting = false
        transport.stopScanning()
        nearby = []
        refresh()
        startBatteryPolling()
    }

    func transportDidFailToConnect(_ id: UUID) {
        guard phase != .paused else { return }
        phase = .searching
        transport.startScanning()
    }

    func transportDidDisconnect(_ id: UUID) {
        poller?.cancel()
        guard phase != .paused, peripheral == id else { return }
        phase = .searching
        // A pending connect completes as soon as the earbuds advertise again (after a restart, or
        // when the phone releases them).
        transport.connect(id)
        transport.startScanning()
    }

    func transportDidReceive(_ value: [UInt8], from uuid: String) {
        log.debug("RX \(uuid, privacy: .public) \(value.hex, privacy: .public)")
        switch uuid {
        case QCYGATT.settings:
            if !hasReadSettings {
                hasReadSettings = true
                loading.turnOff()
            }
            do { try state.apply(frame: value) } catch {
                log.error("bad frame \(value.hex, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        case QCYGATT.battery:
            if let battery = BatteryStatus(bytes: value) { updateBattery(battery) }
        case QCYGATT.version:
            state.firmware = FirmwareVersion(bytes: value)
            if let firmware = state.firmware { refreshPanel(firmware: firmware) }
        case QCYGATT.touchControls:
            if let family, family.isZR {
                state.characteristics[uuid] = stride(from: 0, to: value.count - 1, by: 2)
                    .flatMap { [family.appGesture(value[$0]), value[$0 + 1]] }
            } else {
                state.characteristics[uuid] = value
            }
        default:
            state.characteristics[uuid] = value
        }
    }
}
