import Foundation

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
                if let side = event["left"] as? [String: Any], let control = TouchControl(event: side, gesture: gesture) {
                    left.append(control)
                }
                if let side = event["right"] as? [String: Any], let control = TouchControl(event: side, gesture: gesture) {
                    right.append(control)
                }
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
