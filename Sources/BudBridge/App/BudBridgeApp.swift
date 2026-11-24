import AppKit
import SwiftUI

@main
struct BudBridgeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var coordinator: AppCoordinator { delegate.coordinator }

    var body: some Scene {
        Window("BudBridge", id: "main") {
            RootView(coordinator: coordinator)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BudBridge") { AboutPanel.show() }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh from Earbuds") { coordinator.root.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra(isInserted: menuBarItemShown) {
            MenuBarPanel(viewModel: coordinator.menuBar)
        } label: {
            MenuBarLabel(viewModel: coordinator.menuBar.battery, presence: coordinator.presence)
        }
        .menuBarExtraStyle(.window)

        Settings {
            GeneralSettingsView(viewModel: coordinator.general)
        }
    }

    /// The item follows `AppPresence`; removing it by ⌘-dragging lasts until the next change.
    private var menuBarItemShown: Binding<Bool> {
        Binding(get: { coordinator.presence.isVisible }, set: { _ in })
    }
}

/// Owns the coordinator, so it exists before launch finishes, and tells `AppPresence` how
/// BudBridge was launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.presence.didFinishLaunching(atLogin: AppKitPresenceHost.isLaunchingAtLogin)
    }

    /// Opening BudBridge again (Finder, Spotlight, the Dock) shows the main window. Implementing
    /// this replaces SwiftUI's own reopen handling, so BudBridge opens the window itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        coordinator.presence.reopenRequested()
        return false
    }

    /// BudBridge keeps running without a window, so it notices the earbuds connecting.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarLabel: View {
    let viewModel: BatteryViewModel
    let presence: AppPresence
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let level = viewModel.lowestBud {
                Label("\(level)%", systemImage: "earbuds")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "earbuds")
            }
        }
        // The label is the one view that's always around while BudBridge is visible, so it
        // opens the window when the earbuds connect.
        .onChange(of: presence.wantsWindow, initial: true) { _, wantsWindow in
            guard wantsWindow else { return }
            presence.windowRequestHandled()
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}
