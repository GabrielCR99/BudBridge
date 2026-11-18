import Foundation

public struct EqualizerPanel: Sendable {
    public enum Format: Sendable, Hashable {
        /// Biquad filters via record 0x22 (7-byte slots with a filter type) or 0x20 (6-byte slots).
        case parametric(typed: Bool)
        /// `[presetID, gain × 10 bands]` written to characteristic 000B.
        case legacy
    }

    public var title: String
    public var format: Format
    public var bands: [UInt16]
    public var bandQ: [Double]
    public var gainRange: ClosedRange<Double>
    public var baseGain: Int
    public var presets: [EQPreset]
    public var characteristic: String
    public var rebootTip: String?

    init?(_ block: [String: Any]) {
        title = text(block["name"]) ?? "Equalizer"
        let presetBlocks = (block["sys_eq"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let parametric = presetBlocks.contains { $0["q"] != nil && $0["freq"] != nil }
        let typed = parametric && (presetBlocks.contains { $0["iitType"] != nil } || block["iitType"] != nil)
        format = parametric ? .parametric(typed: typed) : .legacy
        bands = numbers(block["freq"]).map { UInt16(clamping: Int($0.rounded())) }
        let q = numbers(block["q"])
        bandQ = bands.indices.map { $0 < q.count ? q[$0] : 1 }
        let maxDB = Double(int(block["maxdb"]) ?? 8), minDB = Double(int(block["mindb"]) ?? 8)
        gainRange = -abs(minDB)...abs(maxDB)
        baseGain = int(block["basedb"]) ?? 0
        characteristic = shortUUID(string(block["character"])) ?? QCYGATT.legacyEQ
        rebootTip = text(block["rebootTip"]).flatMap { $0.isEmpty ? nil : $0 }
        presets = presetBlocks.enumerated().map { index, p in
            EQPreset(p, fallbackID: index + 1, parametric: parametric)
        }
        guard !bands.isEmpty || !presets.isEmpty else { return nil }
    }

    /// Bytes or record for a preset, given the link's slot budget (`(MTU − 7) / 6`, at most 20).
    public func command(for preset: EQPreset, slots: Int) -> EQCommand {
        switch format {
        case .legacy:
            .characteristic(characteristic, [preset.id] + preset.gains.map { UInt8(bitPattern: Int8(clamping: Int($0.rounded()))) })
        case .parametric(let typed):
            .record(EQConfiguration(id: preset.id, globalGain: preset.globalGain, filters: preset.filters)
                .record(typed: typed, slots: slots))
        }
    }

    /// A custom curve (ID 0x80) from one gain per band.
    public func customCommand(gains: [Double], slots: Int) -> EQCommand {
        let gains = gains.map { min(max($0, gainRange.lowerBound), gainRange.upperBound) }
        switch format {
        case .legacy:
            return .characteristic(characteristic, [EQConfiguration.customID]
                + gains.map { UInt8(bitPattern: Int8(clamping: Int($0.rounded()) + baseGain)) })
        case .parametric(let typed):
            let user = zip(bands, gains).enumerated().map { i, pair in
                EQFilter(frequency: pair.0, gain: pair.1, q: bandQ[i], kind: .userBand)
            }
            // Typed models layer the user bands on the model's base tuning, like the phone app.
            let basePreset = presets.first { $0.id == 1 } ?? presets.first
            let base = typed ? basePreset?.filters ?? [] : []
            let filters = (base + user).sorted { $0.frequency < $1.frequency }
            return .record(EQConfiguration(id: EQConfiguration.customID, filters: filters)
                .record(typed: typed, slots: slots))
        }
    }

    /// The active curve exactly as the earbuds reported it, ready to be sent back later.
    /// Effects named in the phone app live only on the phone; this is how they can be captured.
    public func activeCommand(in state: DeviceState) -> EQCommand? {
        switch format {
        case .legacy:
            return state.characteristics[characteristic].map { .characteristic(characteristic, $0) }
        case .parametric(let typed):
            let cmd = typed ? CommandID.multiEQ2.rawValue : CommandID.multiEQ.rawValue
            return state.records[cmd].map { .record(Record(cmd, $0)) }
        }
    }

    /// The active preset ID and, for custom curves, the band gains.
    public func selection(in state: DeviceState) -> (id: UInt8, gains: [Double]?)? {
        switch format {
        case .legacy:
            guard let v = state.characteristics[characteristic], let id = v.first else { return nil }
            let gains = v.dropFirst().prefix(bands.count).map { Double(Int8(bitPattern: $0)) - Double(baseGain) }
            return (id, id >= 0x80 ? Array(gains) : nil)
        case .parametric(let typed):
            let cmd = typed ? CommandID.multiEQ2.rawValue : CommandID.multiEQ.rawValue
            guard let payload = state.records[cmd],
                  let config = EQConfiguration(bytes: payload, typed: typed) else { return nil }
            guard config.isCustom else { return (config.id, nil) }
            let byFrequency = Dictionary(config.filters.filter { !typed || $0.kind == .userBand }
                .map { ($0.frequency, $0.gain) }, uniquingKeysWith: { first, _ in first })
            return (config.id, bands.map { byFrequency[$0] ?? 0 })
        }
    }
}

public enum EQCommand: Sendable, Equatable {
    case record(Record)
    case characteristic(String, [UInt8])
}

extension EQPreset {
    /// The preset's curve on the custom equalizer's bands, so the sliders can show it: the gains
    /// themselves on graphic-EQ models, or the combined response of the filters on parametric ones.
    /// Rounded to half a dB and clamped to `range`.
    public func curve(onBands bands: [UInt16], range: ClosedRange<Double>) -> [Double]? {
        let raw: [Double]
        if filters.isEmpty {
            guard gains.count == bands.count else { return nil }
            raw = gains
        } else {
            raw = bands.map { band in filters.reduce(0) { $0 + $1.response(at: Double(band)) } }
        }
        // `+ 0` turns a rounded -0.0 into 0, so it doesn't display as "−0".
        return raw.map { min(max(($0 * 2).rounded() / 2, range.lowerBound), range.upperBound) + 0 }
    }
}

public struct EQPreset: Sendable, Hashable, Identifiable {
    public var id: UInt8
    public var name: String
    public var globalGain: Double
    public var filters: [EQFilter]
    public var gains: [Double]
    /// Shown before applying (e.g. spatial audio restarts the earbuds).
    public var warning: String?

    init(_ p: [String: Any], fallbackID: Int, parametric: Bool) {
        id = UInt8(clamping: int(p["id"]) ?? fallbackID)
        name = text(p["name"]) ?? "Preset \(fallbackID)"
        globalGain = Double(int(p["mastergain"]) ?? 0)
        let gains = numbers(p["eqs"])
        self.gains = gains
        warning = text(p["alarmMsg"]).flatMap { $0.isEmpty ? nil : $0 }
        guard parametric else { filters = []; return }
        let freq = numbers(p["freq"]), q = numbers(p["q"]), types = numbers(p["iitType"])
        filters = (0..<min(freq.count, q.count, gains.count)).map { i in
            EQFilter(frequency: UInt16(clamping: Int(freq[i])), gain: gains[i], q: q[i],
                     kind: i < types.count ? EQFilter.Kind(rawValue: UInt8(clamping: Int(types[i]))) ?? .peaking : .userBand)
        }
    }
}
