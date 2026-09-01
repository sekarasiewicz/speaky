import XCTest
@testable import Speaky

final class TextCleanerTests: XCTestCase {

    func testStripsMarkdownEmphasisAndHeadings() {
        let out = TextCleaner.clean("## Heading\n\nSome **bold** and *italic* with `code` text.")
        XCTAssertEqual(out, "Heading.\nSome bold and italic with code text.")
    }

    func testBareURLBecomesItsHost() {
        let out = TextCleaner.clean("See https://github.com/sekarasiewicz/speaky for details.")
        XCTAssertEqual(out, "See link to github.com for details.")
    }

    func testMarkdownLinkKeepsOnlyItsLabel() {
        let out = TextCleaner.clean("Read [the docs](https://example.com/a/b?c=1) now.")
        XCTAssertEqual(out, "Read the docs now.")
    }

    /// Mail quotes nest as "> > ", with spaces between the markers, so a
    /// pattern matching only consecutive angle brackets leaves the inner level
    /// behind.
    func testStripsNestedQuoteMarkers() {
        let out = TextCleaner.clean("> On Monday someone wrote:\n> > nested reply\nMy answer.")
        XCTAssertFalse(out.contains(">"), out)
    }

    /// The character class for box drawing has to reach ICU as a range. Written
    /// with Swift's \u{...} escapes inside a raw string it never matches, and
    /// the failure is silent — the regex still compiles.
    func testStripsBoxDrawing() {
        let out = TextCleaner.clean("┌──────┐\n│ hi   │\n└──────┘\nPlain text here.")
        XCTAssertFalse(out.contains("─"), out)
        XCTAssertFalse(out.contains("│"), out)
        XCTAssertTrue(out.contains("Plain text here."), out)
    }

    func testStripsShellPrompts() {
        let out = TextCleaner.clean("$ npm install\n❯ git status")
        XCTAssertEqual(out, "npm install\ngit status")
    }

    func testAnnouncesFencedCodeRatherThanReadingIt() {
        let out = TextCleaner.clean("Intro line.\n```swift\nlet x = 1\n```\nOutro line.")
        XCTAssertTrue(out.contains("(code block)"), out)
        XCTAssertFalse(out.contains("let x = 1"), out)
    }

    /// The rules are conservative on purpose: an awkward reading beats a
    /// sentence with its meaning removed.
    func testFallsBackToOriginalWhenRulesWouldRemoveMostOfTheText() {
        let input = "| a | b |\n| c | d |\n| e | f |\n| g | h |"
        XCTAssertEqual(TextCleaner.clean(input), input)
    }

    func testPlainProseIsLeftAlone() {
        let input = "This is an ordinary sentence. So is this one."
        XCTAssertEqual(TextCleaner.clean(input), input)
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(TextCleaner.clean("   \n  "), "")
    }
}
