import AppKit

/// The real `PresenceHost`: switches the Dock icon and watches BudBridge's windows through AppKit.
final class AppKitPresenceHost: NSObject, PresenceHost {
    var onMainWindowChange: ((Bool) -> Void)?
    var onOtherWindowsChange: (() -> Void)?

    private var mainWindowOcclusion = OcclusionTracker()

    override init() {
        super.init()
        let center = NotificationCenter.default
        // Becoming key covers windows the user opens or goes back to; the occlusion change also
        // covers a window shown while BudBridge is in the background, such as the one SwiftUI
        // opens at launch. AppKit posts all three on the main thread.
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowOcclusionDidChange(_:)),
                           name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        if Self.isMainWindow(window) {
            _ = mainWindowOcclusion.update(isOnScreen: true)
            onMainWindowChange?(true)
        } else if Self.isOtherWindow(window) {
            onOtherWindowsChange?()
        }
    }

    /// Reports the main window only when it comes into view. Being covered, moving to another
    /// Space, or the screen locking or sleeping isn't the window being shown or brought back.
    @objc private func windowOcclusionDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if Self.isMainWindow(window) {
            let isOnScreen = window.isVisible && window.occlusionState.contains(.visible)
            if mainWindowOcclusion.update(isOnScreen: isOnScreen) { onMainWindowChange?(true) }
        } else if Self.isOtherWindow(window) {
            onOtherWindowsChange?()
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if Self.isMainWindow(window) {
            mainWindowOcclusion.reset()
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

    /// A window of BudBridge's own other than the main one, such as Settings or About (a panel).
    /// The menu-bar extra and the status item sit above the normal level, so they don't count.
    private static func isOtherWindow(_ window: NSWindow) -> Bool {
        !isMainWindow(window) && window.level == .normal && window.styleMask.contains(.titled)
    }

    /// SwiftUI names the window of `Window(_:id:)` after its id ("main", or "main-AppWindow-1").
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue else { return false }
        return id == "main" || id.hasPrefix("main-")
    }
}
