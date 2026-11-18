@testable import BudBridge
import Foundation
import QCYKit
import Testing

struct RootViewModelTests {
    @Test func pagesFollowTheSettingsList() {
        let (store, transport, _) = Fixtures.makeStore()
        let root = RootViewModel(store: store)
        #expect(root.pages == [.overview, .connections])
        #expect(root.page(for: .sound) == .overview)

        transport.powerOn()
        transport.advertise(Fixtures.meloBuds)
        #expect(root.pages == Page.allCases)
        #expect(root.unavailable == .searching(connecting: true))
    }

    @Test func titleAndStatusFollowTheLink() {
        let (store, _, _) = Fixtures.connectedStore()
        let root = RootViewModel(store: store)
        #expect(root.title == "QCY MeloBuds Pro")
        #expect(root.status.tone == .connected)
        store.pause()
        #expect(root.status.tone == .released)
        #expect(root.unavailable == .released)
    }
}

struct NoiseControlViewModelTests {
    @Test func scenesKeepTheStrengthStepWhenSwitching() throws {
        let (store, transport, _) = Fixtures.connectedStore()
        let viewModel = NoiseControlViewModel(store: store)
        store.setNoise(0x010101)  // Indoor, level 2
        guard case .scenes(let scenes, let strengths) = viewModel.content else {
            Issue.record("expected scenes")
            return
        }
        #expect(scenes.first { $0.isSelected }?.scene.name == "Indoor")
        #expect(strengths.map(\.title) == ["Level 1", "Level 2", "Level 3"])

        let commuting = try #require(scenes.first { $0.scene.name == "Commuting" }?.scene)
        viewModel.select(commuting)
        #expect(transport.commandFrames.last == "FF051703010201")
    }

    @Test func transparencyShowsLevelsAndVocal() {
        let (store, _, _) = Fixtures.connectedStore()
        let viewModel = NoiseControlViewModel(store: store)
        store.setNoise(0x030104)
        #expect(viewModel.content == .levels(range: 0x030101...0x030106, value: 0x030104, hasVocal: true, isVocal: false))
        viewModel.setVocal(true)
        #expect(viewModel.content == .levels(range: 0x030101...0x030106, value: 0x030101, hasVocal: true, isVocal: true))
    }

    @Test func waitsUntilTheEarbudsReportAMode() {
        let (store, _, _) = Fixtures.makeStore()
        #expect(NoiseControlViewModel(store: store).content == .waiting)
    }
}

struct SwitchesViewModelTests {
    @Test func restartingSwitchesAskFirst() throws {
        let (store, transport, _) = Fixtures.connectedStore()
        let switches = SwitchesViewModel(store: store)
        let ldac = try #require(switches.quickToggles.first { $0.title == "Dual Device Connection" })
        switches.set(ldac, on: true)
        #expect(switches.pendingRestart == ldac)
        #expect(transport.commandFrames.isEmpty)
        switches.confirmRestart()
        #expect(switches.pendingRestart == nil)
        #expect(transport.commandFrames == ["FF03240101"])
    }

    @Test func gamingModeAndQuickToggles() {
        let (store, _, _) = Fixtures.connectedStore()
        let switches = SwitchesViewModel(store: store)
        #expect(switches.gamingMode?.title == "Gaming mode")
        #expect(switches.quickToggles.map(\.title) == ["Gaming mode", "Dual Device Connection"])
    }
}

struct SoundViewModelTests {
    private func makeViewModel() -> (SoundViewModel, HeadphonesStore, FakeTransport) {
        let (store, transport, _) = Fixtures.connectedStore()
        let file = FileManager.default.temporaryDirectory.appending(path: "effects-\(UUID().uuidString).json")
        return (SoundViewModel(store: store, effects: EffectLibrary(fileURL: file)), store, transport)
    }

