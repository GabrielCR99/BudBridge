import Foundation
import Observation
import QCYKit

/// The noise-control page: the current mode's scenes, strength steps or level slider.
@Observable
final class NoiseControlViewModel {
    /// What the page shows under the mode picker.
    enum Content: Equatable {
        /// Scenes with an optional strength picker for the current scene.
        case scenes([SceneRow], strengths: [StrengthOption])
        /// A level slider, with a vocal toggle when the model has one.
        case levels(range: ClosedRange<Int>, value: Int, hasVocal: Bool, isVocal: Bool)
        /// A mode with nothing more to choose.
        case none
        /// The earbuds haven't reported their mode yet.
        case waiting
    }

    /// A scene in the list.
    struct SceneRow: Identifiable, Equatable {
        var scene: NoiseScene
        var isSelected: Bool
        var id: Int { scene.id }
    }

    /// One strength step of the current scene.
    struct StrengthOption: Identifiable, Equatable {
        var value: Int
        var title: String
        var id: Int { value }
    }

    let modes: NoiseModesViewModel

    init(store: HeadphonesStore) {
        modes = NoiseModesViewModel(store: store)
    }

    var content: Content {
        guard let mode = modes.selectedMode, let value = modes.value else { return .waiting }
        switch mode.kind {
        case .scenes(let scenes):
            let current = scenes.first { $0.values.contains(value) }
            let rows = scenes.map { SceneRow(scene: $0, isSelected: $0 == current) }
            let strengths = (current.map { scene in
                scene.values.count > 1 ? scene.values.enumerated().map { index, step in
                    StrengthOption(value: step, title: String(localized: "Level \(index + 1)"))
                } : []
            }) ?? []
            return .scenes(rows, strengths: strengths)
        case .levels(let levels, let vocal):
            return .levels(range: levels, value: levels.contains(value) ? value : levels.lowerBound,
                           hasVocal: vocal != nil, isVocal: vocal == value)
        case .single:
            return .none
        }
    }

    /// The current value, for the strength picker.
    var value: Int? { modes.value }

    /// Switches scene, keeping the current strength step.
    func select(_ scene: NoiseScene) {
        guard case .scenes(let scenes)? = modes.selectedMode?.kind, let value = modes.value else { return }
        let current = scenes.first { $0.values.contains(value) }
        let step = current.map { value - $0.values.lowerBound } ?? (scene.values.count - 1)
        modes.setValue(min(scene.values.lowerBound + step, scene.values.upperBound))
    }

    func setStrength(_ value: Int) {
        modes.setValue(value)
    }

    func setLevel(_ value: Int) {
        modes.setValue(value)
    }

    /// Vocal enhancement on, or back to the middle level.
    func setVocal(_ on: Bool) {
        guard case .levels(let levels, let vocal?)? = modes.selectedMode?.kind else { return }
        modes.setValue(on ? vocal : levels.lowerBound + (levels.count - 1) / 2)
    }
}
