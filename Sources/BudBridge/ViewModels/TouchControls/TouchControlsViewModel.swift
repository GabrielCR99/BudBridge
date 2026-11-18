import Foundation
import Observation
import QCYKit

/// The touch-controls page: one picker per gesture, grouped by earbud or button.
@Observable
final class TouchControlsViewModel {
    /// A fixed call gesture, ready to display.
    struct CallGestureRow: Identifiable, Equatable {
        var name: String
        var detail: String
        var id: String { name }
    }

    @ObservationIgnored private let store: HeadphonesStore

    init(store: HeadphonesStore) {
        self.store = store
    }

    var groups: [TouchGroup] { store.panel?.touch?.groups ?? [] }

    var callGestures: [CallGestureRow] {
        (store.panel?.touch?.callGestures ?? []).map { gesture in
            CallGestureRow(
                name: gesture.name,
                detail: gesture.left == gesture.right
                    ? gesture.left
                    : String(localized: "L: \(gesture.left) · R: \(gesture.right)")
            )
        }
    }

    /// The selected option, or `nil` until the earbuds report it.
    func selection(for control: TouchControl) -> TouchOption? {
        control.selection(in: store.state)
    }

    func select(_ option: TouchOption, for control: TouchControl) {
        store.set(option, for: control)
    }
}
