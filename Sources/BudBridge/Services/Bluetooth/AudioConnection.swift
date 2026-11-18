import AppKit
import IOBluetooth
import Observation
import QCYKit

/// The Classic Bluetooth audio link, as view models see it.
protocol AudioConnecting: AnyObject {
    var name: String? { get }
    var address: String? { get }
    var isPaired: Bool { get }
    var isConnected: Bool { get }
    var isBusy: Bool { get }
    var lastError: String? { get }
    var pairedAddresses: [String] { get }

    func focus(on advertisement: QCYAdvertisement?)
    func refresh()
    func connect()
    func disconnect()
    func openBluetoothSettings()
}

/// Classic Bluetooth (A2DP/HFP) connection between this Mac and the earbuds.
///
/// macOS negotiates SBC or AAC here. It has no LDAC encoder, so an LDAC switch only changes the
/// earbuds' configuration for other sources such as an Android phone.
@Observable
final class AudioConnection: NSObject, AudioConnecting {
    private(set) var name: String?
    private(set) var address: String?
    private(set) var isPaired = false
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var lastError: String?

    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var target: QCYAdvertisement?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotification: IOBluetoothUserNotification?

    override init() {
        super.init()
        refresh()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceDidConnect(_:device:)))
    }

    var pairedAddresses: [String] {
        ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).compactMap(\.addressString)
    }

    /// Follows the earbuds the control link found, matched by their Classic address.
    func focus(on advertisement: QCYAdvertisement?) {
        guard advertisement != target else { return }
        target = advertisement
        refresh()
    }

    func refresh() {
        let paired = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [])
            .filter { !($0.name ?? "").hasSuffix("-APP") }
        let match: IOBluetoothDevice? = if let target {
            paired.first { $0.addressString.map(target.matchesClassicAddress) ?? false }
        } else {
            paired.first { ($0.name ?? "").localizedCaseInsensitiveContains("QCY") }
        }
        if match?.addressString != device?.addressString {
            disconnectNotification?.unregister()
            disconnectNotification = nil
        }
        device = match
        name = match?.name
        address = match?.addressString?.uppercased().replacingOccurrences(of: "-", with: ":")
        isPaired = match != nil
        updateConnectionState()
    }

    func connect() {
        guard let device, !device.isConnected() else { return }
        isBusy = true
        lastError = nil
        let status = device.openConnection(self)
        if status != kIOReturnSuccess {
            isBusy = false
            lastError = String(localized: "Couldn't start the connection (\(String(format: "0x%08X", status))).")
        }
    }

    func disconnect() {
        guard let device, device.isConnected() else { return }
        isBusy = true
        let status = device.closeConnection()
        isBusy = false
        if status != kIOReturnSuccess {
            lastError = String(localized: "Couldn't disconnect (\(String(format: "0x%08X", status))).")
        }
        updateConnectionState()
    }

    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateConnectionState() {
        isConnected = device?.isConnected() ?? false
        if isConnected, disconnectNotification == nil {
            disconnectNotification = device?.register(
                forDisconnectNotification: self, selector: #selector(deviceDidDisconnect(_:device:)))
        }
    }

    // MARK: IOBluetooth callbacks
    //
    // IOBluetooth may deliver these on a CoreBluetooth background queue, so they are nonisolated
    // and hop to the main actor with plain values only.

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        Task { @MainActor in
            self.isBusy = false
            if status != kIOReturnSuccess {
                self.lastError = String(localized: "The earbuds didn't accept the connection. Take them out of the case and try again.")
            }
            self.updateConnectionState()
        }
    }

    @objc nonisolated private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor in self.refresh() }
    }

    @objc nonisolated private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        Task { @MainActor in
            self.disconnectNotification = nil
            self.updateConnectionState()
        }
    }
}
