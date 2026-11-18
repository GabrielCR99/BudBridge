@testable import BudBridge
import Foundation
import QCYKit
import Testing

struct HeadphonesStoreTests {
    @Test func connectsAutomaticallyOnlyToEarbudsPairedWithThisMac() {
        let (store, transport, audio) = Fixtures.makeStore()
        transport.powerOn()
        #expect(store.phase == .searching)

        transport.advertise(Fixtures.stranger)
        #expect(transport.connected.isEmpty)
        #expect(store.nearby.count == 1)

        transport.advertise(Fixtures.meloBuds)
        #expect(transport.connected == [Fixtures.meloBudsID])
        #expect(store.phase == .connecting)
        #expect(store.modelName == "QCY MeloBuds Pro")
        #expect(audio.focused.last??.vendorID == QCYAdvertisement.meloBudsPro)
    }

    @Test func becomingReadyReadsAndRequestsWhatTheSettingsListNeeds() throws {
        let (store, transport, _) = Fixtures.makeStore()
        transport.powerOn()
        transport.advertise(Fixtures.meloBuds)
        transport.finishConnecting(Fixtures.meloBudsID)

        #expect(store.isReady)
        #expect(!transport.isScanning)
        let reads = try #require(transport.reads.last)
        #expect(reads.isSuperset(of: [QCYGATT.settings, QCYGATT.battery, QCYGATT.version, QCYGATT.touchControls]))
        #expect(transport.commandFrames.contains("FF03FE0117"))
        #expect(transport.commandFrames.contains("FF03FE0123"))
    }

    @Test func settingsReadFillsTheState() {
        let (store, _, _) = Fixtures.connectedStore()
        #expect(store.state.balance == 50)
        #expect(NoiseValue.value(in: store.state) == 0x020000)
        #expect(store.state.firmware?.display == "2.0.6")
    }

    @Test func noiseChangesUpdateOptimisticallyAndSendTheFrame() {
        let (store, transport, _) = Fixtures.connectedStore()
        store.setNoise(0x010500)
        #expect(NoiseValue.value(in: store.state) == 0x010500)
        #expect(transport.commandFrames == ["FF051703010500"])
    }

    @Test func switchesThatRestartTheEarbudsMarkTheStore() throws {
        let (store, transport, _) = Fixtures.connectedStore()
        let ldac = try #require(toggle("LDAC Switch", in: store))
        store.set(ldac, on: true)
        #expect(store.isRestarting)
        #expect(ldac.isOn(in: store.state) == true)
        #expect(transport.commandFrames == ["FF03230101"])
    }

    @Test func disconnectingKeepsAPendingConnectionForTheRestart() {
        let (store, transport, _) = Fixtures.connectedStore()
        transport.delegate?.transportDidDisconnect(Fixtures.meloBudsID)
        #expect(store.phase == .searching)
        #expect(transport.connected.last == Fixtures.meloBudsID)
        #expect(transport.isScanning)
    }

    @Test func releasingToThePhoneStopsReconnecting() {
        let (store, transport, _) = Fixtures.connectedStore()
        store.pause()
        transport.delegate?.transportDidDisconnect(Fixtures.meloBudsID)
        #expect(store.phase == .paused)
        #expect(transport.cancelCount == 1)
    }

    @Test func touchControlsWritePairsToCharacteristic000D() throws {
        let (store, transport, _) = Fixtures.connectedStore()
        transport.notify(QCYGATT.touchControls, "0106020503020403050B06010700080000000000")
        let control = try #require(store.panel?.touch?.groups.first?.controls.first)
        let next = try #require(control.options.first { $0.name == "Next track" })
        store.set(next, for: control)
        #expect(transport.writes.last?.characteristic == QCYGATT.touchControls)
        #expect(transport.writes.last?.bytes == [1, 3])
        #expect(control.selection(in: store.state)?.name == "Next track")
    }

    @Test func batteryGoesStaleWhenDisconnectedAndQuiet() {
        let (store, transport, _) = Fixtures.connectedStore()
        transport.notify(QCYGATT.battery, "5A5800")
        #expect(!store.isBatteryStale())
        transport.delegate?.transportDidDisconnect(Fixtures.meloBudsID)
        #expect(!store.isBatteryStale(at: .now))
        #expect(store.isBatteryStale(at: .now.addingTimeInterval(31)))
    }

    @Test func caseSlotAppearsOnlyAfterTheModelReportsACaseLevel() {
        let (store, transport, _) = Fixtures.connectedStore()
        transport.notify(QCYGATT.battery, "5A5800")
        #expect(!store.reportsCaseBattery)
        transport.notify(QCYGATT.battery, "5A5840")
        #expect(store.reportsCaseBattery)
    }

    @Test func forgettingClearsTheDeviceAndTheAudioTarget() {
        let (store, transport, audio) = Fixtures.connectedStore()
        store.forget()
        #expect(store.panel == nil)
        #expect(store.phase == .searching)
        #expect(transport.isScanning)
        #expect(audio.focused.last == .some(nil))
    }

    @Test func downloadsTheSettingsListWhenNoneIsCached() async throws {
        let (store, transport, panels) = Fixtures.makeStoreWithoutCache()
        panels.downloads[QCYAdvertisement.meloBudsPro] = FakePanels.fixture(QCYAdvertisement.meloBudsPro)
        transport.powerOn()
        transport.advertise(Fixtures.meloBuds)
        try await waitUntil { store.panel != nil }
        #expect(panels.refreshRequests.first?.0 == QCYAdvertisement.meloBudsPro)
        #expect(panels.refreshRequests.first?.1 == nil)
        #expect(!store.isDownloadingPanel)
        #expect(!store.panelDownloadFailed)
    }

    @Test func reportsAFailedDownloadAndRetries() async throws {
        let (store, transport, panels) = Fixtures.makeStoreWithoutCache()
        transport.powerOn()
        transport.advertise(Fixtures.meloBuds)
        try await waitUntil { store.panelDownloadFailed }
        #expect(store.panel == nil)

        panels.downloads[QCYAdvertisement.meloBudsPro] = FakePanels.fixture(QCYAdvertisement.meloBudsPro)
        store.retryPanelDownload()
        try await waitUntil { store.panel != nil }
        #expect(!store.panelDownloadFailed)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private func toggle(_ title: String, in store: HeadphonesStore) -> ToggleItem? {
        for case .toggle(let toggle) in store.panel?.settings ?? [] where toggle.title == title { return toggle }
        return nil
    }
}
