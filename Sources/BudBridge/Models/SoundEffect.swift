import Foundation
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
        case .record(let record):
            self.record = record.command
            bytes = record.payload
        case .characteristic(let characteristic, let bytes):
            self.characteristic = characteristic
            self.bytes = bytes
        }
    }

    var command: EQCommand {
        if let record { .record(Record(record, bytes)) } else { .characteristic(characteristic ?? QCYGATT.legacyEQ, bytes) }
    }
}
