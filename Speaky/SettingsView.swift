import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            VoiceSettings()
                .tabItem { Label("Voice", systemImage: "waveform") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            DiagnosticsSettings()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $settings.apiKey, prompt: Text("sk-…"))
                Text("Stored in the login keychain, never in the app bundle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        if let error = LaunchAtLogin.set(value) {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        } else {
                            launchError = nil
                        }
                    }

                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if LaunchAtLogin.needsApproval {
                    HStack {
                        Text("Needs approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                } else {
                    Text("Registers whichever bundle is running, so a build started from Xcode registers a DerivedData path. Enable this on a copy in /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    Label(
                        SelectionReader.isTrusted ? "Granted" : "Missing",
                        systemImage: SelectionReader.isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(SelectionReader.isTrusted ? .green : .orange)
                }
                Button("Open Accessibility settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                Text("Read at process start only — after granting it, relaunch Speaky.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice

private struct VoiceSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var usageRefresh = 0

    private var usageSummary: String {
        _ = usageRefresh   // recompute after a reset
        let characters = UsageTracker.characters
        let since = UsageTracker.since.formatted(date: .abbreviated, time: .omitted)
        return String(format: "%@ chars ≈ $%.2f since %@",
                      characters.formatted(), UsageTracker.estimatedDollars, since)
    }

    var body: some View {
        Form {
            Section {
                Picker("Voice", selection: $settings.voice) {
                    ForEach(Voice.allCases) { voice in
                        Text(voice.label).tag(voice)
                    }
                }

                HStack {
                    Text("Speed")
                    Slider(value: $settings.rate, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2fx", settings.rate))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }

                Button("Test voice") {
                    SpeakyController.shared.speak(
                        "Hello. This is how the selected voice sounds with the current settings."
                    )
                }
            }

            Section("Spending") {
                Picker("Confirm above", selection: $settings.confirmAboveCharacters) {
                    Text("Never").tag(0)
                    Text("2 000 characters").tag(2_000)
                    Text("5 000 characters").tag(5_000)
                    Text("20 000 characters").tag(20_000)
                }

                LabeledContent("Generated") {
                    Text(usageSummary)
                        .monospacedDigit()
                }
                Button("Reset counter") {
                    UsageTracker.reset()
                    usageRefresh &+= 1
                }
                Text("Counts only characters actually sent to OpenAI — cached audio is free and not counted. Cost is an estimate at $\(UsageTracker.dollarsPerThousandCharacters, specifier: "%.3f") per 1000 characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text") {
                Toggle("Clean up before reading", isOn: $settings.cleanUpText)
                Text("Strips Markdown, quoting, box drawing and shell prompts, and reads a URL as its host rather than character by character. Falls back to the original if the rules would remove most of the text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model instructions") {
                TextEditor(text: $settings.instructions)
                    .font(.body)
                    .frame(height: 90)
                Text("Steers tone and accent. Naming the language explicitly is worth it — without it, text in some languages is read with an English accent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var controller = SpeakyController.shared

    /// Writing through the dictionary re-registers, so a freed combination
    /// takes effect without a relaunch.
    private func binding(for shortcut: HotkeyManager.Shortcut) -> Binding<KeyCombo> {
        Binding(
            get: { settings.combos[shortcut] ?? shortcut.fallback },
            set: {
                settings.combos[shortcut] = $0
                controller.registerHotkeys()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyManager.Shortcut.allCases) { shortcut in
                    HStack {
                        Text(shortcut.title)
                        Spacer()
                        if controller.conflicts.contains(shortcut) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Another app already owns this combination.")
                        }
                        if (settings.combos[shortcut] ?? shortcut.fallback).isDeadKeyRisk {
                            Image(systemName: "textformat.abc")
                                .foregroundStyle(.orange)
                                .help("⌥ without ⌘ composes a diacritic on some layouts if the shortcut fails.")
                        }
                        KeyRecorder(combo: binding(for: shortcut))
                            .frame(width: 120, height: 24)
                    }
                }

                Button("Restore defaults") {
                    for shortcut in HotkeyManager.Shortcut.allCases {
                        settings.combos[shortcut] = shortcut.fallback
                    }
                    controller.registerHotkeys()
                }
            } footer: {
                Text("Click a field and press a combination. ⎋ cancels, ⌫ clears. △ means another app already owns it. abc means ⌥ without ⌘, which types a character instead of firing on layouts where Option composes diacritics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Seeking") {
                Picker("Skip by", selection: $settings.skipSeconds) {
                    ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { value in
                        Text("\(Int(value))s").tag(value)
                    }
                }
                Text("Skipping forward stops at the buffered edge — audio beyond it has not been generated yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSettings: View {
    @State private var loggingEnabled = CaptureLog.isEnabled
    @State private var cacheSize = 0

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file)
    }

    var body: some View {
        Form {
            Section("Audio cache") {
                LabeledContent("Stored", value: formattedCacheSize)
                Button("Clear cache") {
                    AudioCache.shared.clear()
                    cacheSize = AudioCache.shared.size
                }
                .disabled(cacheSize == 0)
                Text("Generated speech is kept per chunk, so replaying something already read costs nothing and starts instantly. Evicted least-recently-used above 200 MB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Trace selection capture", isOn: $loggingEnabled)
                    .onChange(of: loggingEnabled) { _, value in
                        CaptureLog.isEnabled = value
                    }

                HStack {
                    Button("Show log") {
                        NSWorkspace.shared.activateFileViewerSelecting([CaptureLog.url])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: CaptureLog.url.path))

                    Button("Clear log") { CaptureLog.clear() }
                }
            } footer: {
                Text("Writes what each of the four capture tiers saw to ~/Library/Logs/Speaky/capture.log. Off by default: it writes on every hotkey press and records the length of whatever was selected. Turn it on when an app reads as silent, and attach the log to a bug report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if SelectionReader.isSecureInputEnabled {
                Section {
                    Label(
                        "Secure Keyboard Entry is currently on. While it is, global shortcuts and ⌘C-based capture will not work in that app.",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .task { cacheSize = AudioCache.shared.size }
    }
}
