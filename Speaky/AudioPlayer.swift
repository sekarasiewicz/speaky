import AVFoundation

/// Plays a stream of raw 24 kHz mono 16-bit PCM as it arrives, and stays
/// seekable while doing it.
///
/// The endpoint is asked for `pcm` precisely so bytes off the socket can be
/// scheduled straight onto a player node — no container to parse and no
/// decoder latency between download and sound.
///
/// Every sample received is retained in `pcm`, because seeking backwards needs
/// audio that has already played. At 24 kHz mono that is 48 KB per second, so
/// even a long article stays in the low tens of megabytes.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    static let sampleRate = 24_000.0

    /// Deinterleaved Float32 — the format the mixer wants. The Int16 payload is
    /// converted on the way in, which avoids format-mismatch crashes on connect.
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    /// Frames per scheduled buffer. Bounded so a long read does not allocate one
    /// enormous float buffer up front.
    private let sliceFrames = 24_000 * 5

    private let lock = NSLock()

    /// Everything received so far, 16-bit little-endian.
    private var pcm = Data()
    /// Absolute frame the current playback run started from.
    private var baseFrame = 0
    /// Absolute frame up to which audio has been handed to the node.
    private var scheduledFrames = 0
    /// Live buffers belonging to the current run.
    private var pending = 0
    /// Bumped on stop and on seek so stale completion callbacks are ignored.
    private var generation = 0
    /// Set once the network side has delivered the last chunk.
    private var streamFinished = false
    /// Playhead remembered across a pause, when the render clock stops.
    private var frozenFrame: Int?
    /// Gate for incoming audio. A network stream keeps delivering for a while
    /// after a stop, and every delivery would otherwise restart the engine.
    private var accepting = false

    /// Called on the main queue once the whole stream has played out.
    var onFinishedPlaying: (() -> Void)?

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Transport

    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = min(max(newValue, 0.5), 2.0) }
    }

    var isPlaying: Bool { player.isPlaying }

    /// Seconds of audio received so far.
    var duration: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Double(pcm.count / 2) / Self.sampleRate
    }

    /// Current playhead in seconds.
    var position: TimeInterval {
        Double(currentFrame) / Self.sampleRate
    }

    func start() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    /// Clears any previous audio and opens the gate for a new stream.
    func begin() {
        reset()
        lock.lock()
        accepting = true
        lock.unlock()
        start()
        player.play()
    }

    func resume() {
        start()
        lock.lock()
        frozenFrame = nil
        lock.unlock()
        player.play()
    }

    func pause() {
        // The render clock stops with the node, so latch the playhead now —
        // otherwise a seek while paused would measure from a frozen sampleTime.
        let frame = currentFrame
        lock.lock()
        frozenFrame = frame
        lock.unlock()
        player.pause()
    }

    /// Clears everything and readies the player for a new piece of text.
    func reset() {
        lock.lock()
        generation &+= 1
        pcm.removeAll(keepingCapacity: false)
        baseFrame = 0
        scheduledFrames = 0
        pending = 0
        streamFinished = false
        frozenFrame = nil
        accepting = false
        lock.unlock()

        player.stop()
    }

    func stop() {
        reset()
        engine.stop()
    }

    // MARK: - Seeking

    /// Moves the playhead by `seconds`, clamped to what has been received.
    /// Seeking past the end of downloaded audio is not possible — that audio
    /// does not exist yet — so a forward seek stops at the buffered edge.
    func seek(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    func seek(to seconds: TimeInterval) {
        let wasPlaying = player.isPlaying

        lock.lock()
        let totalFrames = pcm.count / 2
        let target = min(max(Int(seconds * Self.sampleRate), 0), totalFrames)
        generation &+= 1
        baseFrame = target
        scheduledFrames = target
        pending = 0
        frozenFrame = wasPlaying ? nil : target
        lock.unlock()

        // stop() discards scheduled buffers and resets the node's sample clock,
        // which is what makes `baseFrame + sampleTime` valid again.
        player.stop()
        scheduleTail()

        if wasPlaying {
            start()
            player.play()
        }
    }

    // MARK: - Feeding

    /// Appends a chunk of PCM bytes and schedules whatever is now playable.
    func enqueue(_ data: Data) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        pcm.append(data)
        lock.unlock()

        start()
        scheduleTail()
        if !player.isPlaying, frozenFrame == nil { player.play() }
    }

    /// Signals that no more audio is coming, so the end of the buffer is a real
    /// end rather than a stall.
    func finishStreaming() {
        lock.lock()
        streamFinished = true
        let done = pending == 0 && scheduledFrames == pcm.count / 2
        lock.unlock()
        if done { DispatchQueue.main.async { self.onFinishedPlaying?() } }
    }

    // MARK: - Internals

    private var currentFrame: Int {
        lock.lock()
        if let frozen = frozenFrame { lock.unlock(); return frozen }
        let base = baseFrame
        lock.unlock()

        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return base }

        return base + Int(playerTime.sampleTime)
    }

    /// Hands the node every whole sample that has arrived but not yet been
    /// scheduled, in bounded slices.
    private func scheduleTail() {
        while true {
            lock.lock()
            let totalFrames = pcm.count / 2
            guard scheduledFrames < totalFrames else { lock.unlock(); return }

            let from = scheduledFrames
            let to = min(from + sliceFrames, totalFrames)
            let byteRange = (from * 2)..<(to * 2)
            let slice = Data(pcm[byteRange])
            scheduledFrames = to
            pending += 1
            let current = generation
            lock.unlock()

            guard let buffer = makeBuffer(from: slice) else {
                lock.lock(); pending -= 1; lock.unlock()
                return
            }

            player.scheduleBuffer(buffer) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let stale = current != self.generation
                if !stale { self.pending -= 1 }
                let drained = !stale
                    && self.pending == 0
                    && self.streamFinished
                    && self.scheduledFrames == self.pcm.count / 2
                self.lock.unlock()

                if drained { DispatchQueue.main.async { self.onFinishedPlaying?() } }
            }
        }
    }

    private func makeBuffer(from slice: Data) -> AVAudioPCMBuffer? {
        let frames = slice.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frames)
        slice.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                channel[i] = Float(Int16(littleEndian: samples[i])) / 32_768.0
            }
        }
        return buffer
    }
}
