@testable import BudBridge
import Testing

struct OcclusionTrackerTests {
    @Test func reportsOnlyComingIntoView() {
        var tracker = OcclusionTracker()
        let shown = tracker.update(isOnScreen: true)
        let stillOnScreen = tracker.update(isOnScreen: true)
        #expect(shown)
        #expect(!stillOnScreen)

        // Covered by another app, another Space, or the screen locks: not reported.
        let covered = tracker.update(isOnScreen: false)
        let stillCovered = tracker.update(isOnScreen: false)
        #expect(!covered)
        #expect(!stillCovered)

        // In view again (uncovered, back to its Space, unlocked): reported.
        let backInView = tracker.update(isOnScreen: true)
        #expect(backInView)
    }

    @Test func showingAfterACloseCountsAsComingIntoView() {
        var tracker = OcclusionTracker()
        _ = tracker.update(isOnScreen: true)
        tracker.reset()
        let shownAgain = tracker.update(isOnScreen: true)
        #expect(shownAgain)
    }

    @Test func startsOffScreen() {
        var tracker = OcclusionTracker()
        let offScreen = tracker.update(isOnScreen: false)
        #expect(!offScreen)
    }
}
