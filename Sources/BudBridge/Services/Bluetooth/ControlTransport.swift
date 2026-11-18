import Foundation
import QCYKit

/// State of the Mac's Bluetooth radio, as far as the app can use it.
enum RadioState: Equatable {
    case unknown
    case poweredOn
    case poweredOff
    case unauthorized
}

/// A QCY device heard in a scan.
struct DiscoveredPeripheral: Equatable {
    var id: UUID
    var name: String?
    var advertisement: QCYAdvertisement
    var rssi: Int
}

/// The Bluetooth LE operations `HeadphonesStore` needs.
///
/// `BLEConnection` implements it with CoreBluetooth; tests use a fake, so the store's logic
/// (state, commands, connect policy) runs without a radio.
protocol ControlTransport: AnyObject {
    var delegate: (any ControlTransportDelegate)? { get set }
    var radio: RadioState { get }
    /// Largest write without response on the current link.
    var maximumWriteLength: Int { get }

    func startScanning()
    func stopScanning()
    /// Connects to a peripheral the system knows, or keeps a pending connection until it appears.
    /// Returns `false` when the system has never seen that peripheral.
    @discardableResult
    func connect(_ peripheral: UUID) -> Bool
    func cancelConnection()
    /// Queues a write; writes are paced because the earbuds drop back-to-back ones.
    func write(_ bytes: [UInt8], to characteristic: String)
    func read(_ characteristics: Set<String>)
}

/// Events from a `ControlTransport`, delivered on the main actor.
protocol ControlTransportDelegate: AnyObject {
    func transportDidUpdateRadio(_ radio: RadioState)
    func transportDidDiscover(_ peripheral: DiscoveredPeripheral)
    func transportDidConnect(_ peripheral: UUID)
    /// Service A001 and its characteristics are discovered and notifications are on.
    func transportDidBecomeReady(_ peripheral: UUID)
    func transportDidFailToConnect(_ peripheral: UUID)
    func transportDidDisconnect(_ peripheral: UUID)
    func transportDidReceive(_ value: [UInt8], from characteristic: String)
}
