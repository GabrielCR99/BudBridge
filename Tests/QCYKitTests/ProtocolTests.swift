import Foundation
@testable import QCYKit
import Testing

/// Settings-list fixtures (`Tests/Fixtures/Panels/<modelID>.json`): the structure and numbers of real QCY
/// lists, with sentence-length texts replaced by our own wording. QCY's lists aren't redistributed.
enum Panels {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Tests/Fixtures/Panels")

    static func load(_ id: Int) throws -> ControlPanel {
        try ControlPanel(json: Data(contentsOf: directory.appending(path: "\(id).json")))
    }

    static var supportedIDs: [Int] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path()))?
            .compactMap { Int($0.replacingOccurrences(of: ".json", with: "")) }.sorted() ?? []
    }

    static let meloBudsPro = 19786
}

/// Fixtures are frames captured from a MeloBuds Pro (firmware 2.0.6) talking to the official app.
struct FrameTests {
    @Test func decodesFullSettingsRead() throws {
        let frame = try #require([UInt8](hex:
            "FF302C0401030101080336360F09010217030200001001001601320401022301002401001F0205001D02060F190457513030"))
        var state = DeviceState()
        try state.apply(frame: frame)
        #expect(state.records.count == 12)
        #expect(NoiseValue.value(in: state) == 0x020000)
        #expect(state.balance == 50)
        #expect(state.wearDetection == WearDetection(isEnabled: true, music: 3, followsANC: true))
    }

    @Test func rejectsBadFrames() {
        #expect(throws: FrameError.badStartByte(0x00)) { try Frame.decode([0x00, 0x01, 0x02]) }
        #expect(throws: FrameError.lengthMismatch(declared: 5, actual: 2)) { try Frame.decode([0xFF, 0x05, 0x01, 0x02]) }
        #expect(throws: FrameError.truncatedRecord(offset: 2)) { try Frame.decode([0xFF, 0x03, 0x17, 0x05, 0x01]) }
    }

    @Test(arguments: [
        (Command.request(.ancSetting), "FF03FE0117"),
        (Command.toggle(.lowLatency, true), "FF03090101"),
        (Command.toggle(.ldac, false), "FF03230102"),
        (Command.noiseControl(0x020000), "FF051703020000"),
        (Command.noiseControl(0x010500), "FF051703010500"),
        (Command.noiseControl(0x010101), "FF051703010101"),
        (Command.noiseControl(0x030104), "FF051703030104"),
        (Command.noiseControl(0x030100), "FF051703030200"),
        (Command.noiseControl(1), "FF030C0101"),
        (Command.wearDetection(WearDetection(isEnabled: true, music: 3, followsANC: true)), "FF052C03010301"),
        (Command.resetToDefaults, "FF020100"),
        (Command.factoryReset, "FF020300"),
    ])
    func encodesCommandsLikeTheOfficialApp(record: Record, expected: String) {
        #expect(Frame.encode(record).hex == expected)
    }
}

struct MeloBudsPanelTests {
    let panel: ControlPanel

    init() throws { panel = try Panels.load(Panels.meloBudsPro) }

    @Test func noiseControlComesFromThePanel() throws {
        let noise = try #require(panel.noiseControl)
        #expect(noise.modes.map(\.name) == ["Noise canceling", "Transparency", "Normal"])
        guard case .scenes(let scenes) = noise.modes[0].kind else { Issue.record("expected scenes"); return }
        #expect(scenes.map(\.name) == ["Adaptive Noise Cancellation", "Indoor", "Commuting", "Noisy", "Anti-wind noise"])
        #expect(scenes[1].values == 0x010100...0x010102)
        guard case .levels(let levels, let vocal) = noise.modes[1].kind else { Issue.record("expected levels"); return }
        #expect(levels == 0x030101...0x030106)
        #expect(vocal == 0x030100)
        #expect(noise.mode(for: 0x010500)?.name == "Noise canceling")
        #expect(noise.mode(for: 0x020000)?.name == "Normal")
    }

