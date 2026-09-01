import CryptoKit
import Foundation

/// On-disk cache of generated speech, keyed by everything that affects the audio.
///
/// Re-listening is common — you replay a paragraph you half-heard — and without
/// a cache that means paying for and waiting on identical audio a second time.
/// Cached chunks skip the network entirely, so playback starts instantly rather
/// than after the preroll.
///
/// Caching happens per chunk rather than per selection. Chunking is
/// deterministic, so two overlapping selections of the same article share every
/// chunk they have in common instead of only matching when identical.
final class AudioCache {
    static let shared = AudioCache()

    /// Total budget before least-recently-used entries are dropped.
    /// 24 kHz mono 16-bit is 48 KB per second, so this holds roughly an hour.
    private let maxBytes = 200 * 1024 * 1024

    private let directory: URL
    private let queue = DispatchQueue(label: "dev.karasiewicz.Speaky.cache", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Speaky/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Everything that changes the audio goes into the key. Leaving out the
    /// instructions or the model would serve a voice the user has since changed.
    func key(text: String, voice: Voice, instructions: String, model: String) -> String {
        let payload = "\(model)\u{1F}\(voice.rawValue)\u{1F}\(instructions)\u{1F}\(text)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func load(_ key: String) -> Data? {
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }

        // Touch it so eviction sees this as recently used.
        queue.async {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path
            )
        }
        return data
    }

    func store(_ key: String, data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [directory] in
            try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
            self.evictIfNeeded()
        }
    }

    /// Bytes currently held.
    var size: Int {
        contents().reduce(0) { $0 + $1.size }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: -

    private struct Entry {
        let url: URL
        let size: Int
        let modified: Date
    }

    private func contents() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { return nil }
            return Entry(url: url, size: size, modified: modified)
        }
    }

    private func evictIfNeeded() {
        var entries = contents()
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }

        entries.sort { $0.modified < $1.modified }   // oldest first
        for entry in entries {
            guard total > maxBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
