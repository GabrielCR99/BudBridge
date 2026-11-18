import Foundation
import QCYKit

/// A QCY device seen nearby, with what the catalog knows about its model.
struct NearbyDevice: Identifiable, Equatable {
    var id: UUID
    var name: String
    var advertisement: QCYAdvertisement
    var model: ModelInfo?
    var isSupported: Bool
    var rssi: Int
}
