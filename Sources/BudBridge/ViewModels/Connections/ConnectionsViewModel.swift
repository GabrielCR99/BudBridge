import Foundation
import Observation

/// The connections page: this Mac's links, nearby QCY devices and switching earbuds.
@Observable
final class ConnectionsViewModel {
    let status: ConnectionsStatusViewModel
    let nearby: NearbyDevicesViewModel

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore, audio: any AudioConnecting) {
        self.store = store
        status = ConnectionsStatusViewModel(store: store, audio: audio)
        nearby = NearbyDevicesViewModel(store: store)
    }

    var isControlReady: Bool { store.isReady }
    var showsNearby: Bool { !store.isReady && store.phase != .paused }
    var modelName: String { store.modelName }

    func useDifferentEarbuds() {
        store.forget()
    }
}