    @Test func customCurveCanBeSavedAndReapplied() throws {
        let (viewModel, _, transport) = makeViewModel()
        viewModel.syncGains()
        viewModel.gains = [2, 1, 0, 0, 0, 0, 0, 1, 2, 3]
        viewModel.applyCustom()
        #expect(viewModel.isCustomSelected)

        let unsaved = try #require(viewModel.unsavedActiveCurve)
        viewModel.startSaving(unsaved)
        viewModel.nameDraft = "rdit2"
        viewModel.commitName()
        #expect(viewModel.savedEffects.map(\.effect.name) == ["rdit2"])
        #expect(viewModel.savedEffects.first?.isActive == true)
        #expect(!viewModel.isCustomSelected)
        #expect(viewModel.unsavedActiveCurve == nil)

        transport.clearWrites()
        viewModel.choose(try #require(viewModel.presets.first { $0.preset.name == "Classic" }).preset)
        #expect(viewModel.savedEffects.first?.isActive == false)
        viewModel.apply(try #require(viewModel.savedEffects.first).effect)
        #expect(viewModel.savedEffects.first?.isActive == true)
    }

    @Test func spatialPresetAsksBeforeRestarting() throws {
        let (viewModel, _, transport) = makeViewModel()
        let spatial = try #require(viewModel.presets.first { $0.preset.warning != nil }).preset
        viewModel.choose(spatial)
        #expect(viewModel.pendingPreset == spatial)
        #expect(transport.commandFrames.isEmpty)
        viewModel.confirmPendingPreset()
        #expect(transport.commandFrames.count == 1)
    }

    @Test func balanceSyncsAndCenters() {
        let (viewModel, _, transport) = makeViewModel()
        viewModel.syncBalance()
        #expect(viewModel.balance == 50)
        viewModel.balance = 70
        viewModel.applyBalance()
        #expect(transport.commandFrames.last == "FF03160146")
        viewModel.centerBalance()
        #expect(transport.commandFrames.last == "FF03160132")
    }
}

struct ConnectionsStatusViewModelTests {
    @Test func audioActionsFollowTheConnection() {
        let (store, _, audio) = Fixtures.makeStore()
        let status = ConnectionsStatusViewModel(store: store, audio: audio)
        #expect(status.audioAction == .connect)
        status.performAudioAction()
        #expect(audio.actions == ["connect"])

        audio.isConnected = true
        #expect(status.audioAction == .disconnect)
        #expect(status.audioDetail == "QCY MeloBuds Pro · connected to this Mac (AAC/SBC)")

        audio.isPaired = false
        #expect(status.audioAction == .pair)
    }

    @Test func controlActionsFollowThePhase() {
        let (store, _, audio) = Fixtures.connectedStore()
        let status = ConnectionsStatusViewModel(store: store, audio: audio)
        #expect(status.controlAction == .release)
        #expect(status.controlDetail == "QCY MeloBuds Pro · firmware 2.0.6")
        status.performControlAction()
        #expect(store.phase == .paused)
        #expect(status.controlAction == .takeControl)
    }
}

struct SettingsViewModelTests {
    @Test func wearDetectionChangesOneFieldAtATime() {
        let (store, transport, audio) = Fixtures.connectedStore()
        let settings = SettingsViewModel(store: store, audio: audio, finder: FakeFinder())
        #expect(settings.wear == WearDetection(isEnabled: true, music: 3, followsANC: true))
        settings.setWear(music: 1)
        #expect(transport.commandFrames.last == "FF052C03010101")
        settings.setWear(enabled: false)
        #expect(transport.commandFrames.last == "FF052C03000101")
    }

    @Test func findSoundNeedsTheAudioLink() {
        let (store, _, audio) = Fixtures.connectedStore()
        let finder = FakeFinder()
        let settings = SettingsViewModel(store: store, audio: audio, finder: finder)
        #expect(!settings.canPlayFindSound)
        audio.isConnected = true
        #expect(settings.canPlayFindSound)
        settings.toggleFindSound()
        #expect(finder.isPlaying)
    }

    @Test func resetsAskFirst() throws {
        let (store, transport, audio) = Fixtures.connectedStore()
        let settings = SettingsViewModel(store: store, audio: audio, finder: FakeFinder())
        settings.pendingAction = try #require(settings.actions.first { $0.isDestructive })
        #expect(transport.writes.isEmpty)
        settings.confirmPendingAction()
        #expect(transport.commandFrames == ["FF020300"])
    }
}

struct NearbyDevicesViewModelTests {
    @Test func strongestFirstAndConnectable() throws {
        let (store, transport, _) = Fixtures.makeStore()
        let nearby = NearbyDevicesViewModel(store: store)
        transport.powerOn()
        transport.advertise(Fixtures.stranger)
        let row = try #require(nearby.rows.first)
        #expect(row.canConnect)
        #expect(row.battery == 88)
        nearby.connect(row)
        #expect(transport.connected == [Fixtures.strangerID])
    }
}
