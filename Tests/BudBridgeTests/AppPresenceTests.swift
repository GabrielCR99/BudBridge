@testable import BudBridge
import Foundation
import Testing

struct AppPresenceTests {
    @Test func loginLaunchStaysHiddenUntilTheEarbudsConnect() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.didFinishLaunching(atLogin: true)
        #expect(!presence.isVisible)
        #expect(host.dockIcon == [false])
        #expect(host.closeCount == 1)

        // The window SwiftUI opens at launch is closed as it appears.
        host.userOpensWindow()
        #expect(!host.isMainWindowOpen)
        #expect(!presence.isVisible)

        presence.earbudsConnectionChanged(true)
        #expect(presence.isVisible)
        #expect(host.dockIcon == [false, true])
        #expect(!presence.wantsWindow)
    }

    @Test func manualLaunchShowsTheWindowAndHidesOnceItCloses() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()
        #expect(presence.isVisible)
        #expect(host.closeCount == 0)

        host.userClosesWindow()
        #expect(!presence.isVisible)
        #expect(host.dockIcon == [false])

        // Opening BudBridge again (Finder, Spotlight) brings it back.
        host.userOpensWindow()
        #expect(presence.isVisible)
    }

    @Test func disconnectingClosesTheWindowAfterTheGracePeriod() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()

        presence.earbudsConnectionChanged(false)
        #expect(presence.isVisible)
        #expect(host.closeCount == 0)

        try await waitUntil { !presence.isVisible }
        #expect(host.closeCount == 1)
        #expect(!host.isMainWindowOpen)
    }

    @Test func reconnectingDuringTheGracePeriodKeepsTheWindow() async throws {
        let setup = makePresence(grace: .milliseconds(50))
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()

        presence.earbudsConnectionChanged(false)
        presence.earbudsConnectionChanged(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(presence.isVisible)
        #expect(host.closeCount == 0)
        #expect(host.isMainWindowOpen)
    }

    @Test func opensTheWindowOnConnectOnlyWhenAsked() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        let defaults = setup.defaults
        presence.didFinishLaunching(atLogin: true)
        host.userOpensWindow() // SwiftUI's launch window, closed as it appears
        presence.earbudsConnectionChanged(true)
        #expect(!presence.wantsWindow)

        presence.earbudsConnectionChanged(false)
        presence.opensWindowOnConnect = true
        #expect(defaults.bool(forKey: "opensWindowOnConnect"))
        presence.earbudsConnectionChanged(true)
        #expect(presence.wantsWindow)
        presence.windowRequestHandled()
        #expect(!presence.wantsWindow)

        // Not when the window is already open.
        presence.earbudsConnectionChanged(false)
        host.userOpensWindow()
        presence.earbudsConnectionChanged(true)
        #expect(!presence.wantsWindow)
    }

    @Test func loginLaunchKeepsTheWindowWhenConnectedAndAsked() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.opensWindowOnConnect = true
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: true)
        host.userOpensWindow()
        #expect(host.isMainWindowOpen)
        #expect(host.closeCount == 0)
    }

    @Test func alwaysVisibleWhenTheSettingIsOff() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        let defaults = setup.defaults
        presence.showsOnlyWhenConnected = false
        #expect(defaults.object(forKey: "showsOnlyWhenConnected") as? Bool == false)
        presence.didFinishLaunching(atLogin: true)
        host.userOpensWindow() // SwiftUI's launch window, closed as it appears
        #expect(presence.isVisible)

        presence.earbudsConnectionChanged(true)
        host.userOpensWindow()
        presence.earbudsConnectionChanged(false)
        try await Task.sleep(for: .milliseconds(60))
        #expect(presence.isVisible)
        #expect(host.isMainWindowOpen)

        // Turning it back on while disconnected hides once the window is gone.
        host.userClosesWindow()
        presence.showsOnlyWhenConnected = true
        try await waitUntil { !presence.isVisible }
    }

    @Test func loginItemTogglesAndReportsFailures() {
        let setup = makePresence()
        let presence = setup.presence
        let login = setup.login
        presence.setLaunchesAtLogin(true)
        #expect(presence.launchesAtLogin)
        #expect(presence.loginItemError == nil)

        login.fails = true
        presence.setLaunchesAtLogin(false)
        #expect(presence.launchesAtLogin)
        #expect(presence.loginItemError != nil)

        login.needsApproval = true
        presence.refreshLoginItem()
        #expect(presence.loginItemNeedsApproval)
        presence.openLoginItemsSettings()
        #expect(login.openedSettings)
    }
}
