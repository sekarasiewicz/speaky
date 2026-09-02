import AppKit
import Combine

@MainActor
final class SpeakyController: ObservableObject {
    enum State: Equatable {
        case idle
        case working          // fetching and/or playing
        case paused
        case error(String)

        var isActive: Bool { self == .working || self == .paused }
    }

    static let shared = SpeakyController()

    @Published private(set) var state: State = .idle
    @Published private(set) var lastText: String = ""
    /// Playhead and buffered length, in seconds. Drives the menu readout.
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// Shortcuts another app already owns, so Settings can flag them.
    @Published private(set) var conflicts: Set<HotkeyManager.Shortcut> = []

    private let player = AudioPlayer()
    private let streamer = SpeechStreamer()
    private let settings = AppSettings.shared
    private var task: Task<Void, Never>?
    private var ticker: Timer?
    private var errorClearTask: Task<Void, Never>?

    private init() {
        settings.onRateChange = { [weak player] rate in
            player?.rate = Float(rate)
        }
        player.onFinishedPlaying = { [weak self] in
            guard let self, self.state.isActive else { return }
            self.finish()
        }
    }

    /// Re-reads the bindings from settings and re-registers them. Call after
    /// any rebind so a freed combination is picked up immediately.
    func registerHotkeys() {
        CaptureLog.session("register hotkeys")
        for (shortcut, combo) in settings.combos {
            CaptureLog.write("binding \(shortcut.title) = \(combo.display)")
        }
        conflicts = HotkeyManager.shared.registerAll(
            combos: settings.combos,
            actions: [
                .speak: { [weak self] in self?.speakSelection() },
                .playPause: { [weak self] in self?.togglePause() },
                .back: { [weak self] in self?.skip(backwards: true) },
                .forward: { [weak self] in self?.skip(backwards: false) },
            ]
        )
        CaptureLog.write("conflicts=\(conflicts.map(\.title).joined(separator: ", "))")
    }

    // MARK: - Starting

    /// Hotkey entry point: grab the selection and start talking. Pressing the
    /// hotkey while speaking stops instead, so it doubles as a panic button.
    func speakSelection() {
        if state.isActive {
            stop()
            return
        }
        readSelection()
    }

    /// Reads the selection unconditionally. The panel's row means "read this",
    /// not "toggle", so it must not stop playback the way the hotkey does.
    func readSelection() {
        do {
            let text = try SelectionReader.currentSelection()
            speak(text)
            CaptureLog.write("RESULT ok")
        } catch let error as SelectionError {
            if case .notTrusted = error { SelectionReader.requestTrust() }
            fail(error.localizedDescription)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func speakClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            fail("The clipboard is empty.")
            return
        }
        speak(text)
    }

    func speak(_ rawText: String) {
        let text = settings.cleanUpText ? TextCleaner.clean(rawText) : rawText
        guard !text.isEmpty else {
            fail("Nothing to read after cleaning up the text.")
            return
        }

        let voice = settings.voice
        let instructions = settings.instructions
        let key = settings.apiKey
        let pieces = TextChunker.chunks(text)

        // Only uncached chunks reach the API, so only those cost anything.
        let billable = pieces
            .filter { AudioCache.shared.load(cacheKey(for: $0, voice: voice, instructions: instructions)) == nil }
            .reduce(0) { $0 + $1.count }

        guard confirmIfExpensive(characters: billable) else { return }

        stop()
        lastText = text
        state = .working

        player.rate = Float(settings.rate)
        player.begin()
        startTicker()

        UsageTracker.record(characters: billable)

        task = Task { [player, streamer] in
            do {
                // Sequential by design: downloads outrun playback, so the queue
                // stays fed while chunk order is guaranteed.
                for piece in pieces {
                    try Task.checkCancellation()

                    let cacheKey = AudioCache.shared.key(
                        text: piece,
                        voice: voice,
                        instructions: instructions,
                        model: SpeechStreamer.model
                    )

                    if let cached = AudioCache.shared.load(cacheKey) {
                        player.enqueue(cached)
                        continue
                    }

                    // Collected as it streams, then stored whole. A cancelled
                    // request must not leave a truncated chunk in the cache.
                    var generated = Data()
                    try await streamer.speak(
                        text: piece,
                        voice: voice,
                        instructions: instructions,
                        apiKey: key
                    ) { data in
                        generated.append(data)
                        player.enqueue(data)
                    }
                    AudioCache.shared.store(cacheKey, data: generated)
                }
                player.finishStreaming()
            } catch is CancellationError {
                // stop() already reset the state.
            } catch {
                await MainActor.run {
                    self.player.stop()
                    self.stopTicker()
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func cacheKey(for piece: String, voice: Voice, instructions: String) -> String {
        AudioCache.shared.key(
            text: piece,
            voice: voice,
            instructions: instructions,
            model: SpeechStreamer.model
        )
    }

    /// Guards against an accidental Select All turning into a large bill.
    /// Returns false when the user declines.
    private func confirmIfExpensive(characters: Int) -> Bool {
        let threshold = settings.confirmAboveCharacters
        guard threshold > 0, characters > threshold else { return true }

        let cost = Double(characters) / 1000 * UsageTracker.dollarsPerThousandCharacters

        let alert = NSAlert()
        alert.messageText = "Read \(characters.formatted()) characters?"
        alert.informativeText = String(
            format: "That is about $%.2f of speech. Cached parts are free and not counted.",
            cost
        )
        alert.addButton(withTitle: "Read")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Errors otherwise only showed inside the menu, which has to be opened to
    /// be seen — so a failed hotkey press was indistinguishable from a hotkey
    /// that never fired. An alert beep gives immediate feedback, and the state
    /// clears itself so the menu bar icon does not stay stuck on a warning.
    private func fail(_ message: String) {
        state = .error(message)
        NSSound.beep()

        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .error = self.state else { return }
                self.state = .idle
            }
        }
    }

    // MARK: - Transport

    func togglePause() {
        switch state {
        case .working:
            player.pause()
            state = .paused
        case .paused:
            player.resume()
            state = .working
        default:
            break
        }
    }

    /// Jumps by the configured amount. A forward jump is capped at the end of
    /// what has been downloaded, since audio beyond that does not exist yet.
    func skip(backwards: Bool) {
        guard state.isActive else { return }
        let delta = backwards ? -settings.skipSeconds : settings.skipSeconds
        player.seek(by: delta)
        tick()
    }

    func seek(to seconds: TimeInterval) {
        guard state.isActive else { return }
        player.seek(to: seconds)
        tick()
    }

    func stop() {
        task?.cancel()
        task = nil
        player.stop()
        stopTicker()
        position = 0
        duration = 0
        state = .idle
    }

    private func finish() {
        task = nil
        stopTicker()
        position = 0
        duration = 0
        state = .idle
    }

    // MARK: - Progress

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            // Resolved outside the task: capturing the optional itself would
            // carry a mutable reference across the concurrency boundary.
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        position = player.position
        duration = player.duration
    }
}
