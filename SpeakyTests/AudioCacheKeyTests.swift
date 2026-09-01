import XCTest
@testable import Speaky

/// The cache key decides whether stored audio is served instead of generated.
/// Dropping any input from it means playing back a voice the user has changed,
/// which is worse than a cache miss and much harder to notice.
final class AudioCacheKeyTests: XCTestCase {

    private let cache = AudioCache.shared
    private let instructions = "Read naturally."

    private func key(text: String = "Hello there.",
                     voice: Voice = .coral,
                     instructions: String? = nil,
                     model: String = "gpt-4o-mini-tts") -> String {
        cache.key(
            text: text,
            voice: voice,
            instructions: instructions ?? self.instructions,
            model: model
        )
    }

    func testSameInputsGiveSameKey() {
        XCTAssertEqual(key(), key())
    }

    func testVoiceChangesTheKey() {
        XCTAssertNotEqual(key(voice: .coral), key(voice: .sage))
    }

    func testInstructionsChangeTheKey() {
        XCTAssertNotEqual(key(), key(instructions: "Read quickly."))
    }

    func testModelChangesTheKey() {
        XCTAssertNotEqual(key(), key(model: "tts-1"))
    }

    func testTextChangesTheKey() {
        XCTAssertNotEqual(key(text: "Hello there."), key(text: "Hello there!"))
    }

    /// Fields are joined with a separator that cannot occur in the values, so
    /// moving a boundary between them cannot produce the same key.
    func testFieldBoundariesCannotBeShifted() {
        XCTAssertNotEqual(
            key(text: "b", instructions: "a"),
            key(text: "a", instructions: "b")
        )
    }

    func testKeyIsAFilenameSafeHexDigest() {
        let value = key()
        XCTAssertEqual(value.count, 64)
        XCTAssertTrue(value.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}
