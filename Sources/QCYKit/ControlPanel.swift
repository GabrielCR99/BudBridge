import Foundation

/// A model's settings list ("control panel"), as served by QCY's `product/findControlPanels`.
///
/// The official app builds its device screens from this JSON. Each block carries its own labels and
/// the bytes to send, so the same parser covers every tier A model. Block types follow
/// `ControlpanelJSONManager.analyseJSON` in the Android app.
public struct ControlPanel: Sendable {
    public var noiseControl: NoiseControlPanel?
    public var equalizer: EqualizerPanel?
    public var touch: TouchPanel?
    public var balance: String?
    public var wearDetection: WearDetectionPanel?
    public var rename: RenamePanel?
    public var settings: [SettingItem] = []
    public var actions: [ActionItem] = []
    public var hasFindEarbuds = false
    /// Records to request after connecting (`FE 01 <cmd>`), in panel order.
    public var readCommands: [UInt8] = []

    public enum ParseError: Error, Sendable, Equatable {
        case notJSON
        case noLayouts
    }

    /// Accepts the raw API response, its `data` object, the `controlPanel` object, or a bare `layouts` holder.
    /// `language` is the list's language (`"en"` or `"pt"`), used to tidy labels.
    public init(json: Data, language: String = "en") throws(ParseError) {
        guard let object = try? JSONSerialization.jsonObject(with: json) else { throw .notJSON }
        var node = object as? [String: Any]
        if let data = node?["data"] as? [String: Any] { node = data }
        if let panel = node?["controlPanel"] as? [String: Any] { node = panel }
        guard let layouts = node?["layouts"] as? [Any] else { throw .noLayouts }
        self = PanelText.$language.withValue(language) { ControlPanel(layouts: layouts) }
    }

    init(layouts: [Any]) {
        var reads: [UInt8] = []
        func read(_ cmd: UInt8?) { if let cmd, !reads.contains(cmd) { reads.append(cmd) } }

        for case let block as [String: Any] in layouts {
            switch int(block["type"]) {
            case 6:
                noiseControl = NoiseControlPanel(simple: block)
                read(CommandID.noiseMode.rawValue)
            case 9:
                noiseControl = NoiseControlPanel(scenes: block)
                read(CommandID.ancSetting.rawValue)
                read(CommandID.noiseMode.rawValue)
            case 2:
                equalizer = EqualizerPanel(block)
                if let eq = equalizer, case .parametric(let typed) = eq.format {
                    read(typed ? CommandID.multiEQ2.rawValue : CommandID.multiEQ.rawValue)
                }
            case 1, 10, 14:
                touch = TouchPanel(block)
            case 8:
                balance = text(block["name"]) ?? "Balance"
                read(CommandID.balance.rawValue)
            case 3:
                hasFindEarbuds = true
            case 4, nil:
                for case let item as [String: Any] in (block["items"] as? [Any] ?? []) {
                    if let toggle = ToggleItem(item) {
                        settings.append(.toggle(toggle))
                        read(toggle.stateCommand)
                    } else if let choice = ChoiceItem(languageItem: item) {
                        settings.append(.choice(choice))
                    } else if let action = ActionItem(item) {
                        actions.append(action)
                    }
                }
            case 101:
                rename = RenamePanel(title: text(block["name"]) ?? "Rename", maxLength: int(block["maxLength"]) ?? 30)
            case 103, 1000, 1001:
                if let choice = ChoiceItem(list: block) {
                    settings.append(.choice(choice))
                    if case .record(let cmd) = choice.target { read(cmd) }
                }
            case 104:
                wearDetection = WearDetectionPanel(block)
                read(CommandID.wearDetection.rawValue)
            case 13:
                for cmd in (block["cmdIndexs"] as? [Any] ?? []).compactMap(int) { read(UInt8(clamping: cmd)) }
            default:
                // 102 timed power-off (format unknown), 20 volume, 23 game EQ, 301 fit test: not supported.
                break
            }
        }
        readCommands = reads
    }
}

// MARK: - Noise control (types 6 and 9)

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

