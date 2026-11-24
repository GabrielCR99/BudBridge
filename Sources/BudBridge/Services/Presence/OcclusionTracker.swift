/// Turns the main window's occlusion changes into "it came into view" events.
///
/// AppKit posts an occlusion change both when a window comes into view and when it leaves it
/// (covered by another app, on another Space, the screen locked or asleep). Only coming into view
/// means the window was shown, so only that is reported.
struct OcclusionTracker {
    private var wasOnScreen = false

    /// Records whether the window is on screen now. Returns `true` only when it just came into view.
    mutating func update(isOnScreen: Bool) -> Bool {
        defer { wasOnScreen = isOnScreen }
        return isOnScreen && !wasOnScreen
    }

    /// The window closed, so the next time it's on screen counts as coming into view.
    mutating func reset() {
        wasOnScreen = false
    }
}
