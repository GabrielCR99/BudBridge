import Foundation
import Observation
import OSLog
import QCYKit

/// A named EQ curve, stored as the exact bytes that select it on the earbuds.
struct SoundEffect: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var modelID: UInt16
    /// Record ID for parametric curves, or `nil` when written to a characteristic (legacy EQ).
    var record: UInt8?
    var characteristic: String?
    var bytes: [UInt8]

    init(name: String, modelID: UInt16, command: EQCommand) {
        self.name = name
        self.modelID = modelID
        switch command {
        case .record(let r):
            record = r.command
            bytes = r.payload
        case .characteristic(let c, let b):
            characteristic = c
            bytes = b
        }
    }

    var command: EQCommand {
        if let record { .record(Record(record, bytes)) } else { .characteristic(characteristic ?? QCYGATT.legacyEQ, bytes) }
    }
}

/// "My Sound Effects": named curves saved on this Mac, per model.
///
/// The QCY phone app keeps its named effects in a database on the phone; the earbuds only hold the
/// active curve. Saving the active curve here is how an effect made on the phone comes across.
@Observable
final class EffectStore {
    private(set) var effects: [SoundEffect] = []

    @ObservationIgnored private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "effects")
    @ObservationIgnored private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appending(path: "BudBridge/sound-effects.json")

    init() {
        if let url, let data = try? Data(contentsOf: url) {
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
        guard !name.isEmpty, let i = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        effects[i].name = name
        persist()
    }

    func delete(_ effect: SoundEffect) {
        effects.removeAll { $0.id == effect.id }
        persist()
    }

    private func persist() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(effects).write(to: url, options: .atomic)
        } catch {
            log.error("couldn't save sound effects: \(error.localizedDescription, privacy: .public)")
        }
    }
}