// MARK: - Equalizer (type 2)

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
            .record(EQConfiguration(id: preset.id, masterGain: preset.masterGain, filters: preset.filters)
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
                .map { ($0.frequency, $0.gain) }, uniquingKeysWith: { a, _ in a })
            return (config.id, bands.map { byFrequency[$0] ?? 0 })
        }
    }
}

public enum EQCommand: Sendable, Equatable {
    case record(Record)
    case characteristic(String, [UInt8])
}

public struct EQPreset: Sendable, Hashable, Identifiable {
    public var id: UInt8
    public var name: String
    public var masterGain: Double
    public var filters: [EQFilter]
    public var gains: [Double]
    /// Shown before applying (e.g. spatial audio restarts the earbuds).
    public var warning: String?

    init(_ p: [String: Any], fallbackID: Int, parametric: Bool) {
        id = UInt8(clamping: int(p["id"]) ?? fallbackID)
        name = text(p["name"]) ?? "Preset \(fallbackID)"
        masterGain = Double(int(p["mastergain"]) ?? 0)
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

// MARK: - Touch controls (types 1, 10, 14)

public struct TouchPanel: Sendable {
    public var title: String
    public var groups: [TouchGroup]
    /// Fixed call gestures (`name`, left action, right action).
    public var callGestures: [CallGesture]

    init?(_ block: [String: Any]) {
        title = text(block["name"]) ?? "Touch Controls"
        callGestures = []
        groups = []
        switch int(block["type"]) {
        case 10:
            let music = block["music"] as? [String: Any]
            var left: [TouchControl] = [], right: [TouchControl] = []
            for case let event as [String: Any] in (music?["event"] as? [Any] ?? []) {
                let gesture = text(event["name"]) ?? "Gesture"
                if let l = event["left"] as? [String: Any], let c = TouchControl(event: l, gesture: gesture) { left.append(c) }
                if let r = event["right"] as? [String: Any], let c = TouchControl(event: r, gesture: gesture) { right.append(c) }
            }
            groups = [TouchGroup(name: "Left Earbud", controls: left), TouchGroup(name: "Right Earbud", controls: right)]
            let voice = block["voice"] as? [String: Any]
            callGestures = (voice?["event"] as? [Any] ?? []).compactMap { entry in
                guard let e = entry as? [String: Any], let name = text(e["name"]) else { return nil }
                return CallGesture(name: name, left: text(e["left"]) ?? "", right: text(e["right"]) ?? "")
            }
        case 14:
            groups = (block["buttons"] as? [Any] ?? []).compactMap { entry in
                guard let b = entry as? [String: Any] else { return nil }
                let controls = (b["events"] as? [Any] ?? []).compactMap { e -> TouchControl? in
                    guard let e = e as? [String: Any] else { return nil }
                    return TouchControl(event: e, gesture: text(e["name"]) ?? "Gesture")
                }
                return TouchGroup(name: cleanLabel(text(b["keyName"]) ?? "Button"), controls: controls)
            }
        case 1:
            let order = ["single_click", "double_click", "three_click", "four_click", "long_press"]
            for (side, key) in [("Left Earbud", "left"), ("Right Earbud", "right")] {
                guard let gestures = block[key] as? [String: Any] else { continue }
                let controls = order.compactMap { name -> TouchControl? in
                    guard let g = gestures[name] as? [String: Any],
                          let characteristic = shortUUID(string(g["character"])) else { return nil }
                    let options = (g["list"] as? [Any] ?? []).compactMap { o -> TouchOption? in
                        guard let o = o as? [String: Any], let bytes = hexBytes(o["cmd"]) else { return nil }
                        return TouchOption(name: text(o["name"]) ?? "?", value: bytes)
                    }
                    return TouchControl(id: "\(key).\(name)", gesture: text(g["name"]) ?? name,
                                        target: .characteristic(characteristic), options: options)
                }
                groups.append(TouchGroup(name: side, controls: controls))
            }
        default:
            return nil
        }
        groups.removeAll { $0.controls.isEmpty }
        guard !groups.isEmpty else { return nil }
    }
}

public struct TouchGroup: Sendable, Hashable, Identifiable {
    public var name: String
    public var controls: [TouchControl]
    public var id: String { name }
}

public struct CallGesture: Sendable, Hashable {
    public var name: String
    public var left: String
    public var right: String
}

public struct TouchControl: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        /// `[eventID, action]` pairs on characteristic 000D.
        case event(UInt8)
        /// The action's bytes written to a per-gesture characteristic (older "V1" models).
        case characteristic(String)
    }

