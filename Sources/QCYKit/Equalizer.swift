import Foundation

/// One biquad filter of a parametric EQ.
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

    static let empty = Self(frequency: 0, gain: 0, q: 0, kind: .userBand)

    /// The filter's gain in dB at a frequency, from the RBJ Audio EQ Cookbook biquads the earbuds use.
    /// User bands behave as peaking filters.
    public func response(at frequency: Double, sampleRate: Double = 48_000) -> Double {
        guard gain != 0, q > 0, self.frequency > 0 else { return 0 }
        let amplitude = pow(10, gain / 40)
        let w0 = 2 * Double.pi * Double(self.frequency) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let (numerator, denominator): ([Double], [Double])
        switch kind {
        case .lowShelf:
            let root = 2 * amplitude.squareRoot() * alpha
            let plus = amplitude + 1, minus = amplitude - 1
            numerator = [
                amplitude * (plus - minus * cosW0 + root),
                2 * amplitude * (minus - plus * cosW0),
                amplitude * (plus - minus * cosW0 - root),
            ]
            denominator = [
                plus + minus * cosW0 + root,
                -2 * (minus + plus * cosW0),
                plus + minus * cosW0 - root,
            ]
        case .peaking, .userBand:
            numerator = [1 + alpha * amplitude, -2 * cosW0, 1 - alpha * amplitude]
            denominator = [1 + alpha / amplitude, -2 * cosW0, 1 - alpha / amplitude]
        }
        // |H(e^jw)| for H(z) = (b0 + b1 z⁻¹ + b2 z⁻²) / (a0 + a1 z⁻¹ + a2 z⁻²).
        let w = 2 * Double.pi * frequency / sampleRate
        func magnitude(_ coefficients: [Double]) -> Double {
            let real = coefficients[0] + coefficients[1] * cos(w) + coefficients[2] * cos(2 * w)
            let imaginary = -coefficients[1] * sin(w) - coefficients[2] * sin(2 * w)
            return (real * real + imaginary * imaginary).squareRoot()
        }
        return 20 * log10(magnitude(numerator) / magnitude(denominator))
    }
}

/// Payload of record 0x22 (typed) or 0x20 (untyped):
/// `[id, globalGain s16] + slots × [freq u16, gain s16, q u16 (, type)]`,
/// all little-endian, gain and Q scaled by 100 (`QCYHeadsetClient.setEQWtihQFG2Type`).
public struct EQConfiguration: Sendable, Hashable {
    public static let maxSlots = 20
    /// IDs ≥ 0x80 are custom curves; 0x80 is the one the phone app (and this app) edits.
    public static let customID: UInt8 = 0x80

    public var id: UInt8
    public var globalGain: Double
    public var filters: [EQFilter]

    public init(id: UInt8, globalGain: Double = 0, filters: [EQFilter]) {
        self.id = id
        self.globalGain = globalGain
        self.filters = filters
    }

    public init?(bytes: [UInt8], typed: Bool = true) {
        let stride = typed ? 7 : 6
        guard bytes.count >= 3 + stride else { return nil }
        id = bytes[0]
        globalGain = Double(Int16(bitPattern: UInt16(bytes[1]) | UInt16(bytes[2]) << 8)) / 100
        var filters: [EQFilter] = []
        var i = 3
        while i + stride <= bytes.count {
            let frequency = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
            let gain = Int16(bitPattern: UInt16(bytes[i + 2]) | UInt16(bytes[i + 3]) << 8)
            let q = UInt16(bytes[i + 4]) | UInt16(bytes[i + 5]) << 8
            if frequency != 0 {
                filters.append(EQFilter(
                    frequency: frequency,
                    gain: Double(gain) / 100,
                    q: Double(q) / 100,
                    kind: typed ? EQFilter.Kind(rawValue: bytes[i + 6]) ?? .peaking : .userBand
                ))
            }
            i += stride
        }
        self.filters = filters
    }

    public var isCustom: Bool { id >= 0x80 }

    /// Slots the phone app sends for a link: `(writeLength − 7) / 6`, capped at 20
    /// (`QCYConnectManager.setEQMarketData`; its "MTU" is already the ATT MTU minus 3).
    public static func slots(forWriteLength length: Int) -> Int {
        min(max((length - 7) / 6, 1), maxSlots)
    }

    public func encoded(typed: Bool = true, slots: Int = maxSlots) -> [UInt8] {
        var out: [UInt8] = [id]
        out += Self.le(Int16(clamping: Int((globalGain * 100).rounded())))
        let padded = (filters + Array(repeating: .empty, count: slots)).prefix(slots)
        for f in padded {
            out += Self.le(f.frequency)
            out += Self.le(Int16(clamping: min(max(Int((f.gain * 100).rounded()), -1270), 1270)))
            out += Self.le(UInt16(clamping: Int((f.q * 100).rounded())))
            if typed { out.append(f.kind.rawValue) }
        }
        return out
    }

    public func record(typed: Bool, slots: Int = maxSlots) -> Record {
        Record(typed ? .multiEQ2 : .multiEQ, encoded(typed: typed, slots: slots))
    }

    private static func le(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le(_ v: Int16) -> [UInt8] { le(UInt16(bitPattern: v)) }
}

extension Collection where Element == UInt16 {
    /// Frequency labels like `31`, `1k`, `16k`.
    public var bandLabels: [String] {
        map { $0 >= 1000 ? ($0 % 1000 == 0 ? "\($0 / 1000)k" : String(format: "%.1fk", Double($0) / 1000)) : "\($0)" }
    }
}