    @Test func classicPresetMatchesCapturedBytes() throws {
        let eq = try #require(panel.equalizer)
        #expect(eq.format == .parametric(typed: true))
        let classic = try #require(eq.presets.first { $0.name == "Classic" })
        guard case .record(let record) = eq.command(for: classic, slots: 20) else { Issue.record("expected a record"); return }
        #expect(Frame.encode(record).hex ==
            "FF91228F0600001E000000460004DC000CFE640000F00A6400640000E02E6400500000B4140CFEC800003C00C8003C0000"
            + String(repeating: "000000000000FF", count: 14))
    }

    @Test func customCurveRoundTrips() throws {
        let eq = try #require(panel.equalizer)
        let gains: [Double] = [2, 1.5, 0, -1, 0, 0, 1, 3, 4, -2]
        guard case .record(let record) = eq.customCommand(gains: gains, slots: 20) else { Issue.record("expected a record"); return }
        var state = DeviceState()
        state.apply(record)
        let selection = try #require(eq.selection(in: state))
        #expect(selection.id == EQConfiguration.customID)
        #expect(selection.gains == gains)
    }

    @Test func storedCustomCurveDecodes() throws {
        let frame = try #require([UInt8](hex:
            "FF91228F8118FC1E0000004600041F002C016400FF3C00F4013C00003E00C8006400FF7D0000006400FFDC00E0FC640000"
            + "FA009CFF6400FFF4019CFF6400FFE80300006400FFD00764006400FFF00A6400640000A00FC8006400FFB4140CFEC80000"
            + "401FF4016400FFE02E2003500000803E2C016400FF000000000000FF000000000000FF000000000000FF000000000000FF"))
        var state = DeviceState()
        try state.apply(frame: frame)
        let selection = try #require(panel.equalizer?.selection(in: state))
        #expect(selection.id == 0x81)
        #expect(selection.gains == [3, 2, 0, -1, -1, 0, 1, 2, 5, 3])

        // Saving it captures the exact bytes, hidden tuning filters included.
        guard case .record(let record) = panel.equalizer?.activeCommand(in: state) else { Issue.record("expected a record"); return }
        #expect(Frame.encode(record) == frame)
    }

    @Test func legacyActiveCurveIsCapturedAsIs() throws {
        let eq = try #require(try Panels.load(19745).equalizer)
        var state = DeviceState()
        state.characteristics["000B"] = [0x80, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0xFE]
        #expect(eq.activeCommand(in: state) == .characteristic("000B", [0x80, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0xFE]))
    }

    @Test func settingsCarryTheirOwnBytes() throws {
        let toggles = panel.settings.compactMap { if case .toggle(let t) = $0 { t } else { nil } }
        let ldac = try #require(toggles.first { $0.title == "LDAC Switch" })
        #expect(ldac.on.hex == "FF03230101" && ldac.off.hex == "FF03230102")
        #expect(ldac.stateCommand == 0x23)
        #expect(ldac.restartsEarbuds)

        var state = DeviceState()
        state.apply(Record(.ldac, [1]))
        #expect(ldac.isOn(in: state) == true)
        state.apply(Record(.ldac, [0]))
        #expect(ldac.isOn(in: state) == false)

        let choices = panel.settings.compactMap { if case .choice(let c) = $0 { c } else { nil } }
        let beep = try #require(choices.first { $0.title == "Beep volume" })
        #expect(beep.options.map(\.payload) == [[4], [6], [8], [10]])
        let powerOff = try #require(choices.first { $0.title == "Disconnect and power off" })
        #expect(powerOff.options.first?.payload == [0x05, 0x00])
        #expect(panel.actions.map(\.title) == ["Reset to default", "Reset to factory"])
        #expect(panel.readCommands.contains(0x17))
    }

    @Test func touchControls() throws {
        let touch = try #require(panel.touch)
        #expect(touch.groups.map(\.name) == ["Left Earbud", "Right Earbud"])
        #expect(touch.groups[0].controls.map(\.gesture) == ["Touch", "Double touch", "Triple touch"])
        var state = DeviceState()
        state.characteristics[QCYGATT.touchControls] = try #require([UInt8](hex: "0106020503020403050B06010700080000000000"))
        #expect(touch.groups[0].controls[0].selection(in: state)?.name == "Volume down")
        #expect(touch.groups[0].controls[2].selection(in: state)?.name == "ANC mode")
    }
}

struct PanelTextTests {
    @Test(arguments: [
        ("5Minute", "5 minutes"),
        ("1Minute", "1 minute"),
        ("10Minute1", "10 minutes"),
        ("Keep touching1.5S", "Keep touching 1.5 seconds"),
        ("Long press1.5S", "Long press 1.5 seconds"),
        ("Don‘t shut down", "Don’t shut down"),
        (" Transparency", "Transparency"),
        ("Do you reset factory?\n Reset button functions", "Do you reset factory?\nReset button functions"),
        ("LDAC Switch", "LDAC Switch"),
        ("Volume de notificação", "Volume de notificação"),
    ])
    func tidiesQCYLabels(raw: String, expected: String) {
        #expect(PanelText.tidy(raw) == expected)
    }

