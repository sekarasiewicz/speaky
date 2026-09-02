import SwiftUI

@main
struct SpeakyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = SpeakyController.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("Speaky", systemImage: menuIcon) {
            MenuPanel()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }

    private var menuIcon: String {
        switch controller.state {
        case .working: return "waveform.circle.fill"
        case .paused:  return "pause.circle.fill"
        case .error:   return "exclamationmark.circle"
        case .idle:    return "waveform"
        }
    }
}

/// Hotkey registration has to happen at launch, not when the menu is first
/// opened — `MenuBarExtra` builds its content lazily.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        FrontmostAppTracker.shared.start()
        PasteboardMonitor.shared.start()
        SelectionReader.requestTrust()
        SpeakyController.shared.registerHotkeys()
    }

    /// Global hotkeys are claimed by whichever process registers first, so a
    /// leftover copy silently steals them from the new one. Xcode does not kill
    /// the previous run of a windowless app, which makes this easy to hit.
    ///
    /// Only a duplicate of *this exact bundle* is terminated. Matching on bundle
    /// identifier alone also matched the copy in /Applications, so launching a
    /// debug build silently quit the installed one — and the other way round,
    /// which looked like the app closing itself for no reason.
    private func terminateOtherInstances() {
        let ownPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let duplicates = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { app in
            guard app.processIdentifier != ownPID,
                  let url = app.bundleURL
            else { return false }
            return url.resolvingSymlinksInPath().path == ownPath
        }

        for app in duplicates { app.terminate() }
    }
}
