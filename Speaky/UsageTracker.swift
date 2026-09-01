import Foundation

/// Counts characters actually sent to the speech API.
///
/// The app spends money on a keystroke, with nothing in the interface saying how
/// much. Cached chunks cost nothing and are deliberately not counted, so the
/// figure reflects spending rather than reading.
enum UsageTracker {
    /// Price per 1000 characters for `gpt-4o-mini-tts`, in US dollars.
    ///
    /// Hard-coded because the API does not report cost, and clearly an estimate:
    /// it will drift when OpenAI changes pricing.
    static let dollarsPerThousandCharacters = 0.015

    private static let charactersKey = "usage.characters"
    private static let sinceKey = "usage.since"

    static var characters: Int {
        UserDefaults.standard.integer(forKey: charactersKey)
    }

    static var since: Date {
        UserDefaults.standard.object(forKey: sinceKey) as? Date ?? {
            let now = Date()
            UserDefaults.standard.set(now, forKey: sinceKey)
            return now
        }()
    }

    static var estimatedDollars: Double {
        Double(characters) / 1000 * dollarsPerThousandCharacters
    }

    static func record(characters count: Int) {
        guard count > 0 else { return }
        _ = since   // make sure the start date exists before the first count
        UserDefaults.standard.set(characters + count, forKey: charactersKey)
    }

    static func reset() {
        UserDefaults.standard.set(0, forKey: charactersKey)
        UserDefaults.standard.set(Date(), forKey: sinceKey)
    }
}
