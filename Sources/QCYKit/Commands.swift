import Foundation

/// GATT layout of the QCY control service (shared by every non-JieLi model; observed on MeloBuds Pro 2.0.6).
public enum QCYGATT {
    public static let service = "A001"
    /// Write-without-response: command frames.
    public static let command = "1001"
    /// Read + notify: setting frames (a read returns all settings at once).
    public static let settings = "1002"
    /// Read: firmware versions, `L.L.L R.R.R`.
    public static let version = "0007"
    /// Read + notify: battery `[left, right, case]`, bit 7 = charging.
    public static let battery = "0008"
    /// Read + write-without-response: legacy EQ slot (`[presetID, 10 gains]`).
    public static let legacyEQ = "000B"
    /// Read + write-without-response: touch mapping as `[gesture, action]` pairs.
    public static let touchControls = "000D"

    /// Bluetooth SIG company identifier used in QCY advertisements (0x521C).
    public static let companyID: UInt16 = 0x521C
}

/// Record identifiers on the `1001`/`1002` channel (from `com.qcymall.qcylibrary.dataBean.DataBean`).
public enum CommandID: UInt8, Sendable, CaseIterable {
    case resetDefaults = 0x01
    case clearPairing = 0x02
    case factoryReset = 0x03
    case musicAction = 0x04
    case findLight = 0x05
    case inEar = 0x06
    case noiseValue = 0x07
    case volume = 0x08
    case lowLatency = 0x09
    case noiseMode = 0x0C
    case sleepMode = 0x10
    case powerManager = 0x14
    case balance = 0x16
    case ancSetting = 0x17
    case pairName = 0x18
    case promptLanguage = 0x19
    case beepVolume = 0x1D
    case standby = 0x1F
    case multiEQ = 0x20
    case multiEQ2 = 0x22
    case ldac = 0x23
    case dualDevice = 0x24
    case adaptiveEQ = 0x27
    case ancResult = 0x28
    case ancWear = 0x29
    case keyFunction = 0x2B
    case wearDetection = 0x2C
    case spatialAudio = 0x2D
    case versionInfo = 0x30
    case maxEQCount = 0x44
    case request = 0xFE
}

/// Command builders. Each returns one ``Record``; wrap with ``Frame/encode(_:)-([Record])`` to send.
public enum Command {
    /// Asks the earbuds to notify the current value of `id` on `1002`.
    public static func request(_ id: CommandID) -> Record {
        Record(.request, [id.rawValue])
    }

    /// Boolean switches use `1` = on, `2` = off on write (reads report `1`/`0`).
    public static func toggle(_ id: CommandID, _ on: Bool) -> Record {
        Record(id, [on ? 1 : 2])
    }

    public static func noiseControl(_ value: Int) -> Record {
        NoiseValue.record(value)
    }

    public static func balance(_ value: Int) -> Record {
        Record(.balance, [UInt8(clamping: min(max(value, 0), 100))])
    }

    public static func wearDetection(_ value: WearDetection) -> Record {
        Record(.wearDetection, value.bytes)
    }

    public static func rename(_ name: String, maxLength: Int = 30) -> Record {
        Record(.pairName, Array(name.utf8.prefix(maxLength)))
    }

    public static var resetToDefaults: Record { Record(.resetDefaults) }
    public static var factoryReset: Record { Record(.factoryReset) }
}