    public var id: String
    public var gesture: String
    public var target: Target
    public var options: [TouchOption]

    init(id: String, gesture: String, target: Target, options: [TouchOption]) {
        self.id = id
        self.gesture = gesture
        self.target = target
        self.options = options
    }

    init?(event: [String: Any], gesture: String) {
        guard let eventID = int(event["eventID"]) else { return nil }
        let options = (event["list"] as? [Any] ?? []).compactMap { o -> TouchOption? in
            guard let o = o as? [String: Any], let cmd = int(o["cmd"]) else { return nil }
            return TouchOption(name: text(o["name"]) ?? "?", value: [UInt8(clamping: cmd)])
        }
        self.init(id: "event.\(eventID)", gesture: gesture, target: .event(UInt8(clamping: eventID)), options: options)
    }

    /// The selected option, if the earbuds reported one.
    public func selection(in state: DeviceState) -> TouchOption? {
        switch target {
        case .event(let eventID):
            guard let pairs = state.characteristics[QCYGATT.touchControls] else { return nil }
            var action: UInt8?
            for i in stride(from: 0, to: pairs.count - 1, by: 2) where pairs[i] == eventID { action = pairs[i + 1] }
            guard let action else { return nil }
            // "Nothing" reads back as 0xFF on some firmware.
            return options.first { $0.value == [action] } ?? (action == 0xFF ? options.first { $0.value == [0] } : nil)
        case .characteristic(let characteristic):
            guard let value = state.characteristics[characteristic] else { return nil }
            return options.first { value.starts(with: $0.value) }
        }
    }
}

public struct TouchOption: Sendable, Hashable, Identifiable {
    public var name: String
    public var value: [UInt8]
    public var id: [UInt8] { value }
}

// MARK: - Generic settings (types 4, 103, 1000, 1001)

public enum SettingItem: Sendable, Identifiable {
    case toggle(ToggleItem)
    case choice(ChoiceItem)

    public var id: String {
        switch self {
        case .toggle(let t): "toggle.\(t.title)"
        case .choice(let c): "choice.\(c.title)"
        }
    }
}

/// A switch (item types 200–206). Its on/off bytes come straight from the panel.
public struct ToggleItem: Sendable, Hashable {
    public var title: String
    public var message: String?
    public var characteristic: String
    public var on: [UInt8]
    public var off: [UInt8]

