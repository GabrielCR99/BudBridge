import Foundation
import Observation

/// What `AppPresence` asks of the app around it: the Dock icon and BudBridge's windows.
protocol PresenceHost: AnyObject {
    /// Called when the main window is shown (`true`) or closes (`false`).
    var onMainWindowChange: ((Bool) -> Void)? { get set }
    /// Called when another BudBridge window, such as Settings, is shown or has closed.
    var onOtherWindowsChange: (() -> Void)? { get set }
    var isMainWindowOpen: Bool { get }
    /// Another BudBridge window (Settings, About) is open. The menu-bar panel doesn't count.
    var hasOtherWindowsOpen: Bool { get }
    /// The main window is the one the user is working in (key, with BudBridge active).
    var isMainWindowKey: Bool { get }
    func setDockIconVisible(_ visible: Bool)
    func closeMainWindow()
}

/// Keeps BudBridge out of the way while the earbuds aren't connected to this Mac.
///
/// BudBridge keeps running in the background so it can notice the earbuds coming back. It is only
/// *visible* (menu-bar item and Dock icon) while the earbuds' audio link is up or one of its windows
/// is open. When they disconnect, it waits a grace period (brief dropouts are common), then closes the
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
    /// Waiting to see if the earbuds come back before hiding.
    @ObservationIgnored private(set) var isInGracePeriod = false
    @ObservationIgnored private var graceTimer: Task<Void, Never>?
    /// The window was open before the earbuds disconnected and hasn't been reopened since, so the
    /// end of the grace period may close it.
    @ObservationIgnored private var closesWindowAfterGrace = false
    /// After a login launch, the window SwiftUI opens on its own is closed as soon as it appears.
    /// Any window BudBridge or the user asks for clears this first.
    @ObservationIgnored private var closesLaunchWindow = false
    @ObservationIgnored private var launchWindowTimer: Task<Void, Never>?

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
        host.onOtherWindowsChange = { [weak self] in self?.applyVisibility() }
    }

    // MARK: - Launch

    /// Called once the app has finished launching. A manual launch shows the window as usual;
    /// a login launch stays in the background unless the earbuds are connected and the user
    /// wants the window then.
    func didFinishLaunching(atLogin: Bool) {
        if atLogin, !(isEarbudsConnected && opensWindowOnConnect) {
            // SwiftUI may have opened its window already (close it now) or may open it shortly
            // (close it when it appears).
            let hadWindow = host.isMainWindowOpen
            isWindowOpen = false
            host.closeMainWindow()
            if !hadWindow {
                closesLaunchWindow = true
                launchWindowTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.closesLaunchWindow = false
                }
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
            if opensWindowOnConnect, !host.isMainWindowOpen {
                windowRequested()
                wantsWindow = true
            }
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
        // Opened during the grace period: it's the user's now, so it stays.
        closesWindowAfterGrace = false
        applyVisibility()
    }

    /// BudBridge or the user asked for the main window (open on connect, reopening the app,
    /// Open Controls), so it must not be taken for the launch window.
    func windowRequested() {
        closesLaunchWindow = false
        launchWindowTimer?.cancel()
        launchWindowTimer = nil
    }

    func mainWindowDidClose() {
        guard isWindowOpen else { return }
        isWindowOpen = false
        applyVisibility()
    }

    /// The user opened BudBridge again (Finder, Spotlight, the Dock) and no window is showing.
    func reopenRequested() {
        windowRequested()
        wantsWindow = true
        applyVisibility()
    }

    /// The menu-bar label opened the window.
    func windowRequestHandled() {
        wantsWindow = false
        isWindowOpen = true
        closesWindowAfterGrace = false
        applyVisibility()
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
        closesWindowAfterGrace = isWindowOpen
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
        // Leave a window the user is working in (e.g. after pressing Disconnect); BudBridge hides
        // once they close it.
        if isWindowOpen, closesWindowAfterGrace, !host.isMainWindowKey {
            isWindowOpen = false
            host.closeMainWindow()
        }
        closesWindowAfterGrace = false
        applyVisibility()
    }

    private func applyVisibility() {
        // A pending window request keeps the menu-bar label around, since the label opens it.
        // Any open window keeps BudBridge visible, so a window left open (e.g. Settings) never
        // ends up without a Dock icon, app menu or menu-bar item.
        let visible = !showsOnlyWhenConnected || isEarbudsConnected || isInGracePeriod || wantsWindow
            || isWindowOpen || host.hasOtherWindowsOpen
        guard visible != isVisible else { return }
        isVisible = visible
        host.setDockIconVisible(visible)
    }
}
