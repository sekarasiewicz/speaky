import Foundation
import Combine

/// OpenAI TTS voices. Names are the API values.
enum Voice: String, CaseIterable, Identifiable {
    case alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var apiKey: String {
        didSet { KeychainStore.save(apiKey) }
    }
    @Published var voice: Voice {
        didSet { defaults.set(voice.rawValue, forKey: "voice") }
    }
    /// Playback rate multiplier applied locally, 0.5...2.0.
    @Published var rate: Double {
        didSet { defaults.set(rate, forKey: "rate") }
    }
    /// How far ⌥⌘← / ⌥⌘→ jump, in seconds.
    @Published var skipSeconds: Double {
        didSet { defaults.set(skipSeconds, forKey: "skipSeconds") }
    }
    /// Steers tone and, importantly, language for `gpt-4o-mini-tts`.
    @Published var instructions: String {
        didSet { defaults.set(instructions, forKey: "instructions") }
    }

    /// Per-action hotkeys, rebindable because global combinations collide.
    @Published var combos: [HotkeyManager.Shortcut: KeyCombo] {
        didSet { persistCombos() }
    }

    private let defaults = UserDefaults.standard

    private init() {
        apiKey = KeychainStore.load() ?? ""
        voice = Voice(rawValue: defaults.string(forKey: "voice") ?? "") ?? .coral
        rate = defaults.object(forKey: "rate") as? Double ?? 1.0
        skipSeconds = defaults.object(forKey: "skipSeconds") as? Double ?? 10
        // Bindings saved before the default moved off Option are discarded once,
        // so an existing install picks up the new, safer combinations.
        let storedVersion = defaults.integer(forKey: "combosVersion")
        let migrating = storedVersion < 2
        if migrating { defaults.set(2, forKey: "combosVersion") }

        var loaded: [HotkeyManager.Shortcut: KeyCombo] = [:]
        for shortcut in HotkeyManager.Shortcut.allCases {
            let key = "combo.\(shortcut.rawValue)"
            if !migrating,
               let data = defaults.data(forKey: key),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                loaded[shortcut] = combo
            } else {
                loaded[shortcut] = shortcut.fallback
            }
        }
        combos = loaded

        instructions = defaults.string(forKey: "instructions")
            ?? "Read the text in its original language with a natural, calm, conversational delivery. If the text is Polish, use native Polish pronunciation without an English accent."
    }

    private func persistCombos() {
        for (shortcut, combo) in combos {
            let key = "combo.\(shortcut.rawValue)"
            defaults.set(try? JSONEncoder().encode(combo), forKey: key)
        }
    }
}