    @Test(arguments: [
        ("5Minuto", "5 minutos"),
        ("1Minuto", "1 minuto"),
        ("Prensa longa1.5S", "Toque longo 1,5 segundos"),
        (" Transparente", "Transparente"),
    ])
    func tidiesPortugueseLabels(raw: String, expected: String) {
        #expect(PanelText.$language.withValue("pt") { PanelText.tidy(raw) } == expected)
    }

    @Test func portugueseMeloBudsPanel() throws {
        let url = Panels.directory.appending(path: "pt/\(Panels.meloBudsPro).json")
        let panel = try ControlPanel(json: Data(contentsOf: url), language: "pt")
        let choices = panel.settings.compactMap { if case .choice(let c) = $0 { c } else { nil } }
        let tone = try #require(choices.first { $0.options.map(\.payload) == [Array("WQ00".utf8), Array("WQ01".utf8)] })
        #expect(tone.title == "Troca de Tom")
        #expect(tone.options.map(\.name) == ["Inglês", "Chinês"])
        let powerOff = try #require(choices.first { $0.options.first?.payload == [0x05, 0x00] })
        #expect(powerOff.options.first?.name == "5 minutos")
        // The bytes are the same as the English list's.
        #expect(panel.readCommands == (try Panels.load(Panels.meloBudsPro)).readCommands)
    }

    @Test func tidiedLabelsKeepTheirBytes() throws {
        let panel = try Panels.load(Panels.meloBudsPro)
        let choices = panel.settings.compactMap { if case .choice(let c) = $0 { c } else { nil } }
        let powerOff = try #require(choices.first { $0.title == "Disconnect and power off" })
        #expect(powerOff.options.first?.name == "5 minutes")
        #expect(powerOff.options.first?.payload == [0x05, 0x00])
        #expect(panel.touch?.callGestures.last?.name == "Long press 1.5 seconds")
    }
}

struct OtherModelTests {
    @Test func everyFixtureParses() throws {
        let ids = Panels.supportedIDs
        #expect(ids.count == 4)
        for id in ids {
            let panel = try Panels.load(id)
            #expect(panel.equalizer != nil || panel.touch != nil || !panel.settings.isEmpty, "model \(id) has no controls")
        }
    }

    @Test func legacyEqualizer() throws {
        // QCY T5: 10 gains written to characteristic 000B, presets numbered by position.
        let eq = try #require(try Panels.load(19745).equalizer)
        #expect(eq.format == .legacy)
        #expect(eq.bands == [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        let pop = try #require(eq.presets.first { $0.name == "Pop" })
        #expect(eq.command(for: pop, slots: 20) == .characteristic("000B", [2, 0xFA, 5, 0xFD, 0xFE, 5, 4, 0xFC, 0xFD, 6, 4]))
        var state = DeviceState()
        state.characteristics["000B"] = [0x80, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0xFE]
        #expect(eq.selection(in: state)?.gains == [3, 0, 0, 0, 0, 0, 0, 0, 0, -2])
    }

    @Test func perGestureTouchCharacteristics() throws {
        // QCY T2C: one characteristic per gesture, actions written as their own bytes.
        let touch = try #require(try Panels.load(18863).touch)
        let single = try #require(touch.groups.first?.controls.first)
        #expect(single.target == .characteristic("0001"))
        #expect(single.options.first?.value == [1])
    }

    @Test func simpleNoiseControl() throws {
        // QCY HT03: modes are single bytes sent with record 0x0C.
        let noise = try #require(try Panels.load(19393).noiseControl)
        #expect(noise.modes.map(\.defaultValue) == [1, 3, 2])
        var state = DeviceState()
        state.apply(Record(.noiseMode, [3]))
        #expect(noise.mode(for: NoiseValue.value(in: state) ?? 0)?.name == "Transparency")
    }

    @Test func advertisementIdentity() throws {
        let raw = try #require([UInt8](hex: "1c524d4a34a06a5a5800b88937ac846022110001ac8460554433"))
        let ad = try #require(QCYAdvertisement(manufacturerData: raw))
        #expect(ad.vendorID == QCYAdvertisement.meloBudsPro)
        #expect(ad.battery.left?.percent == 90)
        #expect(ad.classicAddressSuffix == "AC:60:00:11:22")
        #expect(ad.matchesClassicAddress("c4-ac-60-00-11-22"))
        #expect(!ad.family.isJieLi && !ad.family.isZR)
        #expect(ModelFamily(0x4173).isJieLi)          // QCY H3
        #expect(ModelFamily(19857).wireGesture(2) == 4) // ZR renumbering
    }
}
