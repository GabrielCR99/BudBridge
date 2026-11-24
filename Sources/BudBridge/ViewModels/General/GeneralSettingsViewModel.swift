import Foundation
import Observation

/// The app's own settings (⌘,): opening at login and staying out of the way while the earbuds
/// are disconnected. The earbuds' settings live on the main window's Settings page.
@Observable
final class GeneralSettingsViewModel {
    @ObservationIgnored private let presence: AppPresence

    init(presence: AppPresence) {
        self.presence = presence
    }

    var launchesAtLogin: Bool {
        get { presence.launchesAtLogin }
        set { presence.setLaunchesAtLogin(newValue) }
    }

    var loginItemNeedsApproval: Bool { presence.loginItemNeedsApproval }
    var loginItemError: String? { presence.loginItemError }

    var showsOnlyWhenConnected: Bool {
        get { presence.showsOnlyWhenConnected }
        set { presence.showsOnlyWhenConnected = newValue }
    }

    var opensWindowOnConnect: Bool {
        get { presence.opensWindowOnConnect }
        set { presence.opensWindowOnConnect = newValue }
    }

    func refresh() {
        presence.refreshLoginItem()
    }

    func openLoginItemsSettings() {
        presence.openLoginItemsSettings()
    }
}
