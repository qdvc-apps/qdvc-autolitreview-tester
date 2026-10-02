import Foundation

/// One entry's citation key and the line its entry starts on.
public struct KeyOccurrence: Hashable, Sendable {
    /// The key as written in the file.
    public let key: String
    /// The 1-based line of the entry's `@`.
    public let line: Int

    public init(key: String, line: Int) {
        self.key = key
        self.line = line
    }

    /// "Smith2025 (line 94)".
    public var description: String { "\(key) (line \(line))" }
}

/// A citation key shared by two or more entries. Keys are compared without
/// regard to case, as biber does, so `Smith2025` and `smith2025` clash.
public struct KeyClash: Hashable, Sendable {
    /// Every entry with the key, in file order (at least two).
    public let occurrences: [KeyOccurrence]

    public init(occurrences: [KeyOccurrence]) {
        self.occurrences = occurrences
    }

    /// The key as first written.
    public var key: String { occurrences.first?.key ?? "" }

    /// "Smith2025 (line 94) and Smith2025 (line 255)".
    public var description: String { TextSupport.list(occurrences.map(\.description)) }
}

/// What `BibTeX.summary` found in a .bib file.
public struct BibTeXSummary: Hashable, Sendable {
    /// Bibliographic entries: every `@type{key, …}` or `@type(key, …)` except
    /// `@string`, `@preamble` and `@comment`.
    public var entries: Int = 0
    /// Citation keys shared by separate entries, in the order of each key's
    /// first entry. The tool under test produces these, so they are reported
    /// for information rather than as a problem.
    public var keyClashes: [KeyClash] = []
    /// Entries with no citation key, as in `@article{, title = …}`.
    public var entriesWithoutKey: Int = 0
    /// True when the file ends inside an entry (its braces don't balance).
    public var endsInsideEntry: Bool = false
    /// The distinct dates after "EXPORT DATE:" in the file, earliest first
    /// (usually one, from the exporter's header).
    public var exportDates: [ExportDate] = []

    public init() {}
}

/// Counts the references in a BibTeX file. This is a counter, not a full
/// parser: it finds each `@` that starts an entry at the top level of the
/// file, reads its type and key, and skips the body by matching braces, so
/// an `@` inside a field value (an e-mail address, say) is never counted.
/// Text between entries is a comment in BibTeX and is ignored. Unlike
/// BibTeX, it accepts spaces inside citation keys.
public enum BibTeX {
    /// Entry types that aren't references.
    public static let nonReferenceTypes: Set<String> = ["string", "preamble", "comment"]

    public static func summary(of text: String) -> BibTeXSummary {
        var result = BibTeXSummary()
        var occurrencesByKey: [String: [KeyOccurrence]] = [:]
        var keyOrder: [String] = []
        let s = Array(text.unicodeScalars)
        let n = s.count
        var i = 0
        // Line numbers: `line` is the line of `s[lineCursor]`, which only
        // moves forward, so the whole file is walked once.
        var line = 1
        var lineCursor = 0

        while i < n {
            guard s[i] == "@" else { i += 1; continue }
            while lineCursor < i {
                if s[lineCursor] == "\n" { line += 1 }
                lineCursor += 1
            }
            let entryLine = line
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
                // Spaces are tolerated inside a key (the tool under test
                // sometimes writes them), so only trailing ones are dropped.
                var keyEnd = i
                while keyEnd > keyStart, s[keyEnd - 1] == " " { keyEnd -= 1 }
                let key = String(String.UnicodeScalarView(s[keyStart..<keyEnd]))
                if key.isEmpty {
                    result.entriesWithoutKey += 1
                } else {
                    let folded = key.lowercased()
                    if occurrencesByKey[folded] == nil { keyOrder.append(folded) }
                    occurrencesByKey[folded, default: []].append(KeyOccurrence(key: key, line: entryLine))
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
        result.keyClashes = keyOrder.compactMap { folded in
            guard let occurrences = occurrencesByKey[folded], occurrences.count > 1 else { return nil }
            return KeyClash(occurrences: occurrences)
        }
        result.exportDates = ExportDate.find(in: text)
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

    /// What ends a citation key. A space doesn't: keys like `Smith 2020`
    /// are tolerated, though BibTeX itself doesn't allow them. Tabs and line
    /// breaks still do.
    private static func endsKey(_ c: Unicode.Scalar, parenthesised: Bool) -> Bool {
        c == "," || c == "{" || c == "}" || (c != " " && isSpace(c)) || (parenthesised && c == ")")
    }
}
