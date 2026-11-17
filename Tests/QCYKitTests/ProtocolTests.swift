import Testing
@testable import QCYKit

/// All fixtures are frames captured from a MeloBuds Pro (firmware 2.0.6) talking to the official app.
struct FrameTests {
    @Test func decodesFullSettingsRead() throws {
        let frame = try #require([UInt8](hex:
            "FF302C0401030101080336360F09010217030200001001001601320401022301002401001F0205001D02060F190457513030"))
        let records = try Frame.decode(frame)
        #expect(records.count == 12)

        var settings = DeviceSettings()
        records.forEach { settings.apply($0) }
        #expect(settings.noiseControl == .off)
        #expect(settings.lowLatency == false)
        #expect(settings.ldac == false)
        #expect(settings.dualDevice == false)
        #expect(settings.sleepMode == false)
        #expect(settings.balance == 50)
        #expect(settings.beepVolume == .medium)
        #expect(settings.promptLanguage == .english)
        #expect(settings.autoPowerOff == .fiveMinutes)
        #expect(settings.wearDetection == WearDetection(isEnabled: true, music: .pauseAndResumeBoth, followsANC: true))
    }

    @Test func rejectsBadFrames() {
        #expect(throws: FrameError.badStartByte(0x00)) { try Frame.decode([0x00, 0x01, 0x02]) }
        #expect(throws: FrameError.lengthMismatch(declared: 5, actual: 2)) { try Frame.decode([0xFF, 0x05, 0x01, 0x02]) }
        #expect(throws: FrameError.truncatedRecord(offset: 2)) { try Frame.decode([0xFF, 0x03, 0x17, 0x05, 0x01]) }
    }

    @Test(arguments: [
        (Command.request(.ancSetting), "FF03FE0117"),
        (Command.toggle(.lowLatency, true), "FF03090101"),
        (Command.toggle(.lowLatency, false), "FF03090102"),
        (Command.toggle(.ldac, true), "FF03230101"),
        (Command.toggle(.ldac, false), "FF03230102"),
        (Command.toggle(.dualDevice, true), "FF03240101"),
        (Command.noiseControl(.off), "FF051703020000"),
        (Command.noiseControl(.noiseCanceling(.adaptive)), "FF051703010500"),
        (Command.noiseControl(.noiseCanceling(.indoor(strength: 1))), "FF051703010101"),
        (Command.noiseControl(.noiseCanceling(.noisy(strength: 0))), "FF051703010300"),
        (Command.noiseControl(.noiseCanceling(.windReduction)), "FF051703010400"),
        (Command.noiseControl(.transparency(level: 4)), "FF051703030104"),
        (Command.wearDetection(WearDetection(isEnabled: true, music: .pauseAndResumeBoth, followsANC: true)), "FF052C03010301"),
        (Command.resetToDefaults, "FF020100"),
        (Command.factoryReset, "FF020300"),
    ])
    func encodesCommandsLikeTheOfficialApp(record: Record, expected: String) {
        #expect(Frame.encode(record).hex == expected)
    }
}

struct EqualizerTests {
    /// Captured when choosing "Classic" in the phone app.
    static let classicFrame =
        "FF91228F0600001E000000460004DC000CFE640000F00A6400640000E02E6400500000B4140CFEC800003C00C8003C0000"
        + String(repeating: "000000000000FF", count: 14)

    @Test func presetMatchesCapturedBytes() {
        let classic = EQPreset.all.first { $0.name == "Classic" }!
        #expect(Frame.encode(Command.equalizer(classic.configuration)).hex == Self.classicFrame)
    }

    @Test func decodesStoredCustomCurve() throws {
        let frame = try #require([UInt8](hex:
            "FF91228F8118FC1E0000004600041F002C016400FF3C00F4013C00003E00C8006400FF7D0000006400FFDC00E0FC640000FA009CFF6400FFF4019CFF6400FFE80300006400FFD00764006400FFF00A6400640000A00FC8006400FFB4140CFEC80000401FF4016400FFE02E2003500000803E2C016400FF000000000000FF000000000000FF000000000000FF000000000000FF"))
        let eq = try #require(EQConfiguration(bytes: try Frame.decode(frame)[0].payload))
        #expect(eq.id == 0x81)
        #expect(eq.masterGain == -10)
        #expect(eq.graphicGains == [3, 2, 0, -1, -1, 0, 1, 2, 5, 3])
    }

    @Test func customCurveRoundTrips() throws {
        let gains: [Double] = [2, 1.5, 0, -1, 0, 0, 1, 3, 4, -2]
        let config = GraphicEQ.configuration(gains: gains)
        let decoded = try #require(EQConfiguration(bytes: config.encoded()))
        #expect(decoded.id == EQConfiguration.customID)
        #expect(decoded.graphicGains == gains)
        #expect(config.encoded().count == 3 + 20 * 7)
    }
}

struct DeviceDataTests {
    @Test func batteryAndFirmware() throws {
        let battery = try #require(BatteryStatus(bytes: [0x5B, 0xDA, 0x00]))
        #expect(battery.left == BatteryLevel(percent: 91, isCharging: false))
        #expect(battery.right == BatteryLevel(percent: 90, isCharging: true))
        #expect(battery.chargingCase == nil)
        #expect(FirmwareVersion(bytes: [2, 0, 6, 2, 0, 6])?.display == "2.0.6")
    }

    @Test func touchControlMapping() throws {
        let raw = try #require([UInt8](hex: "0106020503020403050B06010700080000000000"))
        let map = TouchControls.decode(raw)
        #expect(map[.leftSingle] == .volumeDown)
        #expect(map[.rightSingle] == .volumeUp)
        #expect(map[.leftTriple] == .noiseControl)
        #expect(map[.rightTriple] == .playPause)
        #expect(TouchControls.encode([.leftDouble: .nextTrack]) == [3, 3])
    }

    @Test func advertisement() throws {
        let raw = try #require([UInt8](hex: "1c524d4a34a06a5a5800b88937ac846022110001ac8460554433"))
        let ad = try #require(QCYAdvertisement(manufacturerData: raw))
        #expect(ad.vendorID == QCYAdvertisement.meloBudsPro)
        #expect(ad.battery.left?.percent == 90)
        #expect(ad.battery.right?.percent == 88)
        #expect(ad.battery.chargingCase == nil)
    }
}
