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
        self = PanelText.$language.withValue(language) { Self(layouts: layouts) }
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
