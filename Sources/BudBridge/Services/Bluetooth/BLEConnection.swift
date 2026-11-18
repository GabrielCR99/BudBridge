import CoreBluetooth
import Foundation
import OSLog
import QCYKit

/// CoreBluetooth implementation of `ControlTransport`: scanning, the GATT connection to service A001,
/// characteristic reads and paced writes. It knows nothing about settings or connect policy.
final class BLEConnection: NSObject, ControlTransport {
    weak var delegate: (any ControlTransportDelegate)?
    private(set) var radio: RadioState = .unknown

    var maximumWriteLength: Int {
        peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 20
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private let outbox: AsyncStream<Packet>.Continuation
    private var writer: Task<Void, Never>?
    private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "ble")

    private struct Packet: Sendable {
        var characteristic: String
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

    // MARK: - ControlTransport

    func startScanning() {
        // A001 is not in the advertisement, so scan everything and match QCY manufacturer data.
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        central?.stopScan()
    }

    @discardableResult
    func connect(_ id: UUID) -> Bool {
        guard let central, let candidate = central.retrievePeripherals(withIdentifiers: [id]).first else { return false }
        if let peripheral, peripheral.identifier != id {
            central.cancelPeripheralConnection(peripheral)
        }
        guard peripheral?.identifier != id || candidate.state == .disconnected else { return true }
        peripheral = candidate
        candidate.delegate = self
        central.connect(candidate)
        return true
    }

    func cancelConnection() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    func write(_ bytes: [UInt8], to characteristic: String) {
        outbox.yield(Packet(characteristic: characteristic, bytes: bytes))
    }

    func read(_ uuids: Set<String>) {
        guard let peripheral else { return }
        for uuid in uuids {
            if let characteristic = characteristics[uuid], characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    // MARK: - Private

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
}

// MARK: - CBCentralManagerDelegate (delivered on the main queue)

extension BLEConnection: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        radio = switch central.state {
        case .poweredOn: .poweredOn
        case .unauthorized: .unauthorized
        case .unknown: .unknown
        default: .poweredOff
        }
        delegate?.transportDidUpdateRadio(radio)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let ad = QCYAdvertisement(manufacturerData: data) else { return }
        delegate?.transportDidDiscover(DiscoveredPeripheral(
            id: peripheral.identifier, name: peripheral.name, advertisement: ad, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("connected to \(peripheral.identifier)")
        delegate?.transportDidConnect(peripheral.identifier)
        peripheral.discoverServices([CBUUID(string: QCYGATT.service)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        delegate?.transportDidFailToConnect(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        log.info("disconnected: \(error?.localizedDescription ?? "requested", privacy: .public)")
        characteristics = [:]
        delegate?.transportDidDisconnect(peripheral.identifier)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEConnection: @MainActor CBPeripheralDelegate {
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
        delegate?.transportDidBecomeReady(peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard error == nil, let value = characteristic.value else { return }
        delegate?.transportDidReceive(Array(value), from: characteristic.uuid.uuidString)
    }
}
