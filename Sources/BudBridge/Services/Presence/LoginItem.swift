import ServiceManagement

/// Whether BudBridge opens when the user logs in.
protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    /// Registered, but the user still has to allow it in System Settings › Login Items.
    var needsApproval: Bool { get }

    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

/// BudBridge itself as a login item. Only works from a signed `BudBridge.app`, not from `swift run`.
final class MainAppLoginItem: LoginItem {
    private var service: SMAppService { .mainApp }

    var isEnabled: Bool { [.enabled, .requiresApproval].contains(service.status) }
    var needsApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
