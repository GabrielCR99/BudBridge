import Foundation
import Observation
import QCYKit

/// The sound page: EQ presets, the custom equalizer, saved sound effects and balance.
@Observable
final class SoundViewModel {
    /// What the name prompt is for: saving the active curve, or renaming a saved effect.
    enum Naming: Identifiable, Equatable {
        case save(EQCommand)
        case rename(SoundEffect)

        var id: String {
            switch self {
            case .save: "save"
            case .rename(let effect): effect.id.uuidString
            }
        }
    }

    /// A preset button.
    struct PresetRow: Identifiable, Equatable {
        var preset: EQPreset
        var isSelected: Bool
        var id: UInt8 { preset.id }
    }

    /// A saved sound effect.
    struct EffectRow: Identifiable, Equatable {
        var effect: SoundEffect
        var isActive: Bool
        var id: UUID { effect.id }
    }

    /// Slider values for the custom equalizer, edited by the view and applied on release.
    var gains: [Double] = []
    /// Balance slider value, applied on release.
    var balance = 50.0
    var naming: Naming?
    var nameDraft = ""
    /// A preset waiting for confirmation because it restarts the earbuds.
    var pendingPreset: EQPreset?

    @ObservationIgnored private let store: HeadphonesStore
    @ObservationIgnored private let effects: EffectLibrary

    init(store: HeadphonesStore, effects: EffectLibrary) {
        self.store = store
        self.effects = effects
    }

    // MARK: - Equalizer

    var equalizer: EqualizerPanel? { store.panel?.equalizer }

    /// The 9 "ZR" models compute EQ coefficients on the phone, which isn't supported yet.
    var isEqualizerSupported: Bool { store.family?.isZR != true }

    var presets: [PresetRow] {
        let selected = equalizer?.selection(in: store.state)?.id
        return (equalizer?.presets ?? []).map { PresetRow(preset: $0, isSelected: $0.id == selected) }
    }

    var hasCustomEqualizer: Bool { !(equalizer?.bands.isEmpty ?? true) }

    /// The custom button is selected only when the active curve is custom and not a saved effect.
    var isCustomSelected: Bool {
        isActiveCurveCustom && activeEffect == nil
    }

    var bandLabels: [String] { equalizer?.bands.bandLabels ?? [] }
    var gainRange: ClosedRange<Double> { equalizer?.gainRange ?? -8...8 }

    /// The curve the sliders show: the earbuds' custom curve, or the selected preset's curve.
    var activeCurve: [Double]? {
        guard let equalizer, let selection = equalizer.selection(in: store.state) else { return nil }
        if let gains = selection.gains { return gains }
        return selectedPreset?.curve(onBands: equalizer.bands, range: equalizer.gainRange)
    }

    /// Explains the sliders: a preset's curve is shown until a slider moves, which makes it custom.
    var equalizerCaption: String {
        if let selectedPreset, !isActiveCurveCustom {
            return String(localized: "Showing \(selectedPreset.name). Moving a slider makes it a custom curve.")
        }
        return String(localized: "Changes apply when you release a slider.")
    }

    private var selectedPreset: EQPreset? {
        guard let id = equalizer?.selection(in: store.state)?.id else { return nil }
        return equalizer?.presets.first { $0.id == id }
    }

    func choose(_ preset: EQPreset) {
        if preset.warning != nil { pendingPreset = preset } else { store.apply(preset: preset) }
    }

    func confirmPendingPreset() {
        if let preset = pendingPreset { store.apply(preset: preset) }
        pendingPreset = nil
    }

    func applyCustom() {
        store.apply(customGains: gains)
    }

    func flatten() {
        gains = Array(repeating: 0, count: equalizer?.bands.count ?? 0)
        applyCustom()
    }

    /// Loads the sliders from the active curve, or resets them to the right band count.
    func syncGains() {
        let bands = equalizer?.bands.count ?? 0
        if let curve = activeCurve, curve.count == bands {
            gains = curve
        } else if gains.count != bands {
            gains = Array(repeating: 0, count: bands)
        }
    }

    // MARK: - My Sound Effects

    var savedEffects: [EffectRow] {
        let active = activeEffect
        return effects.effects(for: store.modelID).map { EffectRow(effect: $0, isActive: $0 == active) }
    }

    /// The active custom curve, when it isn't saved on this Mac yet.
    var unsavedActiveCurve: EQCommand? {
        guard isActiveCurveCustom, activeEffect == nil else { return nil }
        return activeCommand
    }

    func apply(_ effect: SoundEffect) {
        store.apply(effect: effect)
    }

    func delete(_ effect: SoundEffect) {
        effects.delete(effect)
    }

    func startSaving(_ command: EQCommand) {
        nameDraft = ""
        naming = .save(command)
    }

    func startRenaming(_ effect: SoundEffect) {
        nameDraft = effect.name
        naming = .rename(effect)
    }

    var namingTitle: String {
        if case .rename = naming { String(localized: "Rename Sound Effect") } else { String(localized: "Save Sound Effect") }
    }

    var canCommitName: Bool { !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty }

    func commitName() {
        switch naming {
        case .save(let command):
            if let modelID = store.modelID { effects.save(command, name: nameDraft, modelID: modelID) }
        case .rename(let effect):
            effects.rename(effect, to: nameDraft)
        case nil:
            break
        }
        naming = nil
    }

    // MARK: - Balance

    var balanceTitle: String? { store.panel?.balance }
    var storedBalance: Int? { store.state.balance }

    func syncBalance() {
        balance = Double(store.state.balance ?? 50)
    }

    func applyBalance() {
        store.set(balance: Int(balance))
    }

    var isBalanceCentered: Bool { Int(balance) == 50 }

    /// Where the balance leans, e.g. "Centered" or "Left 20".
    var balanceDescription: String {
        let offset = Int(balance) - 50
        if offset == 0 { return String(localized: "Centered") }
        return offset < 0 ? String(localized: "Left \(-offset)") : String(localized: "Right \(offset)")
    }

    func centerBalance() {
        balance = 50
        applyBalance()
    }

    // MARK: - Private

    private var activeCommand: EQCommand? { equalizer?.activeCommand(in: store.state) }

    private var activeEffect: SoundEffect? {
        effects.effect(matching: activeCommand, modelID: store.modelID)
    }

    private var isActiveCurveCustom: Bool {
        (equalizer?.selection(in: store.state)?.id ?? 0) >= EQConfiguration.customID
    }
}
