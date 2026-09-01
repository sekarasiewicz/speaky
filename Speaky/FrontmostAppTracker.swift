import AppKit

/// Remembers which app was frontmost before Speaky took focus.
///
/// Every capture path depends on the right app being active: `AXFocusedUIElement`
/// follows system focus, a synthetic ⌘C lands wherever the keyboard points, and
/// the menu-item fallback needs the target app's own menu bar. Opening the menu
/// bar extra makes Speaky frontmost, so without this the reader would inspect
/// itself and always come back empty.
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()

    private(set) var lastExternalApp: NSRunningApplication?

    private init() {}

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self?.lastExternalApp = app
        }

        lastExternalApp = NSWorkspace.shared.frontmostApplication
    }

    /// The app a capture should read from: whatever is frontmost, unless that is
    /// Speaky itself, in which case the app we interrupted.
    var captureTarget: NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return lastExternalApp
        }
        return frontmost ?? lastExternalApp
    }

    /// Brings the capture target back to the front and waits for focus to land
    /// there. Returns false if the switch did not happen in time.
    @discardableResult
    func restoreFocusIfNeeded(timeout: TimeInterval = 0.4) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
              let target = lastExternalApp
        else { return true }

        target.activate()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                // Focus has moved, but the target still needs a moment to take
                // key window before it will answer a copy.
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }
}
