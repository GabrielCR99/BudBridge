import AppKit
import IOBluetooth
import Observation

/// Classic Bluetooth (A2DP/HFP) connection between this Mac and the earbuds.
///
/// macOS negotiates SBC or AAC here. It has no LDAC encoder, so the LDAC switch only changes the
/// earbuds' configuration for other sources such as an Android phone.
@Observable
final class AudioLink: NSObject {
    private(set) var name: String?
    private(set) var address: String?
    private(set) var isPaired = false
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var lastError: String?

    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotification: IOBluetoothUserNotification?

    override init() {
        super.init()
        refresh()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceDidConnect(_:device:)))
    }

    func refresh() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        device = paired.first { device in
            let name = device.name ?? ""
            return name.localizedCaseInsensitiveContains("MeloBuds") && !name.hasSuffix("-APP")
        }
        name = device?.name
        address = device?.addressString?.uppercased()
        isPaired = device != nil
        updateConnectionState()
    }

    func connect() {
        guard let device, !device.isConnected() else { return }
        isBusy = true
        lastError = nil
        let status = device.openConnection(self)
        if status != kIOReturnSuccess {
            isBusy = false
            lastError = "Couldn't start the connection (\(String(format: "0x%08X", status)))."
        }
    }

    func disconnect() {
        guard let device, device.isConnected() else { return }
        isBusy = true
        let status = device.closeConnection()
        isBusy = false
        if status != kIOReturnSuccess {
            lastError = "Couldn't disconnect (\(String(format: "0x%08X", status)))."
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

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        Task { @MainActor in
            self.isBusy = false
            if status != kIOReturnSuccess {
                self.lastError = "The earbuds didn't accept the connection. Take them out of the case and try again."
            }
            self.updateConnectionState()
        }
    }

    @objc private nonisolated func deviceDidConnect(_ notification: IOBluetoothUserNotification,
                                                     device: IOBluetoothDevice) {
        guard device.name?.localizedCaseInsensitiveContains("MeloBuds") == true else { return }
        Task { @MainActor in self.refresh() }
    }

    @objc private nonisolated func deviceDidDisconnect(_ notification: IOBluetoothUserNotification,
                                                        device: IOBluetoothDevice) {
        notification.unregister()
        Task { @MainActor in
            self.disconnectNotification = nil
            self.updateConnectionState()
        }
    }
}
