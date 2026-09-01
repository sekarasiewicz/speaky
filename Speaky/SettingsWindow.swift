import AppKit
import SwiftUI

/// Opening a window from an `LSUIElement` app needs a nudge: an accessory app
/// cannot activate itself, so the Settings window would otherwise appear
/// behind everything else — or seem not to open at all.
///
/// The app is promoted to `.regular` while the window is up (which also gives
/// it a Dock icon and a menu bar), then dropped back to `.accessory` on close.
enum SettingsWindow {
    /// SwiftUI's identifier for the `Settings` scene window.
    private static let identifier = "com_apple_SwiftUI_Settings_window"

    static func open(_ openSettings: OpenSettingsAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettings()

        // The window is created asynchronously; grab it once it exists.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = settingsWindow() else { return }
            window.makeKeyAndOrderFront(nil)
            window.center()
            observeClose(of: window)
        }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == identifier }
            ?? NSApp.windows.first { $0.canBecomeKey && $0.contentView != nil && $0.isVisible }
    }

    private static func observeClose(of window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