    init?(_ item: [String: Any]) {
        guard let type = int(item["type"]), (200...206).contains(type),
              let title = text(item["title"]),
              let characteristic = shortUUID(string(item["character"])) else { return nil }
        var on: [UInt8]?, off: [UInt8]?
        for case let sub as [String: Any] in (item["sub_items"] as? [Any] ?? []) {
            guard let bytes = hexBytes(sub["cmd"]) else { continue }
            if (sub["boolVal"] as? Bool) == false { off = bytes } else if on == nil { on = bytes } else { off = bytes }
        }
        guard let on, let off else { return nil }
        self.title = cleanLabel(title)
        self.characteristic = characteristic
        self.on = on
        self.off = off
        message = (text(item["msg_ios"]) ?? text(item["msg"])).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// For framed switches on 1001, the record that reports the state on 1002.
    public var stateCommand: UInt8? {
        characteristic == QCYGATT.command && on.count >= 3 && on[0] == Frame.startByte ? on[2] : nil
    }

    public var restartsEarbuds: Bool {
        message?.localizedCaseInsensitiveContains("restart") == true
    }

    public func isOn(in state: DeviceState) -> Bool? {
        if let cmd = stateCommand {
            return state.records[cmd]?.first.map { $0 == 1 }
        }
        return state.characteristics[characteristic]?.first.map { $0 == on.first }
    }
}

/// A list of values (prompt volume, auto power-off, voice language…).
public struct ChoiceItem: Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        case record(UInt8)
        case characteristic(String)
    }

    public var title: String
    public var target: Target
    public var options: [ChoiceOption]

    /// Layout types 103 (decimal values), 1000 and 1001 (hex payloads).
    init?(list block: [String: Any]) {
        guard let cmd = int(block["cmdid"]), let title = text(block["name"]) else { return nil }
        let type = int(block["type"])
        var pairs: [(String, String)] = []
        if let keys = block["itemKey"] as? [Any], let names = block["itemName"] as? [Any] {
            pairs = zip(keys.compactMap(string), names.compactMap(text)).map { ($0, $1) }
        } else if let keys = block["itemKeyIos"] as? [Any], let names = block["itemNameIos"] as? [Any] {
            pairs = zip(keys.compactMap(string), names.compactMap(text)).map { ($0, $1) }
        } else if let map = block["itemName"] as? [String: Any] {
            pairs = map.compactMap { k, v in text(v).map { (k, $0) } }
                .sorted { (Int($0.0) ?? Int($0.0, radix: 16) ?? 0) < (Int($1.0) ?? Int($1.0, radix: 16) ?? 0) }
        }
        options = pairs.compactMap { key, name in
            let payload: [UInt8]? = type == 103 ? Int(key).map { [UInt8(clamping: $0)] } : [UInt8](hex: key)
            return payload.map { ChoiceOption(name: name, payload: $0) }
        }
        guard !options.isEmpty else { return nil }
        self.title = cleanLabel(title)
        target = .record(UInt8(clamping: cmd))
    }

    /// Item type 2: a per-characteristic list such as the V1 voice language.
    init?(languageItem item: [String: Any]) {
        guard int(item["type"]) == 2, let title = text(item["title"]),
              let characteristic = shortUUID(string(item["character"])) else { return nil }
        options = (item["sub_items"] as? [Any] ?? []).compactMap { s in
            guard let s = s as? [String: Any], let bytes = hexBytes(s["cmd"]) else { return nil }
            return ChoiceOption(name: text(s["name"]) ?? "?", payload: bytes)
        }
        guard !options.isEmpty else { return nil }
        self.title = cleanLabel(title)
        target = .characteristic(characteristic)
    }

    public func selection(in state: DeviceState) -> ChoiceOption? {
        let current: [UInt8]? = switch target {
        case .record(let cmd): state.records[cmd]
        case .characteristic(let c): state.characteristics[c]
        }
        guard let current else { return nil }
        return options.first { current.starts(with: $0.payload) }
    }
}

public struct ChoiceOption: Sendable, Hashable, Identifiable {
    public var name: String
    public var payload: [UInt8]
    public var id: [UInt8] { payload }
}

/// A one-shot command (reset, factory reset, delete pairings).
public struct ActionItem: Sendable, Hashable, Identifiable {
    public var title: String
    public var message: String?
    public var characteristic: String
    public var bytes: [UInt8]
    public var isDestructive: Bool
    public var id: String { title }

    init?(_ item: [String: Any]) {
        guard let type = int(item["type"]), [3, 4, 100].contains(type),
              let title = text(item["title"]), let bytes = hexBytes(item["cmd"]),
              let characteristic = shortUUID(string(item["character"])) else { return nil }
        self.title = cleanLabel(title)
        self.bytes = bytes
        self.characteristic = characteristic
        message = text(item["msg"]).flatMap { $0.isEmpty ? nil : $0 }
        isDestructive = type != 3
    }
}

// MARK: - Wear detection (104) and rename (101)

public struct WearDetectionPanel: Sendable, Hashable {
    public var title: String
    public var message: String?
    public var ancMessage: String?
    public var musicOptions: [ChoiceOption]

    init(_ block: [String: Any]) {
        title = text(block["name"]) ?? "Wear Detection"
        message = text(block["msg"])
        ancMessage = text(block["ancMsg"])
        musicOptions = (block["subItem"] as? [Any] ?? []).compactMap { s in
            guard let s = s as? [String: Any], let cid = int(s["cid"]) else { return nil }
            return ChoiceOption(name: text(s["name"]) ?? "?", payload: [UInt8(clamping: cid)])
        }
    }
}

