import Foundation
import Observation

/// What `AppPresence` asks of the app around it: the Dock icon and the main window.
protocol PresenceHost: AnyObject {
    /// Called when the main window is shown (`true`) or closes (`false`).
    var onMainWindowChange: ((Bool) -> Void)? { get set }
    var isMainWindowOpen: Bool { get }
    func setDockIconVisible(_ visible: Bool)
    func closeMainWindow()
}

/// Keeps BudBridge out of the way while the earbuds aren't connected to this Mac.
///
/// BudBridge keeps running in the background so it can notice the earbuds coming back. It is only
/// *visible* (menu-bar item and Dock icon) while the earbuds' audio link is up or the main window is
/// open. When they disconnect, it waits a grace period (brief dropouts are common), then closes the
/// window and hides.
@Observable
final class AppPresence {
    /// Hide the menu-bar item and Dock icon while the earbuds are disconnected.
    var showsOnlyWhenConnected: Bool {
        didSet {
            defaults.set(showsOnlyWhenConnected, forKey: Keys.showsOnlyWhenConnected)
            applyVisibility()
        }
    }

    /// Open the main window whenever the earbuds connect.
    var opensWindowOnConnect: Bool {
        didSet { defaults.set(opensWindowOnConnect, forKey: Keys.opensWindowOnConnect) }
    }

    private(set) var launchesAtLogin: Bool
    private(set) var loginItemNeedsApproval: Bool
    private(set) var loginItemError: String?

    /// Whether the menu-bar item and Dock icon are shown.
    private(set) var isVisible = true
    /// The main window should open. The menu-bar label opens it (it's the view that can) and
    /// calls `windowRequestHandled()`.
    private(set) var wantsWindow = false
    private(set) var isEarbudsConnected = false

    @ObservationIgnored private let host: any PresenceHost
    @ObservationIgnored private let loginItem: any LoginItem
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let gracePeriod: Duration
    @ObservationIgnored private var isWindowOpen = false
    @ObservationIgnored private var isInGracePeriod = false
    @ObservationIgnored private var graceTimer: Task<Void, Never>?
    /// After a login launch, the window SwiftUI opens on its own is closed as soon as it appears.
    @ObservationIgnored private var closesLaunchWindow = false

    private enum Keys {
        static let showsOnlyWhenConnected = "showsOnlyWhenConnected"
        static let opensWindowOnConnect = "opensWindowOnConnect"
    }

    init(host: any PresenceHost, loginItem: any LoginItem, defaults: UserDefaults,
         gracePeriod: Duration = .seconds(10)) {
        self.host = host
        self.loginItem = loginItem
        self.defaults = defaults
        self.gracePeriod = gracePeriod
        showsOnlyWhenConnected = defaults.object(forKey: Keys.showsOnlyWhenConnected) as? Bool ?? true
        opensWindowOnConnect = defaults.bool(forKey: Keys.opensWindowOnConnect)
        launchesAtLogin = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.needsApproval
        host.onMainWindowChange = { [weak self] isOpen in
            if isOpen { self?.mainWindowDidOpen() } else { self?.mainWindowDidClose() }
        }
    }

    // MARK: - Launch

    /// Called once the app has finished launching. A manual launch shows the window as usual;
    /// a login launch stays in the background unless the earbuds are connected and the user
    /// wants the window then.
    func didFinishLaunching(atLogin: Bool) {
        if atLogin, !(isEarbudsConnected && opensWindowOnConnect) {
            isWindowOpen = false
            closesLaunchWindow = true
            host.closeMainWindow()
            // Only the launch window: anything opened later is the user's.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.closesLaunchWindow = false
            }
        } else {
            isWindowOpen = !atLogin || host.isMainWindowOpen
        }
        applyVisibility()
    }

    // MARK: - Events

    func earbudsConnectionChanged(_ connected: Bool) {
        guard connected != isEarbudsConnected else { return }
        isEarbudsConnected = connected
        if connected {
            stopGracePeriod()
            if opensWindowOnConnect, !host.isMainWindowOpen { wantsWindow = true }
        } else {
            startGracePeriod()
        }
        applyVisibility()
    }

    func mainWindowDidOpen() {
        if closesLaunchWindow {
            closesLaunchWindow = false
            host.closeMainWindow()
            return
        }
        guard !isWindowOpen else { return }
        isWindowOpen = true
        applyVisibility()
    }

    func mainWindowDidClose() {
        guard isWindowOpen else { return }
        isWindowOpen = false
        applyVisibility()
    }

    func windowRequestHandled() {
        wantsWindow = false
    }

    // MARK: - Login item

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = String(localized: "Couldn't change the login item: \(error.localizedDescription)")
        }
        refreshLoginItem()
    }

    /// The user can change the login item in System Settings too, so this re-reads it.
    func refreshLoginItem() {
        launchesAtLogin = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.needsApproval
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    // MARK: - Visibility

    private func startGracePeriod() {
        isInGracePeriod = true
        graceTimer?.cancel()
        graceTimer = Task { [weak self, gracePeriod] in
            try? await Task.sleep(for: gracePeriod)
            guard !Task.isCancelled else { return }
            self?.gracePeriodEnded()
        }
    }

    private func stopGracePeriod() {
        isInGracePeriod = false
        graceTimer?.cancel()
        graceTimer = nil
    }

    private func gracePeriodEnded() {
        isInGracePeriod = false
        graceTimer = nil
        guard !isEarbudsConnected, showsOnlyWhenConnected else { return }
        wantsWindow = false
        if isWindowOpen {
            isWindowOpen = false
            host.closeMainWindow()
        }
        applyVisibility()
    }

    private func applyVisibility() {
        let visible = !showsOnlyWhenConnected || isEarbudsConnected || isInGracePeriod || isWindowOpen
        guard visible != isVisible else { return }
        isVisible = visible
        host.setDockIconVisible(visible)
    }
}
