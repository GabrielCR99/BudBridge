import Foundation
import Observation
import OSLog
import QCYKit

/// "My Sound Effects": named curves saved on this Mac, per model.
///
/// The QCY phone app keeps its named effects in a database on the phone; the earbuds only hold the
/// active curve. Saving the active curve here is how an effect made on the phone comes across.
@Observable
final class EffectLibrary {
    private(set) var effects: [SoundEffect] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "effects")

    /// - Parameter fileURL: JSON file holding the effects (Application Support by default).
    init(fileURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appending(path: "BudBridge/sound-effects.json")) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            effects = (try? JSONDecoder().decode([SoundEffect].self, from: data)) ?? []
        }
    }

    func effects(for modelID: UInt16?) -> [SoundEffect] {
        effects.filter { $0.modelID == modelID }
    }

    /// The saved effect matching the curve currently on the earbuds, if any.
    func effect(matching command: EQCommand?, modelID: UInt16?) -> SoundEffect? {
        guard let command else { return nil }
        return effects(for: modelID).first { $0.command == command }
    }

    func save(_ command: EQCommand, name: String, modelID: UInt16) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        effects.append(SoundEffect(name: name, modelID: modelID, command: command))
        persist()
    }

    func rename(_ effect: SoundEffect, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        effects[index].name = name
        persist()
    }

    func delete(_ effect: SoundEffect) {
        effects.removeAll { $0.id == effect.id }
        persist()
    }

    // MARK: - Private

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(effects).write(to: fileURL, options: .atomic)
        } catch {
            log.error("couldn't save sound effects: \(error.localizedDescription, privacy: .public)")
        }
    }
}
