import Foundation
import NaturalLanguage

/// Splits text into request-sized pieces on sentence boundaries.
///
/// Chunking is what makes playback start fast: the first chunk is already
/// speaking while the rest is still being generated. Chunks are kept large
/// enough (~350 chars) that prosody does not audibly reset every few words.
enum TextChunker {
    static func chunks(_ text: String, maxLength: Int = 350) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        if sentences.isEmpty { sentences = [trimmed] }

        var result: [String] = []
        var current = ""

        for sentence in sentences {
            // A single sentence longer than the budget goes out on its own.
            if sentence.count >= maxLength {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(sentence)
                continue
            }
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxLength {
                current += " " + sentence
            } else {
                result.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
