import Foundation

// MARK: - Noise control (record 0x17)

/// `[mode, scene, level]`, mirroring the control-panel encoding `mode<<16 | scene<<8 | level`.
public enum NoiseControl: Sendable, Hashable {
    case off
    case noiseCanceling(ANCScene)
    /// Ambient pass-through, level 1...6 (app default 4).
    case transparency(level: UInt8)
    /// Vocal-focused transparency (`03 02 00`).
    case vocalTransparency

    public static let transparencyLevels: ClosedRange<UInt8> = 1...6

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 3 else { return nil }
        switch (bytes[0], bytes[1], bytes[2]) {
        case (2, _, _): self = .off
        case (1, let scene, let level):
            guard let scene = ANCScene(scene: scene, level: level) else { return nil }
            self = .noiseCanceling(scene)
        case (3, 2, _): self = .vocalTransparency
        case (3, _, let level): self = .transparency(level: max(level, 1))
        default: return nil
        }
    }

    public var bytes: [UInt8] {
        switch self {
        case .off: [2, 0, 0]
        case .noiseCanceling(let scene): [1, scene.code, scene.level]
        case .transparency(let level): [3, 1, min(max(level, 1), 6)]
        case .vocalTransparency: [3, 2, 0]
        }
    }

    public var kind: Kind {
        switch self {
        case .off: .off
        case .noiseCanceling: .noiseCanceling
        case .transparency, .vocalTransparency: .transparency
        }
    }

    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        case noiseCanceling, transparency, off
        public var id: Self { self }
        public var title: String {
            switch self {
            case .noiseCanceling: "Noise Canceling"
            case .transparency: "Transparency"
            case .off: "Off"
            }
        }
        /// The setting the earbuds' own app picks when switching to this kind.
        public var defaultSetting: NoiseControl {
            switch self {
            case .noiseCanceling: .noiseCanceling(.adaptive)
            case .transparency: .transparency(level: 4)
            case .off: .off
            }
        }
    }
}

/// ANC scenes advertised by the MeloBuds Pro control panel (model 0x4D4A).
public enum ANCScene: Sendable, Hashable {
    /// Quiet environments; strength 0...2.
    case indoor(strength: UInt8)
    /// Very noisy environments such as commuting; strength 0...2.
    case commuting(strength: UInt8)
    /// Noisy environments; strength 0...2.
    case noisy(strength: UInt8)
    case windReduction
    case adaptive

    public static let strengths: ClosedRange<UInt8> = 0...2

    init?(scene: UInt8, level: UInt8) {
        let strength = min(level, 2)
        switch scene {
        case 1: self = .indoor(strength: strength)
        case 2: self = .commuting(strength: strength)
        case 3: self = .noisy(strength: strength)
        case 4: self = .windReduction
        case 5: self = .adaptive
        default: return nil
        }
    }

    var code: UInt8 {
        switch self {
        case .indoor: 1
        case .commuting: 2
        case .noisy: 3
        case .windReduction: 4
        case .adaptive: 5
        }
    }

    var level: UInt8 {
        switch self {
        case .indoor(let s), .commuting(let s), .noisy(let s): min(s, 2)
        case .windReduction, .adaptive: 0
        }
    }

    public var strength: UInt8? {
        switch self {
        case .indoor(let s), .commuting(let s), .noisy(let s): s
        case .windReduction, .adaptive: nil
        }
    }

    public func with(strength: UInt8) -> ANCScene {
        switch self {
        case .indoor: .indoor(strength: strength)
        case .commuting: .commuting(strength: strength)
        case .noisy: .noisy(strength: strength)
        case .windReduction, .adaptive: self
        }
    }

    public var kind: Kind {
        switch self {
        case .indoor: .indoor
        case .commuting: .commuting
        case .noisy: .noisy
        case .windReduction: .windReduction
        case .adaptive: .adaptive
        }
    }

    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        case adaptive, indoor, commuting, noisy, windReduction
        public var id: Self { self }

