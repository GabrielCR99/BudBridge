import Foundation

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
