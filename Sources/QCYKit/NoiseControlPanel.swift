import Foundation

public struct NoiseControlPanel: Sendable {
    public var title: String
    public var modes: [NoiseMode]

    /// Type 6: `modes: [{cmdid, name}]`, sent as a single byte.
    init(simple block: [String: Any]) {
        title = text(block["name"]) ?? "Noise Control"
        modes = (block["modes"] as? [Any] ?? []).enumerated().compactMap { index, entry in
            guard let entry = entry as? [String: Any], let value = int(entry["cmdid"]) else { return nil }
            return NoiseMode(id: index, name: text(entry["name"]) ?? "Mode \(index + 1)", defaultValue: value, kind: .single)
        }
    }

    /// Type 9: modes with `startcmdid…endcmdid` ranges; `viewtype` 1 = scenes, 2 = level slider, else one value.
    init(scenes block: [String: Any]) {
        title = text(block["name"]) ?? "Noise Control"
        modes = (block["modes"] as? [Any] ?? []).enumerated().compactMap { index, entry in
            guard let entry = entry as? [String: Any], let start = int(entry["startcmdid"]) else { return nil }
            let end = max(int(entry["endcmdid"]) ?? start, start)
            let name = text(entry["name"]) ?? "Mode \(index + 1)"
            let defaultValue = int(entry["defaultcmd"]) ?? start
            let scenes = (entry["items"] as? [Any] ?? []).compactMap { item -> NoiseScene? in
                guard let item = item as? [String: Any], let s = int(item["startcmdid"]) else { return nil }
                return NoiseScene(name: cleanLabel(text(item["name"]) ?? ""), detail: text(item["describe"]),
                                  values: s...max(int(item["endcmdid"]) ?? s, s))
            }
            let kind: NoiseMode.Kind
            switch int(entry["viewtype"]) {
            case 1 where !scenes.isEmpty:
                kind = .scenes(scenes)
            case 2 where end > start:
                let vocal = int(entry["voicecmdid"])
                let levels = vocal == start ? (start + 1)...end : start...end
                kind = .levels(levels, vocal: vocal)
            default:
                kind = .single
            }
            return NoiseMode(id: index, name: name, defaultValue: defaultValue, kind: kind)
        }
    }

    public func mode(for value: Int) -> NoiseMode? {
        modes.first { $0.contains(value) }
    }
}

public struct NoiseMode: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case scenes([NoiseScene])
        case levels(ClosedRange<Int>, vocal: Int?)
        case single
    }

    public var id: Int
    public var name: String
    public var defaultValue: Int
    public var kind: Kind

    public func contains(_ value: Int) -> Bool {
        switch kind {
        case .scenes(let scenes): scenes.contains { $0.values.contains(value) }
        case .levels(let levels, let vocal): levels.contains(value) || vocal == value
        case .single: value == defaultValue
        }
    }
}

public struct NoiseScene: Sendable, Hashable, Identifiable {
    public var name: String
    public var detail: String?
    /// One value per strength step; a single value means the scene has no strength setting.
    public var values: ClosedRange<Int>
    public var id: Int { values.lowerBound }
}

/// Noise-control values travel as `0x17 [mode, scene, level]` when they need 24 bits, or as the
/// older one-byte `0x0C [value]` (`QCYHeadsetClient.setNoiseMode`).
public enum NoiseValue {
    public static func record(_ value: Int) -> Record {
        guard value > 0xFF else { return Record(.noiseMode, [UInt8(value)]) }
        var bytes = [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        // The vocal-transparency entry (mode 3, scene 1, level 0) is sent as scene 2.
        if bytes == [3, 1, 0] { bytes = [3, 2, 0] }
        return Record(.ancSetting, bytes)
    }

    public static func value(in state: DeviceState) -> Int? {
        if let p = state.records[CommandID.ancSetting.rawValue], p.count >= 3 {
            return p[0] == 3 && p[1] == 2 ? 0x030100 : Int(p[0]) << 16 | Int(p[1]) << 8 | Int(p[2])
        }
        return state.records[CommandID.noiseMode.rawValue]?.first.map(Int.init)
    }
}
