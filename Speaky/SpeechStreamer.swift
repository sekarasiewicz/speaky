import Foundation

enum SpeechError: LocalizedError {
    case missingKey
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Brak klucza OpenAI. Wklej go w Ustawieniach."
        case let .http(status, body):
            return "OpenAI zwróciło \(status): \(body)"
        }
    }
}

/// Calls the OpenAI speech endpoint and hands back PCM bytes as they arrive.
struct SpeechStreamer {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!
    private let model = "gpt-4o-mini-tts"

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
            "model": model,
            "voice": voice.rawValue,
            "input": text,
            "instructions": instructions,
            "response_format": "pcm",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        for try await byte in bytes {
            // Checked inside the byte loop, not just between chunks: a stop
            // during a long download must take effect immediately.
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 9_600 {   // ~0.2 s of audio
                onData(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { onData(buffer) }
    }
}