        public var title: String {
            switch self {
            case .adaptive: "Adaptive"
            case .indoor: "Indoor"
            case .commuting: "Commuting"
            case .noisy: "Noisy"
            case .windReduction: "Anti-Wind"
            }
        }

        public var detail: String {
            switch self {
            case .adaptive: "Adjusts to your surroundings automatically"
            case .indoor: "Quiet environments"
            case .commuting: "Very noisy places such as transit"
            case .noisy: "Busy, noisy environments"
            case .windReduction: "Reduces wind noise outdoors"
            }
        }

        public var symbol: String {
            switch self {
            case .adaptive: "sparkles"
            case .indoor: "house"
            case .commuting: "tram"
            case .noisy: "speaker.wave.3"
            case .windReduction: "wind"
            }
        }

        public func scene(strength: UInt8 = 2) -> ANCScene {
            switch self {
            case .adaptive: .adaptive
            case .indoor: .indoor(strength: strength)
            case .commuting: .commuting(strength: strength)
            case .noisy: .noisy(strength: strength)
            case .windReduction: .windReduction
            }
        }
    }
}

// MARK: - Simple enumerated settings

/// Prompt-tone volume (record 0x1D). Reads return `[value, max]`.
public enum BeepVolume: UInt8, Sendable, CaseIterable, Identifiable {
    case low = 4, medium = 6, high = 8, maximum = 10
    public var id: Self { self }
    public var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }
}

/// Voice-prompt language (record 0x19), sent as ASCII.
public enum PromptLanguage: String, Sendable, CaseIterable, Identifiable {
    case english = "WQ00"
    case chinese = "WQ01"
    public var id: Self { self }
    public var title: String { self == .english ? "English" : "Chinese" }
}

/// Power off after disconnection (record 0x1F), minutes as UInt16 little-endian.
public enum AutoPowerOff: UInt16, Sendable, CaseIterable, Identifiable {
    case fiveMinutes = 5, tenMinutes = 10, thirtyMinutes = 30, sixtyMinutes = 60, never = 0xFFFF
    public var id: Self { self }
    public var title: String {
        self == .never ? "Never" : "\(rawValue) minutes"
    }
}

/// Wear detection (record 0x2C): `[enabled, musicBehavior, ancFollowsWear(, sensorState)]`.
public struct WearDetection: Sendable, Hashable {
    public enum Music: UInt8, Sendable, CaseIterable, Identifiable {
        case off = 0
        case pauseAndResume = 1
        case pauseOnly = 2
        case pauseAndResumeBoth = 3
        public var id: Self { self }
        public var title: String {
            switch self {
            case .off: "Off"
            case .pauseAndResume: "Pause when removed, play when worn"
            case .pauseOnly: "Pause when removed only"
            case .pauseAndResumeBoth: "Pause when removed, play when both worn"
            }
        }
    }

    public var isEnabled: Bool
    public var music: Music
    /// Noise canceling turns off when removed and back on when worn.
    public var followsANC: Bool

    public init(isEnabled: Bool, music: Music, followsANC: Bool) {
        self.isEnabled = isEnabled
        self.music = music
        self.followsANC = followsANC
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 3 else { return nil }
        isEnabled = bytes[0] == 1
        music = Music(rawValue: bytes[1]) ?? .off
        followsANC = bytes[2] == 1
    }
}

// MARK: - Touch controls (characteristic 000D)

public enum TouchGesture: UInt8, Sendable, CaseIterable, Identifiable {
    case leftSingle = 1, rightSingle, leftDouble, rightDouble, leftTriple, rightTriple
    public var id: Self { self }
    public var isLeft: Bool { rawValue % 2 == 1 }
    public var title: String {
        switch self {
        case .leftSingle, .rightSingle: "Single tap"
        case .leftDouble, .rightDouble: "Double tap"
        case .leftTriple, .rightTriple: "Triple tap"
        }
    }
}

