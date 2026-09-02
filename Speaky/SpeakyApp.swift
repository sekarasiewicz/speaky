import SwiftUI

@main
struct SpeakyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = SpeakyController.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("Speaky", systemImage: menuIcon) {
            MenuContent()
                .environmentObject(controller)
        }

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

struct MenuContent: View {
    @EnvironmentObject private var controller: SpeakyController
    @Environment(\.openSettings) private var openSettings

    private var seconds: Int { Int(AppSettings.shared.skipSeconds) }

    private func key(_ shortcut: HotkeyManager.Shortcut) -> String {
        let combo = AppSettings.shared.combos[shortcut] ?? shortcut.fallback
        return combo.isEmpty ? "" : "  \(combo.display)"
    }

    private var timecode: String {
        func mmss(_ t: TimeInterval) -> String {
            String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
        }
        return "\(mmss(controller.position)) / \(mmss(controller.duration))"
    }

    var body: some View {
        switch controller.state {
        case .error(let message):
            Text(message)
            Divider()
        case .working:
            Text("Reading \(timecode)")
            Divider()
        case .paused:
            Text("Paused \(timecode)")
            Divider()
        case .idle:
            EmptyView()
        }

        Button("Read selection\(key(.speak))") { controller.speakSelection() }
        Button("Read clipboard") { controller.speakClipboard() }

        if controller.state.isActive {
            Divider()
            Button(controller.state == .paused ? "Resume\(key(.playPause))" : "Pause\(key(.playPause))") {
                controller.togglePause()
            }
            Button("Back \(seconds)s\(key(.back))") { controller.skip(backwards: true) }
            Button("Forward \(seconds)s\(key(.forward))") { controller.skip(backwards: false) }
            Button("Stop") { controller.stop() }
        }

        Divider()
        Button("Settings…") { SettingsWindow.open(openSettings) }
            .keyboardShortcut(",")
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
