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
    private func terminateOtherInstances() {
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        for app in others { app.terminate() }
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
            Text("Czytam \(timecode)")
            Divider()
        case .paused:
            Text("Wstrzymane \(timecode)")
            Divider()
        case .idle:
            EmptyView()
        }

        Button("Czytaj zaznaczenie\(key(.speak))") { controller.speakSelection() }
        Button("Czytaj schowek") { controller.speakClipboard() }

        if controller.state.isActive {
            Divider()
            Button(controller.state == .paused ? "Wznów\(key(.playPause))" : "Pauza\(key(.playPause))") {
                controller.togglePause()
            }
            Button("Cofnij \(seconds)s\(key(.back))") { controller.skip(backwards: true) }
            Button("Do przodu \(seconds)s\(key(.forward))") { controller.skip(backwards: false) }
            Button("Stop") { controller.stop() }
        }

        Divider()
        Button("Ustawienia…") { SettingsWindow.open(openSettings) }
            .keyboardShortcut(",")
        Button("Zakończ") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
