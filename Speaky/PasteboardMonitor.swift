import AppKit

/// Watches the pasteboard and remembers who last wrote to it.
///
/// Terminals commonly copy on selection — it is iTerm2's default — which makes
/// the pasteboard a truthful record of the selection in apps that refuse to
/// answer any other way. iTerm2 refuses all of them: it exposes no focused
/// element over system-wide Accessibility, keeps its Copy menu item unvalidated
/// until the menu is opened, and ignores a synthetic ⌘C.
///
/// Recording the source app is what keeps this honest. Text is only ever
/// offered back for the same app it came from, so an unrelated clipboard entry
/// is never mistaken for a selection.
final class PasteboardMonitor {
    static let shared = PasteboardMonitor()

    private(set) var lastText: String?
    private(set) var lastSourceBundleID: String?
    private(set) var lastChange: Date?

    /// Raised while Speaky writes to the pasteboard itself, so its own sentinel
    /// and restore never register as a user copy.
    var isSuppressed = false

    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Re-syncs the counter after Speaky's own writes.
    func resync() {
        lastCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastCount else { return }
        lastCount = pasteboard.changeCount
        guard !isSuppressed else { return }

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        lastText = text
        lastSourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lastChange = Date()
    }

    /// How long a copy still counts as "the current selection".
    ///
    /// Without a bound, a selection made in the same app an hour ago would be
    /// read back as if it were current. Generous enough to cover selecting text
    /// and getting distracted, short enough that it cannot be stale by surprise.
    static let maxAge: TimeInterval = 5 * 60

    /// The remembered text, but only if this very app put it there recently.
    func selection(from app: NSRunningApplication?) -> String? {
        guard let bundleID = app?.bundleIdentifier,
              bundleID == lastSourceBundleID,
              let changed = lastChange,
              Date().timeIntervalSince(changed) < Self.maxAge,
              let text = lastText
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
