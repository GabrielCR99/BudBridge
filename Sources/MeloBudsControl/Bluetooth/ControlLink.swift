import CoreBluetooth
import Foundation
import Observation
import OSLog
import QCYKit

/// BLE control channel to the earbuds (GATT service A001).
///
/// The earbuds expose this on a separate LE identity ("QCY MeloBuds Pro-APP"). They accept a single
/// LE control connection, so while the phone app holds it the Mac cannot connect (and vice versa).
@Observable
final class ControlLink: NSObject {
    enum Phase: Equatable {
        case starting
        case bluetoothOff
        case unauthorized
        case searching
        case connecting
        case ready
        case paused
    }

    private(set) var phase: Phase = .starting
    private(set) var settings = DeviceSettings()
    private(set) var battery: BatteryStatus?
    private(set) var firmware: FirmwareVersion?
    private(set) var touchControls: [TouchGesture: TouchAction] = [:]
    /// Set while LDAC / dual-device changes restart the earbuds.
    private(set) var isRestarting = false

    var isReady: Bool { phase == .ready }

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var characteristics: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored private let outbox: AsyncStream<Packet>.Continuation
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "dev.melobuds.control", category: "ble")

    @ObservationIgnored
    private var knownPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: "peripheralID").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "peripheralID") }
    }

    private struct Packet: Sendable {
        var characteristic: CBUUID
        var bytes: [UInt8]
    }

    override init() {
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

    func refresh() {
        guard let peripheral, isReady else { return }
        for uuid in [QCYGATT.settings, QCYGATT.battery, QCYGATT.version, QCYGATT.touchControls] {
            if let characteristic = characteristics[CBUUID(string: uuid)] {
                peripheral.readValue(for: characteristic)
            }
        }
        send(Command.request(.multiEQ2))
    }

    // MARK: Settings

    func set(noiseControl value: NoiseControl) {
        settings.noiseControl = value
        send(Command.noiseControl(value))
    }

    func set(lowLatency on: Bool) {
        settings.lowLatency = on
        send(Command.toggle(.lowLatency, on))
    }

    /// LDAC and dual-device connection are mutually exclusive; the earbuds restart to apply either.
    func set(ldac on: Bool) {
        settings.ldac = on
        if on { settings.dualDevice = false }
        expectRestart()
        send(Command.toggle(.ldac, on))
    }

    func set(dualDevice on: Bool) {
        settings.dualDevice = on
        if on { settings.ldac = false }
        expectRestart()
        send(Command.toggle(.dualDevice, on))
    }

    func set(sleepMode on: Bool) {
        settings.sleepMode = on
        send(Command.toggle(.sleepMode, on))
    }

    func set(balance value: Int) {
        settings.balance = value
        send(Command.balance(value))
    }

    func set(beepVolume value: BeepVolume) {
        settings.beepVolume = value
        send(Command.beepVolume(value))
    }

    func set(promptLanguage value: PromptLanguage) {
        settings.promptLanguage = value
        send(Command.promptLanguage(value))
    }

    func set(autoPowerOff value: AutoPowerOff) {
        settings.autoPowerOff = value
        send(Command.autoPowerOff(value))
    }

    func set(wearDetection value: WearDetection) {
        settings.wearDetection = value
        send(Command.wearDetection(value))
    }

    func apply(preset: EQPreset) {
        if preset.warning != nil { settings.ldac = false; expectRestart() }
        apply(equalizer: preset.configuration)
    }

    func apply(customGains gains: [Double]) {
        apply(equalizer: GraphicEQ.configuration(gains: gains))
    }

    private func apply(equalizer: EQConfiguration) {
        settings.equalizer = equalizer
        send(Command.equalizer(equalizer))
    }

    func set(_ action: TouchAction, for gesture: TouchGesture) {
        touchControls[gesture] = action
        enqueue(TouchControls.encode([gesture: action]), to: QCYGATT.touchControls)
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.deviceName = trimmed
        send(Command.rename(trimmed))
    }

    func resetToDefaults() { send(Command.resetToDefaults) }
    func factoryReset() { send(Command.factoryReset) }

    // MARK: Transport

    private func send(_ records: Record...) {
        enqueue(Frame.encode(records), to: QCYGATT.command)
    }

    private func enqueue(_ bytes: [UInt8], to characteristic: String) {
        outbox.yield(Packet(characteristic: CBUUID(string: characteristic), bytes: bytes))
    }

    private func transmit(_ packet: Packet) {
        guard let peripheral, let characteristic = characteristics[packet.characteristic] else {
            log.notice("dropping \(packet.bytes.hex, privacy: .public): not connected")
            return
        }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        guard packet.bytes.count <= peripheral.maximumWriteValueLength(for: type) else {
            log.error("frame of \(packet.bytes.count) bytes exceeds the negotiated MTU")
            return
        }
        log.debug("TX \(packet.characteristic.uuidString, privacy: .public) \(packet.bytes.hex, privacy: .public)")
        peripheral.writeValue(Data(packet.bytes), for: characteristic, type: type)
    }

    private func expectRestart() {
        isRestarting = true
        Task {
            try? await Task.sleep(for: .seconds(15))
            isRestarting = false
        }
    }

    private func startDiscovery() {
        guard central.state == .poweredOn, phase != .paused else { return }
        if let id = knownPeripheralID, let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
        }
        for candidate in central.retrieveConnectedPeripherals(withServices: [CBUUID(string: QCYGATT.service)])
        where candidate.name?.localizedCaseInsensitiveContains("MeloBuds") == true {
            connect(candidate)
            return
        }
        // A001 is not in the advertisement, so scan everything and match QCY manufacturer data.
        central.scanForPeripherals(withServices: nil)
    }

    private func connect(_ candidate: CBPeripheral) {
        guard peripheral?.identifier != candidate.identifier || candidate.state == .disconnected else { return }
        peripheral = candidate
        candidate.delegate = self
        if phase != .ready { phase = .connecting }
        central.connect(candidate)
    }

    private func didBecomeReady(_ peripheral: CBPeripheral) {
        phase = .ready
        isRestarting = false
        refresh()
        poller?.cancel()
        // Battery notifies on change, but a slow poll keeps the case level fresh like the phone app does.
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, let c = self.characteristics[CBUUID(string: QCYGATT.battery)] else { continue }
                self.peripheral?.readValue(for: c)
            }
        }
    }

    private func handle(_ value: [UInt8], from characteristic: CBUUID) {
        log.debug("RX \(characteristic.uuidString, privacy: .public) \(value.hex, privacy: .public)")
        switch characteristic.uuidString {
        case QCYGATT.settings:
            do {
                for record in try Frame.decode(value) { settings.apply(record) }
            } catch {
                log.error("bad frame \(value.hex): \(String(describing: error))")
            }
        case QCYGATT.battery:
            battery = BatteryStatus(bytes: value) ?? battery
        case QCYGATT.version:
            firmware = FirmwareVersion(bytes: value)
        case QCYGATT.touchControls:
            touchControls = TouchControls.decode(value)
        default:
            break
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
        case .poweredOff, .resetting: phase = .bluetoothOff
        default: phase = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let ad = QCYAdvertisement(manufacturerData: data),
              ad.vendorID == QCYAdvertisement.meloBudsPro else { return }
        if battery == nil { battery = ad.battery }
        central.stopScan()
        knownPeripheralID = peripheral.identifier
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("connected to \(peripheral.identifier)")
        knownPeripheralID = peripheral.identifier
        peripheral.discoverServices([CBUUID(string: QCYGATT.service)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown")")
        guard phase != .paused else { return }
        phase = .searching
        central.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        log.info("disconnected: \(error?.localizedDescription ?? "requested")")
        characteristics = [:]
        poller?.cancel()
        guard phase != .paused else { return }
        phase = .searching
        // A pending connect completes as soon as the earbuds advertise again (e.g. after a restart
        // or when the phone releases them).
        central.connect(peripheral)
        central.scanForPeripherals(withServices: nil)
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
            characteristics[characteristic.uuid] = characteristic
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if characteristics[CBUUID(string: QCYGATT.command)] != nil {
            didBecomeReady(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard error == nil, let value = characteristic.value else { return }
        handle(Array(value), from: characteristic.uuid)
    }
}
