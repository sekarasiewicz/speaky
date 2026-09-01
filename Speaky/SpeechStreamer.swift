import Foundation

enum SpeechError: LocalizedError {
    case missingKey
    case http(status: Int, body: String)
    case interrupted

    /// Worth another attempt: rate limiting and server faults are transient,
    /// a bad key or a malformed request is not.
    var isRetryable: Bool {
        if case let .http(status, _) = self {
            return status == 429 || (500...599).contains(status)
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No OpenAI key. Paste one in Settings."
        case let .http(status, body):
            return "OpenAI returned \(status): \(body)"
        case .interrupted:
            return "The connection dropped while audio was playing." 
        }
    }
}

/// Calls the OpenAI speech endpoint and hands back PCM bytes as they arrive.
struct SpeechStreamer {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!
    private let maxRetries = 2
    static let model = "gpt-4o-mini-tts"

    /// Streams one chunk of text. `onData` is invoked repeatedly on a
    /// background task as bytes come off the socket.
    func speak(
        text: String,
        voice: Voice,
        instructions: String,
        apiKey: String,
        onData: @escaping (Data) -> Void
    ) async throws {
        guard !apiKey.isEmpty else { throw SpeechError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": Self.model,
            "voice": voice.rawValue,
            "input": text,
            "instructions": instructions,
            "response_format": "pcm",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Retried only while nothing has been handed to the player yet. Once
        // audio is flowing, a second attempt would replay the opening of the
        // chunk on top of what is already queued.
        var attempt = 0
        while true {
            do {
                try await stream(request, onData: onData)
                return
            } catch let error as SpeechError where error.isRetryable && attempt < maxRetries {
                attempt += 1
            } catch let error as URLError where Self.isTransient(error) && attempt < maxRetries {
                attempt += 1
            }

            // 0.5 s, then 1 s. Short enough not to feel hung, long enough for a
            // rate limit window to move on.
            try await Task.sleep(for: .seconds(0.5 * pow(2, Double(attempt - 1))))
            try Task.checkCancellation()
        }
    }

    private func stream(_ request: URLRequest, onData: @escaping (Data) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw SpeechError.http(
                status: http.statusCode,
                body: String(data: body, encoding: .utf8) ?? ""
            )
        }

        // Batch bytes so the player is not woken once per byte.
        var buffer = Data()
        buffer.reserveCapacity(9_600)
        var delivered = false

        do {
            for try await byte in bytes {
                // Checked inside the byte loop, not just between chunks: a stop
                // during a long download must take effect immediately.
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 9_600 {   // ~0.2 s of audio
                    onData(buffer)
                    delivered = true
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            // A drop mid-stream cannot be retried without duplicating audio.
            throw delivered ? SpeechError.interrupted : error
        }

        if !buffer.isEmpty { onData(buffer) }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