public enum TouchAction: UInt8, Sendable, CaseIterable, Identifiable {
    case none = 0, playPause = 1, previousTrack = 2, nextTrack = 3, voiceAssistant = 4
    case volumeUp = 5, volumeDown = 6, gamingMode = 7, noiseControl = 11
    public var id: Self { self }
    public var title: String {
        switch self {
        case .none: "Nothing"
        case .playPause: "Play / Pause"
        case .previousTrack: "Previous track"
        case .nextTrack: "Next track"
        case .voiceAssistant: "Voice assistant"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .gamingMode: "Gaming mode"
        case .noiseControl: "Cycle noise control"
        }
    }
}

public enum TouchControls {
    public static func decode(_ bytes: [UInt8]) -> [TouchGesture: TouchAction] {
        var map: [TouchGesture: TouchAction] = [:]
        for i in stride(from: 0, to: bytes.count - 1, by: 2) {
            if let gesture = TouchGesture(rawValue: bytes[i]) {
                map[gesture] = TouchAction(rawValue: bytes[i + 1]) ?? TouchAction.none
            }
        }
        return map
    }

    public static func encode(_ assignments: [TouchGesture: TouchAction]) -> [UInt8] {
        assignments.sorted { $0.key.rawValue < $1.key.rawValue }
            .flatMap { [$0.key.rawValue, $0.value.rawValue] }
    }
}

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

// MARK: - Aggregate state

/// Everything the earbuds report on the settings channel. `nil` = not reported yet.
public struct DeviceSettings: Sendable, Equatable {
    public var noiseControl: NoiseControl?
    public var lowLatency: Bool?
    public var ldac: Bool?
    public var dualDevice: Bool?
    public var sleepMode: Bool?
    public var balance: Int?
    public var beepVolume: BeepVolume?
    public var promptLanguage: PromptLanguage?
    public var autoPowerOff: AutoPowerOff?
    public var wearDetection: WearDetection?
    public var equalizer: EQConfiguration?
    public var deviceName: String?

    public init() {}

    /// Applies one record; returns `false` when the record carries nothing this model tracks.
    @discardableResult
    public mutating func apply(_ record: Record) -> Bool {
        let p = record.payload
        switch record.id {
        case .ancSetting: noiseControl = NoiseControl(bytes: p) ?? noiseControl
        case .lowLatency: lowLatency = p.first == 1
        case .ldac: ldac = p.first == 1
        case .dualDevice: dualDevice = p.first == 1
        case .sleepMode: sleepMode = p.first == 1
        case .balance: balance = p.first.map(Int.init)
        case .beepVolume: beepVolume = p.first.flatMap(BeepVolume.init(rawValue:)) ?? beepVolume
        case .promptLanguage: promptLanguage = PromptLanguage(rawValue: String(decoding: p, as: UTF8.self))
        case .standby where p.count >= 2:
            autoPowerOff = AutoPowerOff(rawValue: UInt16(p[0]) | UInt16(p[1]) << 8) ?? autoPowerOff
        case .wearDetection: wearDetection = WearDetection(bytes: p) ?? wearDetection
        case .multiEQ2: equalizer = EQConfiguration(bytes: p) ?? equalizer
        case .pairName:
            deviceName = String(decoding: p.prefix { $0 != 0 }, as: UTF8.self)
        default: return false
        }
        return true
    }
}

// MARK: - Advertisement

/// Manufacturer data broadcast by QCY earbuds (company 0x521C), as CoreBluetooth delivers it
/// (the two company-ID bytes first).
public struct QCYAdvertisement: Sendable, Hashable {
    public var vendorID: UInt16
    public var battery: BatteryStatus

    /// MeloBuds Pro model identifier.
    public static let meloBudsPro: UInt16 = 0x4D4A

    public init?(manufacturerData: some Collection<UInt8>) {
        let d = Array(manufacturerData)
        guard d.count >= 10,
              UInt16(d[0]) | UInt16(d[1]) << 8 == QCYGATT.companyID else { return nil }
        vendorID = UInt16(d[2]) << 8 | UInt16(d[3])
        battery = BatteryStatus(bytes: d[7...9]) ?? BatteryStatus()
    }
}
