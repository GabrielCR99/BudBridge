import CoreBluetooth
import Foundation
import Observation
import OSLog
import QCYKit

/// BLE control channel to QCY earbuds (GATT service A001), driven by the model's settings list.
///
/// QCY earbuds expose this on a separate LE identity ("<name>-APP") and accept a single LE controller,
/// so while the phone app holds it the Mac cannot connect (and vice versa).
@Observable
final class ControlLink: NSObject {
    enum Phase: Equatable {
        case starting, bluetoothOff, unauthorized, searching, connecting, ready, paused
    }

    /// A QCY device seen in a scan.
    struct Nearby: Identifiable, Equatable {
        var id: UUID
        var name: String
        var advertisement: QCYAdvertisement
        var model: ModelInfo?
        var isSupported: Bool
        var rssi: Int

        static func == (a: Nearby, b: Nearby) -> Bool { a.id == b.id && a.rssi == b.rssi && a.name == b.name }
    }

    private(set) var phase: Phase = .starting
    private(set) var state = DeviceState()
    private(set) var panel: ControlPanel?
    private(set) var model: ModelInfo?
    private(set) var advertisement: QCYAdvertisement?
    private(set) var nearby: [Nearby] = []
    /// Set while a change (LDAC, dual device, spatial EQ…) restarts the earbuds.
    private(set) var isRestarting = false
    /// Whether this model has ever reported a charging-case level. Some (like the MeloBuds Pro)
    /// always send 0 for the case, so the case slot is hidden for them.
    var reportsCaseBattery: Bool {
        guard let vendorID else { return false }
        return state.battery?.chargingCase != nil
            || UserDefaults.standard.bool(forKey: "reportsCaseBattery.\(vendorID)")
    }

    /// When the battery levels were last reported, by the link or by an advertisement.
    private(set) var batteryUpdated: Date?

    /// Battery levels that may be out of date: not connected, and nothing heard for a while
    /// (e.g. the case lid is closed, so the earbuds have stopped broadcasting).
    func isBatteryStale(at now: Date = .now) -> Bool {
        guard !isReady, let batteryUpdated else { return !isReady && state.battery != nil }
        return now.timeIntervalSince(batteryUpdated) > 30
    }

    var isReady: Bool { phase == .ready }
    var family: ModelFamily? { vendorID.map(ModelFamily.init) }
    var modelID: UInt16? { vendorID }
    var modelName: String { model?.name ?? String(localized: "QCY Earbuds") }

    /// Classic addresses paired with this Mac; a nearby device matching one is connected automatically.
    @ObservationIgnored var pairedAudioAddresses: () -> [String] = { [] }

