import Foundation
import Observation

/// The main window: which pages exist for the connected model, the title and the link status.
@Observable
final class RootViewModel {
    /// Why a page that needs the control link can't be shown.
    enum Unavailable: Equatable {
        case bluetoothOff
        case unauthorized
        case released
        case searching(connecting: Bool)
    }

    let nearby: NearbyDevicesViewModel

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
        nearby = NearbyDevicesViewModel(store: store)
    }

    var pages: [Page] {
        Page.allCases.filter { $0.isAvailable(for: store.panel) }
    }

    /// The page to show for a selection, falling back to the overview when it isn't available.
    func page(for selection: Page) -> Page {
        pages.contains(selection) ? selection : .overview
    }

    var title: String {
        store.isReady || store.isLoadingSettings ? store.modelName : "BudBridge"
    }

    var status: LinkStatus { LinkStatus(store: store) }

    var isControlReady: Bool { store.isReady }

    /// The earbuds are connecting and their pages are shown as placeholders.
    var isLoading: Bool { store.isLoadingSettings }

    var unavailable: Unavailable {
        switch store.phase {
        case .bluetoothOff: .bluetoothOff
        case .unauthorized: .unauthorized
        case .paused: .released
        case .connecting: .searching(connecting: true)
        case .starting, .searching, .ready: .searching(connecting: false)
        }
    }

    func takeControl() {
        store.resume()
    }

    func refresh() {
        store.refresh()
    }
}
