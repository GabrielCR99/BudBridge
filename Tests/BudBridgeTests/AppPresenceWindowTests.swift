@testable import BudBridge
import Foundation
import Testing

/// How `AppPresence` treats the main window and BudBridge's other windows: the launch window,
/// opening on request, and the grace period.
struct AppPresenceWindowTests {
    // MARK: - Launch window

    @Test func openOnConnectRightAfterLoginKeepsItsWindow() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.opensWindowOnConnect = true
        presence.didFinishLaunching(atLogin: true)

        // The earbuds connect a moment later and BudBridge opens the window for them.
        presence.earbudsConnectionChanged(true)
        #expect(presence.wantsWindow)
        presence.windowRequestHandled()
        host.userOpensWindow()
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)
    }

    @Test func launchWindowAlreadyOpenIsClosedOnlyOnce() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        host.userOpensWindow() // SwiftUI's launch window, already up
        presence.didFinishLaunching(atLogin: true)
        #expect(!host.isMainWindowOpen)
        #expect(!presence.isVisible)

        // The next window is the user's.
        host.userOpensWindow()
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)
    }

    @Test func reopeningRightAfterLoginKeepsTheWindow() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.didFinishLaunching(atLogin: true)

        // The user opens BudBridge from Spotlight (or Open Controls) before SwiftUI's window showed.
        presence.windowRequested()
        host.userOpensWindow()
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)
    }

    @Test func reopeningWhileHiddenShowsTheWindow() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.didFinishLaunching(atLogin: true)
        #expect(!presence.isVisible)

        // Finder or Spotlight with no window showing: the label comes back and opens it.
        presence.reopenRequested()
        #expect(presence.wantsWindow)
        #expect(presence.isVisible)
        presence.windowRequestHandled()
        host.userOpensWindow()
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)

        host.userClosesWindow()
        #expect(!presence.isVisible)
    }

    // MARK: - Grace period and the user's window

    @Test func windowOpenedDuringTheGracePeriodStays() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()
        host.userClosesWindow()

        // The earbuds drop and the user opens BudBridge to reconnect them.
        presence.earbudsConnectionChanged(false)
        host.userOpensWindow()
        try await waitUntil { !presence.isInGracePeriod }
        #expect(host.closeCount == 0)
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)

        host.userClosesWindow()
        #expect(!presence.isVisible)
    }

    @Test func windowInUseIsNotClosedWhenTheGracePeriodEnds() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()
        host.isMainWindowKey = true

        // The user presses Disconnect on the Connections page and keeps looking at the window.
        presence.earbudsConnectionChanged(false)
        try await waitUntil { !presence.isInGracePeriod }
        #expect(host.closeCount == 0)
        #expect(presence.isVisible)

        host.userClosesWindow()
        #expect(!presence.isVisible)
    }

    // MARK: - Opening the window

    @Test func reopeningOpensTheWindowDirectlyWhenAViewProvidedTheOpener() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        var opened = 0
        presence.windowOpener = {
            opened += 1
            host.userOpensWindow()
        }
        presence.didFinishLaunching(atLogin: true)
        #expect(!presence.isVisible)

        // Works without the menu-bar label (e.g. the user removed the item).
        presence.reopenRequested()
        #expect(opened == 1)
        #expect(!presence.wantsWindow)
        #expect(host.isMainWindowOpen)
        #expect(presence.isVisible)

        host.userClosesWindow()
        #expect(!presence.isVisible)
    }

    @Test func openOnConnectUsesTheOpener() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        var opened = 0
        presence.windowOpener = {
            opened += 1
            host.userOpensWindow()
        }
        presence.opensWindowOnConnect = true
        presence.didFinishLaunching(atLogin: true)
        presence.earbudsConnectionChanged(true)
        #expect(opened == 1)
        #expect(!presence.wantsWindow)
        #expect(host.isMainWindowOpen)
    }

    @Test func openerThatShowsNothingDoesNotKeepBudBridgeVisible() async throws {
        let setup = makePresence()
        let presence = setup.presence
        var opened = 0
        presence.windowOpener = { opened += 1 } // SwiftUI ignores the request
        presence.didFinishLaunching(atLogin: true)

        presence.reopenRequested()
        #expect(opened == 1)
        #expect(presence.isWindowRequestPending)
        #expect(presence.isVisible)
        try await waitUntil { !presence.isWindowRequestPending }
        #expect(!presence.isVisible)
    }

    @Test func unhandledWindowRequestDoesNotKeepBudBridgeVisible() async throws {
        let setup = makePresence()
        let presence = setup.presence
        presence.didFinishLaunching(atLogin: true)

        // No view has provided the opener and the label never handles the request.
        presence.reopenRequested()
        #expect(presence.wantsWindow)
        #expect(presence.isVisible)
        try await waitUntil { !presence.wantsWindow }
        #expect(!presence.isVisible)
    }

    @Test func manualLaunchWithoutAWindowAsksForOne() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        var opened = 0
        presence.windowOpener = { opened += 1 } // SwiftUI restored no window and ignores the request
        presence.didFinishLaunching(atLogin: false)
        #expect(opened == 1)
        #expect(presence.isVisible)

        // Disconnected and no window ever shows: BudBridge hides once the request expires.
        try await waitUntil { !presence.isWindowRequestPending }
        #expect(!presence.isVisible)
        #expect(!host.isMainWindowOpen)
    }

    @Test func manualLaunchWithAWindowDoesNotAskAgain() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        var opened = 0
        presence.windowOpener = { opened += 1 }
        host.userOpensWindow() // SwiftUI's launch window
        presence.didFinishLaunching(atLogin: false)
        #expect(opened == 0)
        #expect(!presence.isWindowRequestPending)
        #expect(presence.isVisible)
    }

    @Test func windowBroughtBackDuringTheGracePeriodStays() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()

        // Minimized or behind other apps when the earbuds disconnect, then brought back
        // (un-minimized from the Dock), and the user switches to another app.
        presence.earbudsConnectionChanged(false)
        host.userOpensWindow()
        host.isMainWindowKey = false
        try await waitUntil { !presence.isInGracePeriod }
        #expect(host.closeCount == 0)
        #expect(host.isMainWindowOpen)
    }

    @Test func openControlsDuringTheGracePeriodKeepsTheWindow() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()

        presence.earbudsConnectionChanged(false)
        presence.windowRequested() // Open Controls in the menu-bar panel
        try await waitUntil { !presence.isInGracePeriod }
        #expect(host.closeCount == 0)
        #expect(host.isMainWindowOpen)
    }

    // MARK: - Other windows

    @Test func settingsWindowKeepsBudBridgeVisible() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()

        // Disconnected: the user presses ⌘, and then closes the main window.
        host.userOpensSettings()
        host.userClosesWindow()
        #expect(presence.isVisible)
        #expect(host.dockIcon.isEmpty)

        host.userClosesSettings()
        #expect(!presence.isVisible)
        #expect(host.dockIcon == [false])
    }

    @Test func turningTheSettingOnWithSettingsOpenKeepsBudBridgeVisible() {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.showsOnlyWhenConnected = false
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()
        host.userOpensSettings()
        host.userClosesWindow()

        presence.showsOnlyWhenConnected = true
        #expect(presence.isVisible)
        host.userClosesSettings()
        #expect(!presence.isVisible)
    }

    @Test func gracePeriodLeavesSettingsOpenAndVisible() async throws {
        let setup = makePresence()
        let presence = setup.presence
        let host = setup.host
        presence.earbudsConnectionChanged(true)
        presence.didFinishLaunching(atLogin: false)
        host.userOpensWindow()
        host.userOpensSettings()

        presence.earbudsConnectionChanged(false)
        try await waitUntil { !presence.isInGracePeriod }
        #expect(!host.isMainWindowOpen) // the main window still closes
        #expect(presence.isVisible)
        host.userClosesSettings()
        #expect(!presence.isVisible)
    }
}
