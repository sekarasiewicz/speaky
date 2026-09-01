import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
            VoiceSettings()
                .tabItem { Label("Głos", systemImage: "waveform") }
            ShortcutSettings()
                .tabItem { Label("Skróty", systemImage: "command") }
            DiagnosticsSettings()
                .tabItem { Label("Diagnostyka", systemImage: "stethoscope") }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - Ogólne

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("Klucz API", text: $settings.apiKey, prompt: Text("sk-…"))
                Text("Trzymany w Keychain, nie w bundlu aplikacji.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Uruchamianie") {
                Toggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
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
                        Text("Wymaga zatwierdzenia w Ustawieniach Systemowych.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Otwórz") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                } else {
                    Text("Rejestruje uruchomiony bundle, więc build z Xcode zarejestruje ścieżkę w DerivedData. Włączaj na kopii w /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Uprawnienia") {
                LabeledContent("Dostępność") {
                    Label(
                        SelectionReader.isTrusted ? "Przyznane" : "Brak",
                        systemImage: SelectionReader.isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(SelectionReader.isTrusted ? .green : .orange)
                }
                Button("Otwórz ustawienia Dostępności") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Głos

private struct VoiceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Głos", selection: $settings.voice) {
                    ForEach(Voice.allCases) { voice in
                        Text(voice.label).tag(voice)
                    }
                }

                HStack {
                    Text("Tempo")
                    Slider(value: $settings.rate, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2fx", settings.rate))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }

                Button("Przetestuj głos") {
                    SpeakyController.shared.speak(
                        "Cześć. Tak brzmi wybrany głos przy obecnych ustawieniach."
                    )
                }
            }

            Section("Instrukcje dla modelu") {
                TextEditor(text: $settings.instructions)
                    .font(.body)
                    .frame(height: 90)
                Text("Steruje tonem i akcentem. Warto wprost wskazać język — bez tego polski tekst bywa czytany z angielskim akcentem.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Skróty

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
                                .help("Ten skrót jest już zajęty przez inną aplikację.")
                        }
                        if (settings.combos[shortcut] ?? shortcut.fallback).isDeadKeyRisk {
                            Image(systemName: "textformat.abc")
                                .foregroundStyle(.orange)
                                .help("⌥ bez ⌘ na polskim układzie wpisuje znak diakrytyczny, jeśli skrót zawiedzie.")
                        }
                        KeyRecorder(combo: binding(for: shortcut))
                            .frame(width: 120, height: 24)
                    }
                }

                Button("Przywróć domyślne") {
                    for shortcut in HotkeyManager.Shortcut.allCases {
                        settings.combos[shortcut] = shortcut.fallback
                    }
                    controller.registerHotkeys()
                }
            } footer: {
                Text("Kliknij pole i naciśnij kombinację. ⎋ anuluje, ⌫ czyści. △ = kombinacja zajęta przez inną aplikację. abc = ⌥ bez ⌘, na polskim układzie wpisze znak zamiast zadziałać.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Przewijanie") {
                Picker("Skok", selection: $settings.skipSeconds) {
                    ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { value in
                        Text("\(Int(value)) s").tag(value)
                    }
                }
                Text("Do przodu można przewinąć tylko po pobrany fragment — dalsze audio jeszcze nie istnieje.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostyka

private struct DiagnosticsSettings: View {
    @State private var loggingEnabled = CaptureLog.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Zapisuj log odczytu zaznaczenia", isOn: $loggingEnabled)
                    .onChange(of: loggingEnabled) { _, value in
                        CaptureLog.isEnabled = value
                    }

                HStack {
                    Button("Pokaż log") {
                        NSWorkspace.shared.activateFileViewerSelecting([CaptureLog.url])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: CaptureLog.url.path))

                    Button("Wyczyść log") { CaptureLog.clear() }
                }
            } footer: {
                Text("Zapisuje do ~/Library/Logs/Speaky/capture.log, co zwrócił każdy z czterech poziomów odczytu. Domyślnie wyłączone — zapisuje przy każdym naciśnięciu skrótu i notuje długość zaznaczonego tekstu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if SelectionReader.isSecureInputEnabled {
                Section {
                    Label(
                        "Secure Keyboard Entry jest teraz włączone. Dopóki jest, skróty globalne i odczyt przez ⌘C nie zadziałają w tej aplikacji.",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}
