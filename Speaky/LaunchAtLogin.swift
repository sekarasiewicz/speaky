import ServiceManagement

/// Registers the app as a login item through `SMAppService`.
///
/// The service registers whatever bundle is running, so a build launched from
/// Xcode registers its DerivedData path — which stops working the moment that
/// build is replaced. Worth enabling only on a copy living in /Applications.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has to approve the item in System Settings before it
    /// will actually run.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns the error, if any, so the UI can say what went wrong rather than
    /// silently flipping the toggle back.
    @discardableResult
    static func set(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