public struct RenamePanel: Sendable, Hashable {
    public var title: String
    public var maxLength: Int
}

// MARK: - Lenient JSON helpers (the panels mix ints, floats and numeric strings)

func int(_ any: Any?) -> Int? {
    switch any {
    case let v as Int: v
    case let v as Double: Int(v)
    case let v as NSNumber: v.intValue
    case let v as String: Int(v.trimmingCharacters(in: .whitespaces))
    default: nil
    }
}

func string(_ any: Any?) -> String? {
    switch any {
    case let v as String: v
    case let v as NSNumber: v.stringValue
    default: nil
    }
}

/// `"31,62,1k,2k"` or `"0.7,1,1.5"` → numbers (`k` = ×1000).
func numbers(_ any: Any?) -> [Double] {
    guard let text = string(any), !text.isEmpty else { return [] }
    return text.split(separator: ",").compactMap { part in
        let s = part.trimmingCharacters(in: .whitespaces).lowercased()
        return s.hasSuffix("k") ? Double(s.dropLast()).map { $0 * 1000 } : Double(s)
    }
}

func hexBytes(_ any: Any?) -> [UInt8]? {
    guard let text = string(any), !text.isEmpty else { return nil }
    return [UInt8](hex: text)
}

/// `"00001001-0000-1000-8000-00805f9b34fb"` → `"1001"`.
func shortUUID(_ uuid: String?) -> String? {
    guard let uuid, uuid.count >= 8 else { return nil }
    return String(uuid.uppercased().dropFirst(4).prefix(4))
}

/// Display text from the panel, tidied (see `PanelText.tidy`).
func text(_ any: Any?) -> String? {
    string(any).map(PanelText.tidy)
}

/// Panel labels sometimes carry a second line; keep the first.
func cleanLabel(_ s: String) -> String {
    (s.split(separator: "\n").first.map(String.init) ?? s).trimmingCharacters(in: .whitespaces)
}

/// The settings lists are typed by hand and full of small slips: "5Minute", "Keep touching1.5S",
/// "Don‘t shut down", stray line breaks. Labels are tidied for display only; payloads are read
/// separately, so the bytes sent never change. Units follow the list's language.
public enum PanelText {
    /// Language of the settings list being parsed (`"en"` or `"pt"`), set by `ControlPanel(json:language:)`.
    @TaskLocal public static var language = "en"

    /// Obvious mistranslations in QCY's Portuguese lists.
    static let portugueseFixes = ["Prensa longa": "Toque longo"]

    public static func tidy(_ raw: String) -> String {
        let portuguese = language == "pt"
        var s = raw.replacing("‘", with: "’").replacing("´", with: "’")
        if portuguese {
            for (wrong, right) in portugueseFixes { s = s.replacing(wrong, with: right) }
        }
        // A duplicated entry in one panel ends in a stray "1" ("10Minute1", "Don‘t shut down1").
        s = s.replacing(/([A-Za-z])1$/) { "\($0.output.1)" }
        // "press1.5S" → "press 1.5S"
        s = s.replacing(/(\p{Ll})(\d)/) { "\($0.output.1) \($0.output.2)" }
        // "5Minute" → "5 minutes", "5Minuto" → "5 minutos"
        s = s.replacing(/(\d+)\s*[Mm]inut(?:es?|os?)\b/) { match in
            let n = match.output.1
            return switch (portuguese, n == "1") {
            case (true, true): "1 minuto"
            case (true, false): "\(n) minutos"
            case (false, true): "1 minute"
            case (false, false): "\(n) minutes"
            }
        }
        // "1.5S" → "1.5 seconds" / "1,5 segundos"
        s = s.replacing(/(\d+)(?:\.(\d+))?\s*[Ss]\b/) { match in
            let number = match.output.2.map { "\(match.output.1)\(portuguese ? "," : ".")\($0)" } ?? "\(match.output.1)"
            return "\(number) \(portuguese ? "segundos" : "seconds")"
        }
        // Spaces around line breaks, doubled spaces. Breaks stay: labels keep their first line.
        s = s.replacing(/[ \t]*\n[ \t]*/, with: "\n").replacing(/[ ]{2,}/, with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
