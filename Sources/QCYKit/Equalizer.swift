import Foundation

/// One biquad filter of the earbuds' parametric EQ.
public struct EQFilter: Sendable, Hashable {
    public enum Kind: UInt8, Sendable {
        case peaking = 0x00
        case lowShelf = 0x04
        /// User-adjustable graphic-EQ band (the app's sliders). Also used for empty slots.
        case userBand = 0xFF
    }

    public var frequency: UInt16
    /// Gain in dB, ±12.7 on the wire.
    public var gain: Double
    public var q: Double
    public var kind: Kind

    public init(frequency: UInt16, gain: Double, q: Double, kind: Kind) {
        self.frequency = frequency
        self.gain = gain
        self.q = q
        self.kind = kind
    }

    static let empty = EQFilter(frequency: 0, gain: 0, q: 0, kind: .userBand)
}

/// Payload of record 0x22: `[id, masterGain s16] + 20 × [freq u16, gain s16, q u16, type]`,
/// all little-endian, gain and Q scaled by 100.
public struct EQConfiguration: Sendable, Hashable {
    public static let slotCount = 20
    /// IDs ≥ 0x80 are custom curves; 0x80 is the one this app (and the phone app) edits.
    public static let customID: UInt8 = 0x80

    public var id: UInt8
    public var masterGain: Double
    public var filters: [EQFilter]

    public init(id: UInt8, masterGain: Double = 0, filters: [EQFilter]) {
        self.id = id
        self.masterGain = masterGain
        self.filters = filters
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 3 + 7 else { return nil }
        id = bytes[0]
        masterGain = Double(Int16(bitPattern: UInt16(bytes[1]) | UInt16(bytes[2]) << 8)) / 100
        var filters: [EQFilter] = []
        var i = 3
        while i + 7 <= bytes.count {
            let frequency = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
            let gain = Int16(bitPattern: UInt16(bytes[i + 2]) | UInt16(bytes[i + 3]) << 8)
            let q = UInt16(bytes[i + 4]) | UInt16(bytes[i + 5]) << 8
            if frequency != 0 {
                filters.append(EQFilter(
                    frequency: frequency,
                    gain: Double(gain) / 100,
                    q: Double(q) / 100,
                    kind: EQFilter.Kind(rawValue: bytes[i + 6]) ?? .peaking
                ))
            }
            i += 7
        }
        self.filters = filters
    }

    public var isCustom: Bool { id >= 0x80 }

    public func encoded() -> [UInt8] {
        var out: [UInt8] = [id]
        out += Self.le(Int16(clamping: Int((masterGain * 100).rounded())))
        let slots = (filters + Array(repeating: .empty, count: Self.slotCount)).prefix(Self.slotCount)
        for f in slots {
            out += Self.le(f.frequency)
            out += Self.le(Int16(clamping: min(max(Int((f.gain * 100).rounded()), -1270), 1270)))
            out += Self.le(UInt16(clamping: Int((f.q * 100).rounded())))
            out.append(f.kind.rawValue)
        }
        return out
    }

    /// Gains of the 10 graphic bands, if this is a custom curve containing them.
    public var graphicGains: [Double]? {
        guard isCustom else { return nil }
        let bands = Dictionary(filters.filter { $0.kind == .userBand }.map { ($0.frequency, $0.gain) },
                               uniquingKeysWith: { a, _ in a })
        guard !bands.isEmpty else { return nil }
        return GraphicEQ.frequencies.map { bands[$0] ?? 0 }
    }

    private static func le(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le(_ v: Int16) -> [UInt8] { le(UInt16(bitPattern: v)) }
}

/// The 10-band graphic EQ exposed by the MeloBuds Pro control panel.
public enum GraphicEQ {
    public static let frequencies: [UInt16] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let gainRange: ClosedRange<Double> = -8...8

    /// A custom curve: the model's base tuning plus the 10 user bands (Q 1.0), sorted by frequency
    /// as the phone app sends it.
    public static func configuration(gains: [Double]) -> EQConfiguration {
        precondition(gains.count == frequencies.count)
        let bands = zip(frequencies, gains).map { frequency, gain in
            EQFilter(frequency: frequency, gain: min(max(gain, gainRange.lowerBound), gainRange.upperBound),
                     q: 1, kind: .userBand)
        }
        let filters = (EQPreset.default.filters + bands).sorted { $0.frequency < $1.frequency }
        return EQConfiguration(id: EQConfiguration.customID, filters: filters)
    }

    public static func label(for frequency: UInt16) -> String {
        frequency >= 1000 ? "\(frequency / 1000)k" : "\(frequency)"
    }
}

/// Factory presets from the MeloBuds Pro control panel (`product/findControlPanels`, model 19786).
public struct EQPreset: Sendable, Hashable, Identifiable {
    public var id: UInt8
    public var name: String
    public var filters: [EQFilter]
    /// Shown before applying (spatial audio restarts the earbuds and disables LDAC).
    public var warning: String?

    public var configuration: EQConfiguration { EQConfiguration(id: id, filters: filters) }

    init(_ id: UInt8, _ name: String, freq: [UInt16], gain: [Double], q: [Double], kinds: [UInt8],
         warning: String? = nil) {
        self.id = id
        self.name = name
        self.warning = warning
        filters = (0..<freq.count).map {
            EQFilter(frequency: freq[$0], gain: gain[$0], q: q[$0], kind: EQFilter.Kind(rawValue: kinds[$0]) ?? .peaking)
        }
    }

    private static let shelfFirst: [UInt8] = [4, 0, 0, 0, 0, 0]

    public static let `default` = EQPreset(1, "Default", freq: [30, 220, 900, 2800, 12000, 5300],
        gain: [0, -8, -2, 4, 3, -3], q: [0.7, 1, 1.5, 1, 0.8, 2], kinds: shelfFirst)

    public static let all: [EQPreset] = [
        .default,
        EQPreset(2, "Pop", freq: [30, 220, 2800, 12000, 5300, 60],
                 gain: [0, -8, 3.5, 3, -3, -3], q: [0.4, 1, 1, 0.8, 2, 0.5], kinds: shelfFirst),
        EQPreset(3, "Heavy Bass", freq: [30, 220, 2800, 12000, 5300, 60],
                 gain: [0, -8, 1, 8, -5, 5], q: [0.7, 1, 1, 0.8, 2, 0.6], kinds: shelfFirst),
        EQPreset(4, "Rock", freq: [30, 220, 2800, 12000, 5300, 60],
                 gain: [0, -10, 2, 3, -1, 3], q: [0.7, 1, 1, 0.8, 2, 0.6], kinds: shelfFirst),
        EQPreset(5, "Soft", freq: [30, 220, 2800, 12000, 5300, 60],
                 gain: [0, -8, 1, 1, -3, -2], q: [0.4, 1, 1, 0.8, 2, 0.5], kinds: shelfFirst),
        EQPreset(6, "Classic", freq: [30, 220, 2800, 12000, 5300, 60],
                 gain: [0, -5, 1, 1, -5, 2], q: [0.7, 1, 1, 0.8, 2, 0.6], kinds: shelfFirst),
        EQPreset(10, "Spatial", freq: [30, 220, 900, 2800, 12000, 5300],
                 gain: [0, -8, -2, 4, 3, -3], q: [0.7, 1, 1.5, 1, 0.8, 2], kinds: shelfFirst,
                 warning: "Spatial sound isn't compatible with LDAC. The earbuds will restart with LDAC turned off."),
    ]
}