    @ObservationIgnored let panels: PanelStore
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var characteristics: [String: CBCharacteristic] = [:]
    @ObservationIgnored private var vendorID: UInt16?
    @ObservationIgnored private var refreshedFirmware: String?
    @ObservationIgnored private let outbox: AsyncStream<Packet>.Continuation
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "ble")

    @ObservationIgnored
    private var known: (peripheral: UUID, vendor: UInt16)? {
        get {
            let d = UserDefaults.standard
            guard let id = d.string(forKey: "peripheralID").flatMap(UUID.init(uuidString:)),
                  let vendor = d.object(forKey: "vendorID") as? Int else { return nil }
            return (id, UInt16(vendor))
        }
        set {
            UserDefaults.standard.set(newValue?.peripheral.uuidString, forKey: "peripheralID")
            UserDefaults.standard.set(newValue.map { Int($0.vendor) }, forKey: "vendorID")
        }
    }

    private struct Packet: Sendable {
        var characteristic: String
        var bytes: [UInt8]
    }

    init(panels: PanelStore) {
        self.panels = panels
        let (stream, continuation) = AsyncStream.makeStream(of: Packet.self)
        outbox = continuation
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // The earbuds drop writes that arrive back-to-back; the phone app spaces them ~50 ms apart.
        writer = Task { [weak self] in
            for await packet in stream {
                self?.transmit(packet)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    // MARK: Connection control

    func resume() {
        guard phase == .paused || phase == .searching else { return }
        phase = .searching
        startDiscovery()
    }

    /// Drops the control link so the phone app can take over.
    func pause() {
        phase = .paused
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    /// Connects to a device picked from the nearby list.
    func connect(to device: Nearby) {
        guard device.isSupported,
              let candidate = central.retrievePeripherals(withIdentifiers: [device.id]).first else { return }
        if let peripheral, peripheral.identifier != candidate.identifier {
            central.cancelPeripheralConnection(peripheral)
        }
        adopt(device.advertisement)
        connect(candidate)
    }

    /// Forgets the current earbuds and looks for others.
    func forget() {
        known = nil
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        resetDevice()
        phase = .searching
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func refresh() {
        guard let peripheral, isReady else { return }
        // A read of 1002 returns most settings at once; the rest are requested one by one.
        var reads = [QCYGATT.settings, QCYGATT.battery, QCYGATT.version, QCYGATT.touchControls]
        if let eq = panel?.equalizer, eq.format == .legacy { reads.append(eq.characteristic) }
        for group in panel?.touch?.groups ?? [] {
            for control in group.controls { if case .characteristic(let c) = control.target { reads.append(c) } }
        }
        for item in panel?.settings ?? [] {
            switch item {
            case .toggle(let t) where t.stateCommand == nil: reads.append(t.characteristic)
            case .choice(let c): if case .characteristic(let ch) = c.target { reads.append(ch) }
            default: break
            }
        }
        for uuid in Set(reads) {
            if let c = characteristics[uuid], c.properties.contains(.read) { peripheral.readValue(for: c) }
        }
        for cmd in panel?.readCommands ?? [] {
            send(Record(CommandID.request, [cmd]))
        }
    }

    // MARK: Settings

    func setNoise(_ value: Int) {
        let record = NoiseValue.record(value)
        state.apply(record)
        send(record)
    }

    func set(_ toggle: ToggleItem, on: Bool) {
        if let cmd = toggle.stateCommand {
            state.records[cmd] = [on ? 1 : 0]
        } else {
            state.characteristics[toggle.characteristic] = on ? toggle.on : toggle.off
        }
        if toggle.restartsEarbuds { expectRestart() }
        enqueue(on ? toggle.on : toggle.off, to: toggle.characteristic)
    }

    func select(_ option: ChoiceOption, in choice: ChoiceItem) {
        switch choice.target {
        case .record(let cmd):
            let record = Record(cmd, option.payload)
            state.apply(record)
            send(record)
        case .characteristic(let c):
            state.characteristics[c] = option.payload
            enqueue(option.payload, to: c)
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

    private func perform(_ command: EQCommand) {
        switch command {
        case .record(let record):
            state.apply(record)
            send(record)
        case .characteristic(let c, let bytes):
            state.characteristics[c] = bytes
            enqueue(bytes, to: c)
        }
    }

    func set(_ option: TouchOption, for control: TouchControl) {
        switch control.target {
        case .characteristic(let c):
            state.characteristics[c] = option.value
            enqueue(option.value, to: c)
        case .event(let eventID):
            var pairs = state.characteristics[QCYGATT.touchControls] ?? []
            if let i = stride(from: 0, to: pairs.count - 1, by: 2).first(where: { pairs[$0] == eventID }) {
                pairs[i + 1] = option.value[0]
            } else {
                pairs += [eventID, option.value[0]]
            }
            state.characteristics[QCYGATT.touchControls] = pairs
            guard let family else { return }
            if family.isZR {
                // ZR firmware takes the whole map, with its own gesture numbering.
                let wire = stride(from: 0, to: pairs.count - 1, by: 2).flatMap { [family.wireGesture(pairs[$0]), pairs[$0 + 1]] }
                enqueue(wire, to: QCYGATT.touchControls)
            } else {
                var action = option.value[0]
                if action == 0, family.sendsNoActionAsFF, firmwareAtLeast(1, 1, 0) { action = 0xFF }
                enqueue([eventID, action], to: QCYGATT.touchControls)
            }
        }
    }

    func set(balance value: Int) {
        let record = Command.balance(value)
        state.apply(record)
        send(record)
    }

    func set(wearDetection value: WearDetection) {
        let record = Command.wearDetection(value)
        state.apply(record)
        send(record)
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = Command.rename(trimmed, maxLength: panel?.rename?.maxLength ?? 30)
        state.apply(record)
        send(record)
    }

    func run(_ action: ActionItem) {
        enqueue(action.bytes, to: action.characteristic)
    }

    // MARK: Transport

    private var eqSlots: Int {
        EQConfiguration.slots(forWriteLength: peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 20)
    }

    private func send(_ record: Record) {
        enqueue(Frame.encode(record), to: QCYGATT.command)
    }

    private func enqueue(_ bytes: [UInt8], to characteristic: String) {
        outbox.yield(Packet(characteristic: characteristic, bytes: bytes))
    }

    private func transmit(_ packet: Packet) {
        guard let peripheral, let characteristic = characteristics[packet.characteristic] else {
            log.notice("dropping \(packet.bytes.hex, privacy: .public) for \(packet.characteristic, privacy: .public): not available")
            return
        }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        guard packet.bytes.count <= peripheral.maximumWriteValueLength(for: type) else {
            log.error("\(packet.bytes.count) bytes exceed the negotiated MTU")
            return
        }
        log.debug("TX \(packet.characteristic, privacy: .public) \(packet.bytes.hex, privacy: .public)")
        peripheral.writeValue(Data(packet.bytes), for: characteristic, type: type)
    }

    private func firmwareAtLeast(_ major: Int, _ minor: Int, _ patch: Int) -> Bool {
        guard let parts = state.firmware?.left.split(separator: ".").compactMap({ Int($0) }), parts.count == 3 else { return false }
        return (parts[0], parts[1], parts[2]) >= (major, minor, patch)
    }

    private func expectRestart() {
        isRestarting = true
        Task {
            try? await Task.sleep(for: .seconds(15))
            isRestarting = false
        }
    }

    // MARK: Discovery

    private func startDiscovery() {
        guard central.state == .poweredOn, phase != .paused else { return }
        if let known, let peripheral = central.retrievePeripherals(withIdentifiers: [known.peripheral]).first {
            vendorID = known.vendor
            connect(peripheral)
        }
        // A001 is not in the advertisement, so scan everything and match QCY manufacturer data.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func adopt(_ ad: QCYAdvertisement) {
        advertisement = ad
        if vendorID != ad.vendorID { resetDevice() }
        vendorID = ad.vendorID
        model = panels.model(ad.vendorID)
        panel = panels.panel(for: ad.vendorID)
        if state.battery == nil { updateBattery(ad.battery) }
    }

    private func resetDevice() {
        state = DeviceState()
        panel = nil
        model = nil
        advertisement = nil
        refreshedFirmware = nil
    }

    private func connect(_ candidate: CBPeripheral) {
        guard peripheral?.identifier != candidate.identifier || candidate.state == .disconnected else { return }
        peripheral = candidate
        candidate.delegate = self
        if phase != .ready { phase = .connecting }
        central.connect(candidate)
    }

    private func didBecomeReady() {
        if let vendorID {
            if model == nil { model = panels.model(vendorID) }
            if panel == nil { panel = panels.panel(for: vendorID) }
        }
        phase = .ready
        isRestarting = false
        central.stopScan()
        nearby = []
        refresh()
        poller?.cancel()
        // Battery notifies on change, but a slow poll keeps the case level fresh like the phone app does.
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, let c = self.characteristics[QCYGATT.battery] else { continue }
                self.peripheral?.readValue(for: c)
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
            UserDefaults.standard.set(true, forKey: "reportsCaseBattery.\(vendorID)")
        }
    }

    private func handle(_ value: [UInt8], from uuid: String) {
        log.debug("RX \(uuid, privacy: .public) \(value.hex, privacy: .public)")
        switch uuid {
        case QCYGATT.settings:
            do { try state.apply(frame: value) } catch {
                log.error("bad frame \(value.hex, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        case QCYGATT.battery:
            if let battery = BatteryStatus(bytes: value) { updateBattery(battery) }
        case QCYGATT.version:
            state.firmware = FirmwareVersion(bytes: value)
            if let firmware = state.firmware { refreshPanel(firmware: firmware) }
        case QCYGATT.touchControls where family?.isZR == true:
            let f = family!
            state.characteristics[uuid] = stride(from: 0, to: value.count - 1, by: 2).flatMap { [f.appGesture(value[$0]), value[$0 + 1]] }
        default:
            state.characteristics[uuid] = value
        }
    }
}

// MARK: - CoreBluetooth delegates (delivered on the main queue)

extension ControlLink: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if phase != .paused {
                phase = .searching
                startDiscovery()
            }
        case .unauthorized: phase = .unauthorized
        default: phase = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let ad = QCYAdvertisement(manufacturerData: data) else { return }
        let info = panels.model(ad.vendorID)
        let name = info?.name ?? peripheral.name?.replacingOccurrences(of: "-APP", with: "") ?? String(localized: "QCY device")
        let device = Nearby(id: peripheral.identifier, name: name, advertisement: ad, model: info,
                            isSupported: panels.isSupported(ad.vendorID), rssi: RSSI.intValue)
        if let i = nearby.firstIndex(where: { $0.id == device.id }) { nearby[i] = device } else { nearby.append(device) }

        // Like the phone app, keep the battery fresh from our earbuds' broadcasts while not connected.
        let isOurs = peripheral.identifier == self.peripheral?.identifier || peripheral.identifier == known?.peripheral
        if isOurs, !isReady { updateBattery(ad.battery) }

        guard phase == .searching || phase == .starting, device.isSupported else { return }
        // Connect automatically only to earbuds this Mac knows: the last ones used, or ones paired for audio.
        let isKnown = known?.peripheral == peripheral.identifier
        let isPaired = pairedAudioAddresses().contains { ad.matchesClassicAddress($0) }
        guard isKnown || isPaired else { return }
        adopt(ad)
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("connected to \(peripheral.identifier)")
        if let vendorID { known = (peripheral.identifier, vendorID) }
        peripheral.discoverServices([CBUUID(string: QCYGATT.service)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        guard phase != .paused else { return }
        phase = .searching
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        log.info("disconnected: \(error?.localizedDescription ?? "requested", privacy: .public)")
        characteristics = [:]
        poller?.cancel()
        guard phase != .paused, self.peripheral?.identifier == peripheral.identifier else { return }
        phase = .searching
        // A pending connect completes as soon as the earbuds advertise again (after a restart, or
        // when the phone releases them).
        central.connect(peripheral)
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
}

extension ControlLink: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: QCYGATT.service) }) else {
            log.error("service A001 not found")
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: (any Error)?) {
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid.uuidString] = characteristic
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        didBecomeReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard error == nil, let value = characteristic.value else { return }
        handle(Array(value), from: characteristic.uuid.uuidString)
    }
}
