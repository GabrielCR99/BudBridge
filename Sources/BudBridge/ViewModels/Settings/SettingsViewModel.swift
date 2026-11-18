import Foundation
import Observation
import QCYKit

/// The settings page: everything else the model's settings list offers, in panel order.
@Observable
final class SettingsViewModel {
    /// A label and value for the About section.
    struct AboutRow: Identifiable, Equatable {
        var label: String
        var value: String
        var id: String { label }
    }

    let switches: SwitchesViewModel
    /// The new Bluetooth name being typed.
    var nameDraft = ""
    /// A reset command waiting for confirmation.
    var pendingAction: ActionItem?

    @ObservationIgnored private let store: HeadphonesStore
    @ObservationIgnored private let audio: any AudioConnecting
    @ObservationIgnored private let finder: any FindTonePlaying

    init(store: HeadphonesStore, audio: any AudioConnecting, finder: any FindTonePlaying) {
        self.store = store
        self.audio = audio
        self.finder = finder
        switches = SwitchesViewModel(store: store)
    }

    // MARK: - Features

    var items: [SettingItem] { store.panel?.settings ?? [] }

    func selection(for choice: ChoiceItem) -> ChoiceOption? {
        choice.selection(in: store.state)
    }

    func select(_ option: ChoiceOption, in choice: ChoiceItem) {
        store.select(option, in: choice)
    }

    // MARK: - Wear detection

    var wearPanel: WearDetectionPanel? { store.panel?.wearDetection }

    var wear: WearDetection {
        store.state.wearDetection ?? WearDetection(isEnabled: false, music: 0, followsANC: false)
    }

    func setWear(enabled: Bool) {
        var value = wear
        value.isEnabled = enabled
        store.set(wearDetection: value)
    }

    func setWear(music: UInt8) {
        var value = wear
        value.music = music
        store.set(wearDetection: value)
    }

    func setWear(followsANC: Bool) {
        var value = wear
        value.followsANC = followsANC
        store.set(wearDetection: value)
    }

    // MARK: - Rename

    var renamePanel: RenamePanel? { store.panel?.rename }
    var namePlaceholder: String { store.state.deviceName ?? store.modelName }
    var canRename: Bool { !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty }

    func rename() {
        store.rename(to: nameDraft)
        nameDraft = ""
    }

    // MARK: - Find earbuds

    var hasFindEarbuds: Bool { store.panel?.hasFindEarbuds == true }
    var isFindSoundPlaying: Bool { finder.isPlaying }
    /// The sound plays through the Mac's output, so the earbuds must be connected for audio.
    var canPlayFindSound: Bool { audio.isConnected || finder.isPlaying }

    func toggleFindSound() {
        finder.toggle()
    }

    // MARK: - About

    var about: [AboutRow] {
        var rows = [
            AboutRow(label: String(localized: "Model"), value: store.modelName),
            AboutRow(label: String(localized: "Firmware"), value: store.state.firmware?.display ?? "—"),
        ]
        if let address = audio.address {
            rows.append(AboutRow(label: String(localized: "Address"), value: address))
        }
        if let id = store.advertisement?.vendorID {
            rows.append(AboutRow(label: String(localized: "Model ID"),
                                 value: "\(id) (0x\(String(id, radix: 16, uppercase: true)))"))
        }
        return rows
    }

    // MARK: - Actions

    var actions: [ActionItem] { store.panel?.actions ?? [] }

    func confirmPendingAction() {
        if let action = pendingAction { store.run(action) }
        pendingAction = nil
    }

    var pendingActionMessage: String {
        pendingAction?.message ?? String(localized: "This can't be undone.")
    }
}
