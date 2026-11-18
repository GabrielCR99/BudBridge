import Foundation
import Observation

/// A flag that turns itself off after a timeout, for placeholders that shouldn't stay up forever.
@Observable
final class ExpiringFlag {
    private(set) var isOn = false

    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(timeout: Duration) {
        self.timeout = timeout
    }

    /// Turns the flag on, restarting the timeout.
    func turnOn() {
        isOn = true
        timer?.cancel()
        timer = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.isOn = false
        }
    }

    func turnOff() {
        isOn = false
        timer?.cancel()
        timer = nil
    }
}
