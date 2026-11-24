import AppKit

/// The real `PresenceHost`: switches the Dock icon and watches BudBridge's windows through AppKit.
final class AppKitPresenceHost: NSObject, PresenceHost {
    var onMainWindowChange: ((Bool) -> Void)?
    var onOtherWindowsChange: (() -> Void)?

    override init() {
        super.init()
        let center = NotificationCenter.default
        // Becoming key covers windows the user opens; the occlusion change also covers a window
        // shown while BudBridge is in the background, such as the one SwiftUI opens at launch.
        // AppKit posts all three on the main thread.
        center.addObserver(self, selector: #selector(windowDidShow(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidShow(_:)),
                           name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowDidShow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        if Self.isMainWindow(window) {
            onMainWindowChange?(true)
        } else if Self.isOtherWindow(window) {
            onOtherWindowsChange?()
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if Self.isMainWindow(window) {
            onMainWindowChange?(false)
        } else if Self.isOtherWindow(window) {
            // The window is still visible while it's about to close; check once it's gone.
            Task { @MainActor [weak self] in self?.onOtherWindowsChange?() }
        }
    }

    var isMainWindowOpen: Bool {
        NSApp.windows.contains { Self.isMainWindow($0) && $0.isVisible }
    }

    var hasOtherWindowsOpen: Bool {
        NSApp.windows.contains { Self.isOtherWindow($0) && $0.isVisible }
    }

    var isMainWindowKey: Bool {
        NSApp.isActive && NSApp.keyWindow.map(Self.isMainWindow) == true
    }

    func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    func closeMainWindow() {
        for window in NSApp.windows where Self.isMainWindow(window) {
            window.close()
        }
    }

    /// Whether the current launch was macOS opening BudBridge at login. Only meaningful while
    /// the app is finishing launching.
    static var isLaunchingAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// A window of BudBridge's own other than the main one, such as Settings or About. Panels
    /// (the menu-bar extra) and windows that can't be main (the status item) don't count.
    private static func isOtherWindow(_ window: NSWindow) -> Bool {
        !isMainWindow(window) && window.canBecomeMain && !(window is NSPanel)
    }

    /// SwiftUI names the window of `Window(_:id:)` after its id ("main", or "main-AppWindow-1").
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue else { return false }
        return id == "main" || id.hasPrefix("main-")
    }
}
