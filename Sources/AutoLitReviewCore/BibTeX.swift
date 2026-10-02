import Foundation

/// What `BibTeX.count` found in a .bib file.
public struct BibTeXSummary: Hashable, Sendable {
    /// Bibliographic entries: every `@type{key, …}` or `@type(key, …)` except
    /// `@string`, `@preamble` and `@comment`.
    public var entries: Int = 0
    /// Citation keys used more than once (compared without regard to case,
    /// as biber does), each listed once, in the order the repeat was found.
    public var duplicateKeys: [String] = []
    /// Entries with no citation key, as in `@article{, title = …}`.
    public var entriesWithoutKey: Int = 0
    /// True when the file ends inside an entry (its braces don't balance).
    public var endsInsideEntry: Bool = false

    public init() {}
}

/// Counts the references in a BibTeX file. This is a counter, not a full
/// parser: it finds each `@` that starts an entry at the top level of the
/// file, reads its type and key, and skips the body by matching braces, so
/// an `@` inside a field value (an e-mail address, say) is never counted.
/// Text between entries is a comment in BibTeX and is ignored.
public enum BibTeX {
    /// Entry types that aren't references.
    public static let nonReferenceTypes: Set<String> = ["string", "preamble", "comment"]

    public static func summary(of text: String) -> BibTeXSummary {
        var result = BibTeXSummary()
        var seenKeys = Set<String>()
        var reportedKeys = Set<String>()
        let s = Array(text.unicodeScalars)
        let n = s.count
        var i = 0

        while i < n {
            guard s[i] == "@" else { i += 1; continue }
            i += 1

            // The entry type (letters, digits, underscores), which BibTeX
            // allows to be separated from the @ by spaces.
            while i < n, isSpace(s[i]) { i += 1 }
            let typeStart = i
            while i < n, isIdentifier(s[i]) { i += 1 }
            guard i > typeStart else { continue }
            let type = String(String.UnicodeScalarView(s[typeStart..<i])).lowercased()

            while i < n, isSpace(s[i]) { i += 1 }
            guard i < n, s[i] == "{" || s[i] == "(" else { continue }
            let parenthesised = s[i] == "("
            i += 1

            if !nonReferenceTypes.contains(type) {
                result.entries += 1
                while i < n, isSpace(s[i]) { i += 1 }
                let keyStart = i
                while i < n, !endsKey(s[i], parenthesised: parenthesised) { i += 1 }
                let key = String(String.UnicodeScalarView(s[keyStart..<i]))
                if key.isEmpty {
                    result.entriesWithoutKey += 1
                } else {
                    let folded = key.lowercased()
                    if !seenKeys.insert(folded).inserted, reportedKeys.insert(folded).inserted {
                        result.duplicateKeys.append(key)
                    }
                }
            }

            // Skip the body. The opening delimiter has been consumed, so a
            // closing brace at depth 0 (or, for @type(…), a closing
            // parenthesis at depth 0) ends the entry.
            var depth = 0
            var closed = false
            while i < n {
                let c = s[i]
                i += 1
                if c == "{" {
                    depth += 1
                } else if c == "}" {
                    if depth > 0 {
                        depth -= 1
                    } else if !parenthesised {
                        closed = true
                        break
                    }
                } else if c == ")", parenthesised, depth == 0 {
                    closed = true
                    break
                }
            }
            if !closed { result.endsInsideEntry = true }
        }
        return result
    }

    /// Reads and summarises a .bib file (UTF-8, or Latin-1 as a fallback).
    public static func summary(contentsOf url: URL) throws -> BibTeXSummary {
        summary(of: try TextSupport.readText(url))
    }

    private static func isIdentifier(_ c: Unicode.Scalar) -> Bool {
        let v = c.value
        return (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || (v >= 48 && v <= 57) || v == 95
    }

    private static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0B}" || c == "\u{0C}"
    }

    private static func endsKey(_ c: Unicode.Scalar, parenthesised: Bool) -> Bool {
        c == "," || c == "{" || c == "}" || isSpace(c) || (parenthesised && c == ")")
    }
}
