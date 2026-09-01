import Foundation

/// Turns text meant to be *read* into text worth *hearing*.
///
/// A selection is rarely prose. It comes from a terminal, a diff, a Markdown
/// file or a quoted email, and a speech model reads all of that literally: a URL
/// goes out character by character, `>>>` becomes "greater than greater than",
/// box-drawing characters become nothing useful at all. Stripping that noise
/// improves the result more than moving to a more expensive voice does.
///
/// Everything here is deliberately conservative. When a rule is not confident,
/// it leaves the text alone — a slightly awkward reading beats a sentence with
/// its meaning removed.
enum TextCleaner {

    static func clean(_ input: String) -> String {
        var text = input

        text = stripCodeFences(text)
        text = stripMarkdown(text)
        text = replaceLinks(text)
        text = stripQuoting(text)
        text = stripDecoration(text)
        text = stripTerminalPrompts(text)
        text = normalizeWhitespace(text)

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the rules ate almost everything, the input was not what they
        // assumed. Reading the original is better than reading a fragment.
        guard cleaned.count >= input.count / 4 else {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    // MARK: - Rules

    /// Fenced code is announced rather than spelled out. Reading a block of
    /// Swift aloud produces a minute of punctuation.
    private static func stripCodeFences(_ text: String) -> String {
        replacing(text, #"(?m)^\s*```[\s\S]*?```\s*$"#, with: " (code block) ")
    }

    private static func stripMarkdown(_ text: String) -> String {
        var out = text
        out = replacing(out, #"(?m)^\s{0,3}#{1,6}\s+"#, with: "")          // headings
        out = replacing(out, #"(?m)^\s{0,3}[-*+]\s+"#, with: "")           // bullets
        out = replacing(out, #"`([^`\n]+)`"#, with: "$1")                  // inline code
        out = replacing(out, #"\*\*([^*\n]+)\*\*"#, with: "$1")            // bold
        out = replacing(out, #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, with: "$1")  // italics
        out = replacing(out, #"(?m)^\s{0,3}\|.*\|\s*$"#, with: "")         // table rows
        return out
    }

    /// `[label](url)` keeps its label. A bare URL becomes its host, because the
    /// host is the part a listener can act on — the path never is.
    private static func replaceLinks(_ text: String) -> String {
        var out = replacing(text, #"\[([^\]\n]+)\]\((?:[^)\s]+)\)"#, with: "$1")
        out = replacing(out, #"!\[[^\]\n]*\]\([^)\s]+\)"#, with: " (image) ")

        let pattern = #"\bhttps?://([^\s/?#]+)[^\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }

        let range = NSRange(out.startIndex..., in: out)
        var result = out
        // Replace from the back so earlier ranges stay valid.
        for match in regex.matches(in: out, range: range).reversed() {
            guard let full = Range(match.range, in: result),
                  let hostRange = Range(match.range(at: 1), in: result)
            else { continue }
            let host = String(result[hostRange]).replacingOccurrences(of: "www.", with: "")
            result.replaceSubrange(full, with: "link to \(host)")
        }
        return result
    }

    /// Email and diff quoting. `>` at the start of a line is a quote marker, not
    /// a comparison.
    private static func stripQuoting(_ text: String) -> String {
        replacing(text, #"(?m)^\s*(?:>\s*)+"#, with: "")
    }

    /// Rules, box drawing and separator runs carry layout, never meaning.
    private static func stripDecoration(_ text: String) -> String {
        var out = text
        out = replacing(out, #"[─-▟]+"#, with: " ")  // box drawing and blocks
        out = replacing(out, #"(?m)^\s*[-=_*~]{3,}\s*$"#, with: "")                 // horizontal rules
        out = replacing(out, #"[•·▪▸►]+"#, with: " ")
        return out
    }

    /// Shell prompts and list markers at the head of a line.
    private static func stripTerminalPrompts(_ text: String) -> String {
        replacing(text, #"(?m)^\s*[$❯➜›%#]\s+"#, with: "")
    }

    /// Collapses runs of space, and turns a blank line into a sentence break so
    /// the model pauses between paragraphs instead of running them together.
    private static func normalizeWhitespace(_ text: String) -> String {
        var out = replacing(text, #"[ \t]+"#, with: " ")
        out = replacing(out, #"\n{2,}"#, with: ".\n")
        out = replacing(out, #"(?m)[ \t]+$"#, with: "")
        out = replacing(out, #"\.{2,}"#, with: ".")
        return out
    }

    // MARK: -

    private static func replacing(_ text: String, _ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
