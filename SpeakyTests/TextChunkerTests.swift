import XCTest
@testable import Speaky

final class TextChunkerTests: XCTestCase {

    func testEmptyInputProducesNoChunks() {
        XCTAssertTrue(TextChunker.chunks("").isEmpty)
        XCTAssertTrue(TextChunker.chunks("   \n ").isEmpty)
    }

    func testShortTextStaysInOneChunk() {
        let chunks = TextChunker.chunks("One sentence. Two sentences.")
        XCTAssertEqual(chunks, ["One sentence. Two sentences."])
    }

    /// Chunks have to stay under the budget, or the point of chunking — getting
    /// the first one speaking quickly — is lost.
    func testChunksStayWithinTheBudget() {
        let sentence = "This sentence is exactly the sort of thing one reads. "
        let chunks = TextChunker.chunks(String(repeating: sentence, count: 40), maxLength: 200)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 200, chunk)
        }
    }

    /// A single sentence longer than the budget cannot be split without cutting
    /// mid-thought, so it goes out on its own oversized.
    func testOversizedSentenceIsNotSplit() {
        let long = String(repeating: "word ", count: 200) + "end."
        let chunks = TextChunker.chunks(long, maxLength: 100)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertGreaterThan(chunks[0].count, 100)
    }

    /// Nothing may be dropped: every word of the input has to survive into some
    /// chunk, or the listener silently loses part of what they selected.
    func testNoWordsAreLost() {
        let input = "Alpha bravo. Charlie delta echo. Foxtrot golf hotel india. Juliett."
        let rejoined = TextChunker.chunks(input, maxLength: 30).joined(separator: " ")

        for word in input.split(whereSeparator: { " .".contains($0) }) {
            XCTAssertTrue(rejoined.contains(word), "lost \(word)")
        }
    }

    /// Abbreviations carry a period that does not end a sentence. Whatever the
    /// tokenizer decides, chunking must not produce empty pieces.
    func testAbbreviationsDoNotProduceEmptyChunks() {
        let chunks = TextChunker.chunks("Meet Dr. Nowak at 5 p.m. sharp. Then we leave.")
        XCTAssertFalse(chunks.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
