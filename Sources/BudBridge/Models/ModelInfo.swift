import Foundation

/// One entry of QCY's product list (bundled as `Panels/catalog.json`).
struct ModelInfo: Sendable, Decodable, Identifiable, Equatable {
    var id: UInt16
    var name: String
    var kind: String
    var supported: Bool
    var note: String?

    /// The catalog stores its notes in English; these are the only three.
    var localizedNote: String? {
        switch note {
        case "Uses the JieLi connection protocol": String(localized: "Uses the JieLi connection protocol")
        case "QCY publishes no settings for this model": String(localized: "QCY publishes no settings for this model")
        case "A few of this model's features aren't available yet":
            String(localized: "A few of this model's features aren't available yet")
        default: note
        }
    }
}
