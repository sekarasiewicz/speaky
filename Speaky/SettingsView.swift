import SwiftUI

struct SettingsView: View {
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
            Section("OpenAI") {
                SecureField("Klucz API", text: $settings.apiKey, prompt: Text("sk-…"))
                Text("Trzymany w Keychain, nie w bundlu aplikacji.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Głos") {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instrukcje dla modelu")
                    TextEditor(text: $settings.instructions)
                        .font(.body)
                        .frame(height: 70)
                        .border(.separator)
                    Text("Steruje tonem i akcentem. Warto wprost wskazać język.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

            Section("Skróty") {
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
                Text("Kliknij pole i naciśnij kombinację. ⎋ anuluje, ⌫ czyści. △ = kombinacja zajęta przez inną aplikację. abc = ⌥ bez ⌘, na polskim układzie wpisze znak zamiast zadziałać.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Przetestuj głos") {
                    SpeakyController.shared.speak(
                        "Cześć. Tak brzmi wybrany głos przy obecnych ustawieniach."
                    )
                }
                if SelectionReader.isSecureInputEnabled {
                    Label(
                        "Secure Keyboard Entry jest teraz włączone. Dopóki jest, skróty globalne i odczyt przez Cmd+C nie zadziałają w tej aplikacji.",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
                Button("Otwórz ustawienia Dostępności") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
