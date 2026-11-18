import Foundation

// MARK: - Battery and firmware

public struct BatteryLevel: Sendable, Hashable {
    public var percent: Int
    public var isCharging: Bool
}

public struct BatteryStatus: Sendable, Hashable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?
    public var chargingCase: BatteryLevel?

    public init(left: BatteryLevel? = nil, right: BatteryLevel? = nil, chargingCase: BatteryLevel? = nil) {
        self.left = left
        self.right = right
        self.chargingCase = chargingCase
    }

    /// `[left, right, case]`: low 7 bits = percent (0 = unknown/absent), bit 7 = charging.
    public init?(bytes: some Collection<UInt8>) {
        let bytes = Array(bytes)
        guard bytes.count >= 3 else { return nil }
        func level(_ byte: UInt8) -> BatteryLevel? {
            let percent = Int(byte & 0x7F)
            guard (1...100).contains(percent) else { return nil }
            return BatteryLevel(percent: percent, isCharging: byte & 0x80 != 0)
        }
        left = level(bytes[0])
        right = level(bytes[1])
        chargingCase = level(bytes[2])
    }

    public var lowestBud: Int? {
        [left?.percent, right?.percent].compactMap(\.self).min()
    }
}

public struct FirmwareVersion: Sendable, Hashable {
    public var left: String
    public var right: String?

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 3 else { return nil }
        left = bytes[0..<3].map(String.init).joined(separator: ".")
        right = bytes.count >= 6 ? bytes[3..<6].map(String.init).joined(separator: ".") : nil
    }

    public var display: String {
        guard let right, right != left else { return left }
        return "L \(left) · R \(right)"
    }
}

// MARK: - Model identity

/// QCY model families, from the vendor-ID bit tests in the Android app's `Devicebind`.
public struct ModelFamily: Sendable, Hashable {
    public var vendorID: UInt16

    public init(_ vendorID: UInt16) { self.vendorID = vendorID }

    /// JieLi models wrap the same records in JieLi's RCSP transport (not supported here).
    public var isJieLi: Bool { vendorID & 0xF0 == 0x70 || vendorID == 512 }
    /// "ZR" models compute EQ filter coefficients on the phone and renumber touch gestures.
    public var isZR: Bool { vendorID & 0xF0 == 0x90 }
    /// Families whose firmware ≥ 1.1.0 expects 0xFF instead of 0 for "no action".
    public var sendsNoActionAsFF: Bool { [0x20, 0x30, 0x80].contains(vendorID & 0xF0) }

    /// ZR firmware numbers gestures differently from QCY (`ZRDeviceImpl.converCmdIDToZR`).
    public func wireGesture(_ eventID: UInt8) -> UInt8 {
        guard isZR else { return eventID }
        return [1: 1, 3: 2, 5: 3, 2: 4, 4: 5, 6: 6][eventID] ?? eventID
    }

    public func appGesture(_ wireID: UInt8) -> UInt8 {
        guard isZR else { return wireID }
        return [1: 1, 2: 3, 3: 5, 4: 2, 5: 4, 6: 6][wireID] ?? wireID
    }
}

/// Manufacturer data broadcast by QCY earbuds (company 0x521C), as CoreBluetooth delivers it
/// (the two company-ID bytes first).
public struct QCYAdvertisement: Sendable, Hashable {
    public var vendorID: UInt16
    public var battery: BatteryStatus
    /// Last five octets of the earbuds' Classic (audio) address, e.g. `AC:60:00:11:22`.
    /// The first octet is masked in the advertisement, so it is left out.
    public var classicAddressSuffix: String?

    public static let meloBudsPro: UInt16 = 0x4D4A

    public init?(manufacturerData: some Collection<UInt8>) {
        let d = Array(manufacturerData)
        guard d.count >= 10,
              UInt16(d[0]) | UInt16(d[1]) << 8 == QCYGATT.companyID else { return nil }
        vendorID = UInt16(d[2]) << 8 | UInt16(d[3])
        battery = BatteryStatus(bytes: d[7...9]) ?? BatteryStatus()
        // Android's Devicebind reads the address as bytes [12, 11, 13, 16, 15, 14] after the company ID.
        if d.count >= 19 {
            classicAddressSuffix = [d[13], d[15], d[18], d[17], d[16]]
                .map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }

    public var family: ModelFamily { ModelFamily(vendorID) }

    /// Whether `address` (any separator, any case) is this advertisement's Classic device.
    public func matchesClassicAddress(_ address: String) -> Bool {
        guard let suffix = classicAddressSuffix else { return false }
        let octets = address.uppercased().split { $0 == ":" || $0 == "-" }
        return octets.count == 6 && octets.dropFirst().joined(separator: ":") == suffix
    }
}

// MARK: - Live state

/// Everything the earbuds have reported, kept raw. Panel items interpret it (`isOn(in:)`, `selection(in:)`).
public struct DeviceState: Sendable, Equatable {
    /// Last payload per record ID from the settings channel (1002).
    public var records: [UInt8: [UInt8]] = [:]
    /// Last value per characteristic (`"000D"`, `"000B"`, V1 per-gesture characteristics…).
    public var characteristics: [String: [UInt8]] = [:]
    public var battery: BatteryStatus?
    public var firmware: FirmwareVersion?

    public init() {}

    public mutating func apply(_ record: Record) {
        guard record.command != CommandID.request.rawValue else { return }
        records[record.command] = record.payload
    }

    public mutating func apply(frame bytes: [UInt8]) throws(FrameError) {
        for record in try Frame.decode(bytes) { apply(record) }
    }

    public var balance: Int? { records[CommandID.balance.rawValue]?.first.map(Int.init) }

    public var deviceName: String? {
        records[CommandID.pairName.rawValue].flatMap { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
    }

    public var wearDetection: WearDetection? {
        records[CommandID.wearDetection.rawValue].flatMap(WearDetection.init(bytes:))
    }
}

/// Wear detection (record 0x2C): `[enabled, musicBehavior, ancFollowsWear(, sensorState)]`.
public struct WearDetection: Sendable, Hashable {
    public var isEnabled: Bool
    public var music: UInt8
    public var followsANC: Bool

    public init(isEnabled: Bool, music: UInt8, followsANC: Bool) {
        self.isEnabled = isEnabled
        self.music = music
        self.followsANC = followsANC
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 3 else { return nil }
        isEnabled = bytes[0] == 1
        music = bytes[1]
        followsANC = bytes[2] == 1
    }

    public var bytes: [UInt8] { [isEnabled ? 1 : 0, music, followsANC ? 1 : 0] }
}
