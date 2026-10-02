import Foundation

// MARK: - Parsed entries

/// One BibTeX entry with its fields: names lowercased, values with their
/// outer delimiters removed but inner braces and LaTeX kept (see
/// `LaTeX.clean` for display).
public struct BibEntry: Hashable, Sendable {
    public var type: String
    public var key: String
    public var fields: [String: String]
    /// The 1-based line of the entry's `@`.
    public var line: Int

    public init(type: String, key: String = "", fields: [String: String] = [:], line: Int = 1) {
        self.type = type
        self.key = key
        self.fields = fields
        self.line = line
    }

    public subscript(_ name: String) -> String? { fields[name] }

    /// The first of `names` with a non-empty value.
    public func first(_ names: String...) -> String? {
        for name in names {
            if let value = fields[name], !value.trimmed.isEmpty { return value }
        }
        return nil
    }
}

extension BibTeX {
    /// Parses every reference entry in `text` with its fields. Handles brace-
    /// and quote-delimited values, nested braces, numbers, `#` concatenation,
    /// `@string` macros and the standard month macros (`jan`…`dec`).
    /// `@comment` and `@preamble` are skipped. Like `summary(of:)`, it accepts
    /// spaces inside citation keys.
    public static func entries(in text: String) -> [BibEntry] {
        var parser = EntryParser(text)
        return parser.parseAll()
    }
}

private struct EntryParser {
    let s: [Unicode.Scalar]
    var i = 0
    var line = 1
    var lineCursor = 0
    var macros: [String: String] = [
        "jan": "January", "feb": "February", "mar": "March", "apr": "April", "may": "May", "jun": "June",
        "jul": "July", "aug": "August", "sep": "September", "oct": "October", "nov": "November", "dec": "December",
    ]

    init(_ text: String) { s = Array(text.unicodeScalars) }

    var n: Int { s.count }

    mutating func parseAll() -> [BibEntry] {
        var entries: [BibEntry] = []
        while i < n {
            guard s[i] == "@" else { i += 1; continue }
            while lineCursor < i {
                if s[lineCursor] == "\n" { line += 1 }
                lineCursor += 1
            }
            let entryLine = line
            i += 1
            skipSpace()
            let typeStart = i
            while i < n, isIdentifier(s[i]) { i += 1 }
            guard i > typeStart else { continue }
            let type = text(typeStart..<i).lowercased()
            skipSpace()
            guard i < n, s[i] == "{" || s[i] == "(" else { continue }
            let close: Unicode.Scalar = s[i] == "{" ? "}" : ")"
            i += 1
            switch type {
            case "comment", "preamble":
                skipBody(close: close)
            case "string":
                let fields = parseFields(close: close)
                for (name, value) in fields { macros[name] = value }
            default:
                skipSpace()
                let keyStart = i
                while i < n, s[i] != ",", s[i] != close, s[i] != "\n", s[i] != "{", s[i] != "}" { i += 1 }
                let key = text(keyStart..<i).trimmed
                if i < n, s[i] == "," { i += 1 }
                let fields = parseFields(close: close)
                entries.append(BibEntry(type: type, key: key, fields: fields, line: entryLine))
            }
        }
        return entries
    }

    /// `name = value, …` up to and including the closing delimiter.
    mutating func parseFields(close: Unicode.Scalar) -> [String: String] {
        var fields: [String: String] = [:]
        while i < n {
            while i < n, isSpace(s[i]) || s[i] == "," { i += 1 }
            guard i < n else { break }
            if s[i] == close { i += 1; break }
            let nameStart = i
            while i < n, isFieldNameCharacter(s[i]) { i += 1 }
            let name = text(nameStart..<i).lowercased()
            skipSpace()
            guard !name.isEmpty, i < n, s[i] == "=" else {
                // Not a field: skip to the next comma or the end of the entry.
                if !skipToNextField(close: close) { break }
                continue
            }
            i += 1
            fields[name] = parseValue(close: close)
        }
        return fields
    }

    /// One value: parts joined by `#`.
    mutating func parseValue(close: Unicode.Scalar) -> String {
        var value = ""
        while i < n {
            skipSpace()
            guard i < n else { break }
            if s[i] == "{" {
                i += 1
                let start = i
                var depth = 0
                while i < n {
                    if s[i] == "{" { depth += 1 } else if s[i] == "}" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    i += 1
                }
                value += text(start..<min(i, n))
                if i < n { i += 1 }
            } else if s[i] == "\"" {
                i += 1
                let start = i
                var depth = 0
                while i < n {
                    if s[i] == "{" { depth += 1 } else if s[i] == "}" { depth = max(0, depth - 1) }
                    else if s[i] == "\"", depth == 0 { break }
                    i += 1
                }
                value += text(start..<min(i, n))
                if i < n { i += 1 }
            } else {
                let start = i
                while i < n, !isSpace(s[i]), s[i] != ",", s[i] != "#", s[i] != close, s[i] != "}" { i += 1 }
                let token = text(start..<i)
                if token.isEmpty { break }
                value += token.allSatisfy(\.isNumber) ? token : (macros[token.lowercased()] ?? token)
            }
            skipSpace()
            if i < n, s[i] == "#" { i += 1 } else { break }
        }
        return value.trimmed
    }

    /// Skips a malformed field. Returns false at the end of the entry.
    mutating func skipToNextField(close: Unicode.Scalar) -> Bool {
        var depth = 0
        while i < n {
            let c = s[i]
            if c == "{" { depth += 1 } else if c == "}" {
                if depth == 0 { if close == "}" { i += 1; return false } } else { depth -= 1 }
            } else if c == close, depth == 0 { i += 1; return false }
            else if c == ",", depth == 0 { i += 1; return true }
            i += 1
        }
        return false
    }

    mutating func skipBody(close: Unicode.Scalar) {
        var depth = 0
        while i < n {
            let c = s[i]
            i += 1
            if c == "{" { depth += 1 } else if c == "}" {
                if depth > 0 { depth -= 1 } else if close == "}" { return }
            } else if c == ")", close == ")", depth == 0 { return }
        }
    }

    mutating func skipSpace() { while i < n, isSpace(s[i]) { i += 1 } }

    func text(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(s[range])) }

    func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }

    func isIdentifier(_ c: Unicode.Scalar) -> Bool {
        let v = c.value
        return (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || (v >= 48 && v <= 57) || v == 95
    }

    func isFieldNameCharacter(_ c: Unicode.Scalar) -> Bool {
        isIdentifier(c) || c == "-" || c == ":" || c == "."
    }
}

// MARK: - LaTeX to text

/// Turns BibTeX field values into display text: accent commands become
/// accented letters, escaped characters become themselves, formatting
/// commands keep their argument, braces go, `--` and `---` become dashes,
/// `~` a space, and runs of whitespace one space.
public enum LaTeX {
    private static let accents: [Unicode.Scalar: Unicode.Scalar] = [
        "\"": "\u{0308}", "'": "\u{0301}", "`": "\u{0300}", "^": "\u{0302}", "~": "\u{0303}",
        "=": "\u{0304}", ".": "\u{0307}",
    ]
    private static let letterAccents: [String: Unicode.Scalar] = [
        "c": "\u{0327}", "v": "\u{030C}", "u": "\u{0306}", "H": "\u{030B}", "k": "\u{0328}", "r": "\u{030A}",
    ]
    private static let symbols: [String: String] = [
        "ss": "\u{DF}", "o": "\u{F8}", "O": "\u{D8}", "aa": "\u{E5}", "AA": "\u{C5}", "ae": "\u{E6}",
        "AE": "\u{C6}", "oe": "\u{153}", "OE": "\u{152}", "l": "\u{142}", "L": "\u{141}", "i": "\u{131}",
        "j": "\u{237}", "textendash": "\u{2013}", "textemdash": "\u{2014}", "ldots": "\u{2026}",
        "dots": "\u{2026}", "textquoteright": "\u{2019}", "textquoteleft": "\u{2018}", "textquotedblleft": "\u{201C}",
        "textquotedblright": "\u{201D}", "textregistered": "\u{AE}", "texttrademark": "\u{2122}",
        "textcopyright": "\u{A9}", "&": "&", "%": "%", "$": "$", "_": "_", "#": "#", "{": "{", "}": "}",
        " ": " ", ",": " ", "textunderscore": "_", "textbackslash": "\\",
    ]

    public static func clean(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let s = Array(value.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == "\\", i + 1 < s.count {
                i += 1
                if let mark = accents[s[i]] {
                    i += 1
                    if let base = accentBase(s, &i) {
                        out.append(base)
                        out.append(mark)
                    }
                    continue
                }
                if isLetter(s[i]) {
                    let start = i
                    while i < s.count, isLetter(s[i]) { i += 1 }
                    let name = String(String.UnicodeScalarView(s[start..<i]))
                    if let mark = letterAccents[name] {
                        while i < s.count, s[i] == " " { i += 1 }
                        if let base = accentBase(s, &i) {
                            out.append(base)
                            out.append(mark)
                        }
                        continue
                    }
                    if let symbol = symbols[name] {
                        out.append(contentsOf: symbol.unicodeScalars)
                    }
                    // Other commands (\emph, \textit, \url…) keep their
                    // argument, which the loop goes on to copy.
                    if i < s.count, s[i] == " " { i += 1 }
                    continue
                }
                let single = String(s[i])
                out.append(contentsOf: (symbols[single] ?? single).unicodeScalars)
                i += 1
                continue
            }
            if c == "{" || c == "}" { i += 1; continue }
            out.append(c == "~" ? " " : c)
            i += 1
        }
        let text = String(out).precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "---", with: "\u{2014}")
            .replacingOccurrences(of: "--", with: "\u{2013}")
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The letter an accent applies to: `o`, `{o}` or `{\i}`.
    private static func accentBase(_ s: [Unicode.Scalar], _ i: inout Int) -> Unicode.Scalar? {
        var braced = false
        if i < s.count, s[i] == "{" { braced = true; i += 1 }
        var base: Unicode.Scalar?
        if i + 1 < s.count, s[i] == "\\", s[i + 1] == "i" || s[i + 1] == "j" {
            base = s[i + 1] == "i" ? "i" : "j"
            i += 2
        } else if i < s.count {
            base = s[i]
            i += 1
        }
        if braced, i < s.count, s[i] == "}" { i += 1 }
        return base
    }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
    }
}

// MARK: - Names

/// One author or editor.
public struct PersonName: Hashable, Sendable {
    /// The surname with any particles ("van der Berg"), or the whole name of
    /// an organisation.
    public let family: String
    /// The given names ("Jean-Paul Anne"); empty for an organisation.
    public let given: String
    /// "Jr.", "III" and the like.
    public let suffix: String
    public let isOrganisation: Bool

    /// "J.-P. A."
    public var initials: String {
        given.split(separator: " ").map { word -> String in
            word.split(separator: "-").compactMap { part in part.first.map { "\(String($0).uppercased())." } }
                .joined(separator: "-")
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// APA's reference-list form: "van der Berg, J.-P. A., Jr." or the organisation.
    public var invertedAPA: String {
        if isOrganisation || initials.isEmpty { return family }
        return "\(family), \(initials)" + (suffix.isEmpty ? "" : ", \(suffix)")
    }

    /// APA's editor form: "J.-P. A. van der Berg".
    public var directAPA: String {
        if isOrganisation || initials.isEmpty { return family }
        return "\(initials) \(family)" + (suffix.isEmpty ? "" : ", \(suffix)")
    }

    /// Splits a BibTeX `author` or `editor` value on top-level "and".
    /// "others" is dropped. A name wholly in braces is an organisation.
    public static func parseList(_ raw: String?) -> [PersonName] {
        guard let raw, !raw.trimmed.isEmpty else { return [] }
        var names: [String] = []
        var current = ""
        var depth = 0
        let words = raw.unicodeScalars
        var token = ""
        func flushToken() {
            if depth == 0, token.lowercased() == "and" {
                names.append(current)
                current = ""
            } else {
                current += (current.isEmpty ? "" : " ") + token
            }
            token = ""
        }
        for c in words {
            if c == "{" { depth += 1 }
            if c == "}" { depth = max(0, depth - 1) }
            if depth == 0, c == " " || c == "\n" || c == "\t" || c == "\r" {
                if !token.isEmpty { flushToken() }
            } else {
                token.unicodeScalars.append(c)
            }
        }
        if !token.isEmpty { flushToken() }
        names.append(current)
        return names.map(\.trimmed).filter { !$0.isEmpty && $0.lowercased() != "others" }.map(parse)
    }

    /// One name: "Last, First", "Last, Jr., First", "First von Last" or "{Organisation}".
    public static func parse(_ raw: String) -> PersonName {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"), isWhollyBraced(trimmed) {
            return PersonName(family: LaTeX.clean(trimmed), given: "", suffix: "", isOrganisation: true)
        }
        let parts = splitTopLevelCommas(trimmed).map { LaTeX.clean($0) }
        switch parts.count {
        case 0:
            return PersonName(family: "", given: "", suffix: "", isOrganisation: false)
        case 1:
            let words = parts[0].split(separator: " ").map(String.init)
            guard words.count > 1 else {
                return PersonName(family: parts[0], given: "", suffix: "", isOrganisation: false)
            }
            // "First von Last": the family name starts at the first word
            // after the first one that begins in lowercase, else it is the
            // last word.
            var familyStart = words.count - 1
            if let von = words.indices.dropFirst().dropLast().first(where: { words[$0].first?.isLowercase == true }) {
                familyStart = von
            }
            return PersonName(family: words[familyStart...].joined(separator: " "),
                              given: words[..<familyStart].joined(separator: " "), suffix: "", isOrganisation: false)
        case 2:
            return PersonName(family: parts[0], given: parts[1], suffix: "", isOrganisation: false)
        default:
            return PersonName(family: parts[0], given: parts[2...].joined(separator: " "), suffix: parts[1],
                              isOrganisation: false)
        }
    }

    private static func isWhollyBraced(_ text: String) -> Bool {
        var depth = 0
        for (index, c) in text.unicodeScalars.enumerated() {
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0, index < text.unicodeScalars.count - 1 { return false }
            }
        }
        return true
    }

    private static func splitTopLevelCommas(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for c in text.unicodeScalars {
            if c == "{" { depth += 1 }
            if c == "}" { depth = max(0, depth - 1) }
            if c == ",", depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.unicodeScalars.append(c)
            }
        }
        parts.append(current)
        return parts.map(\.trimmed).filter { !$0.isEmpty }
    }
}

// MARK: - Formatted references

/// A formatted reference as runs of text, some in italics, so it can be
/// shown, copied as rich text (HTML, RTF) or as plain text.
public struct FormattedReference: Hashable, Sendable {
    public struct Segment: Hashable, Sendable {
        public let text: String
        public let italic: Bool
    }

    public private(set) var segments: [Segment] = []

    public init() {}

    public var plain: String { segments.map(\.text).joined() }

    /// HTML with `<i>` for italics, escaped.
    public var html: String {
        segments.map { $0.italic ? "<i>\(Exporter.escape($0.text))</i>" : Exporter.escape($0.text) }.joined()
    }

    mutating func add(_ text: String, italic: Bool = false) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.italic == italic {
            segments[segments.count - 1] = Segment(text: last.text + text, italic: italic)
        } else {
            segments.append(Segment(text: text, italic: italic))
        }
    }

    /// Adds a space unless the reference is empty or already ends in one.
    mutating func space() {
        if let last = plain.last, last != " " { add(" ") }
    }

    /// Ends a sentence with a full stop, unless it already ends with . ? or !
    mutating func period() {
        guard let last = plain.last else { return }
        if !".?!".contains(last) { add(".") }
    }
}

/// APA 7th edition references for the common entry types: a pragmatic
/// formatter, not a CSL engine, laid out like QDVC Bibliotheca's. The DOI is
/// written `doi:10.1234/abcd` rather than as a URL.
public enum APA7 {
    public static func format(_ entry: BibEntry) -> FormattedReference {
        var ref = FormattedReference()
        let authors = PersonName.parseList(entry["author"])
        let editors = PersonName.parseList(entry["editor"])
        let title = LaTeX.clean(entry["title"])
        let type = entry.type.lowercased()
        let titleIsItalic: Bool
        switch type {
        case "article", "inproceedings", "conference", "incollection", "inbook": titleIsItalic = false
        default: titleIsItalic = true
        }

        // Author (Year). — editors stand in for a book's missing authors, and
        // the title moves to the front when there is neither.
        var titleDone = false
        if !authors.isEmpty {
            ref.add(authorList(authors))
        } else if !editors.isEmpty, type == "book" || type == "proceedings" || type == "collection" {
            ref.add(authorList(editors))
            ref.add(editors.count == 1 ? " (Ed.)" : " (Eds.)")
        } else if !title.isEmpty {
            ref.add(title, italic: titleIsItalic)
            titleDone = true
        }
        ref.period()
        ref.space()
        ref.add("(\(year(entry)))")
        ref.period()

        if !titleDone, !title.isEmpty {
            ref.space()
            ref.add(title, italic: titleIsItalic)
        }

        switch type {
        case "article":
            if !titleDone, !title.isEmpty { ref.period() }
            let journal = LaTeX.clean(entry.first("journal", "journaltitle"))
            let volume = LaTeX.clean(entry["volume"])
            let issue = LaTeX.clean(entry.first("number", "issue"))
            let pages = LaTeX.clean(entry["pages"])
            let articleNumber = LaTeX.clean(entry.first("eid", "articleno", "article-number"))
            if !journal.isEmpty {
                ref.space()
                ref.add(journal, italic: true)
                if !volume.isEmpty {
                    ref.add(", ")
                    ref.add(volume, italic: true)
                    if !issue.isEmpty { ref.add("(\(issue))") }
                }
                if !pages.isEmpty {
                    ref.add(", \(pages)")
                } else if !articleNumber.isEmpty {
                    ref.add(", Article \(articleNumber)")
                }
                ref.period()
            }
        case "inproceedings", "conference", "incollection", "inbook":
            if !titleDone, !title.isEmpty { ref.period() }
            let book = LaTeX.clean(entry.first("booktitle", "maintitle"))
            let pages = LaTeX.clean(entry["pages"])
            if !book.isEmpty {
                ref.space()
                ref.add("In ")
                if !editors.isEmpty {
                    let names = editors.map(\.directAPA)
                    switch names.count {
                    case 1: ref.add(names[0])
                    case 2: ref.add("\(names[0]) & \(names[1])")
                    default: ref.add(names.dropLast().joined(separator: ", ") + ", & " + names[names.count - 1])
                    }
                    ref.add(editors.count == 1 ? " (Ed.), " : " (Eds.), ")
                }
                ref.add(book, italic: true)
                if !pages.isEmpty { ref.add(" (pp. \(pages))") }
                ref.period()
            }
            addPublisher(entry, to: &ref)
        case "phdthesis", "mastersthesis", "thesis":
            let kind = type == "mastersthesis" ? "Master\u{2019}s thesis" : "Doctoral dissertation"
            let school = LaTeX.clean(entry.first("school", "institution"))
            if !titleDone {
                ref.add(school.isEmpty ? " [\(kind)]" : " [\(kind), \(school)]")
                ref.period()
            }
        case "techreport", "report":
            let number = LaTeX.clean(entry["number"])
            if !titleDone {
                if !number.isEmpty { ref.add(" (Report No. \(number))") }
                ref.period()
            }
            let institution = LaTeX.clean(entry.first("institution", "publisher"))
            if !institution.isEmpty {
                ref.space()
                ref.add(institution)
                ref.period()
            }
        case "book", "proceedings", "collection":
            let edition = LaTeX.clean(entry["edition"])
            if !titleDone {
                if !edition.isEmpty { ref.add(" (\(edition) ed.)") }
                ref.period()
            }
            addPublisher(entry, to: &ref)
        default:
            if !titleDone, !title.isEmpty { ref.period() }
            let site = LaTeX.clean(entry.first("howpublished", "organization", "publisher", "institution"))
            if !site.isEmpty, !site.contains("://") {
                ref.space()
                ref.add(site)
                ref.period()
            }
        }

        if let doi = doi(of: entry) {
            ref.space()
            ref.add(doi)
        } else if let url = url(of: entry) {
            ref.space()
            ref.add(url)
        }
        return ref
    }

    /// "Smith, J., Jones, A., & Lee, K." — up to 20 names; with 21 or more,
    /// the first 19, an ellipsis and the last.
    public static func authorList(_ names: [PersonName]) -> String {
        let formatted = names.map(\.invertedAPA).filter { !$0.isEmpty }
        switch formatted.count {
        case 0: return ""
        case 1: return formatted[0]
        case 2...20: return formatted.dropLast().joined(separator: ", ") + ", & " + formatted[formatted.count - 1]
        default: return formatted.prefix(19).joined(separator: ", ") + ", . . . " + formatted[formatted.count - 1]
        }
    }

    /// The narrative citation: "Smith (2024)", "Smith & Jones (2024)" or
    /// "Smith et al. (2024)".
    public static func shortCitation(_ entry: BibEntry) -> String {
        let names = PersonName.parseList(entry["author"]).isEmpty
            ? PersonName.parseList(entry["editor"]) : PersonName.parseList(entry["author"])
        let lead: String
        switch names.count {
        case 0: lead = LaTeX.clean(entry["title"])
        case 1: lead = names[0].family
        case 2: lead = "\(names[0].family) & \(names[1].family)"
        default: lead = "\(names[0].family) et al."
        }
        return lead.isEmpty ? "(\(year(entry)))" : "\(lead) (\(year(entry)))"
    }

    /// The year, from `year` or the start of `date`, or "n.d.".
    public static func year(_ entry: BibEntry) -> String {
        let year = LaTeX.clean(entry["year"])
        if !year.isEmpty { return year }
        let date = LaTeX.clean(entry["date"])
        if date.count >= 4, date.prefix(4).allSatisfy(\.isNumber) { return String(date.prefix(4)) }
        return "n.d."
    }

    /// The entry's DOI as `doi:10.1234/abcd`, or nil when it has none.
    public static func doi(of entry: BibEntry) -> String? {
        normalizedDOI(entry["doi"])
    }

    /// `https://doi.org/10.1234/X`, `http://dx.doi.org/…`, `doi:…` or a bare
    /// `10.1234/X` → `doi:10.1234/X`.
    public static func normalizedDOI(_ raw: String?) -> String? {
        var doi = LaTeX.clean(raw)
        let prefixes = ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/",
                        "doi.org/", "dx.doi.org/", "doi:"]
        var stripped = true
        while stripped {
            stripped = false
            for prefix in prefixes where doi.lowercased().hasPrefix(prefix) {
                doi = String(doi.dropFirst(prefix.count)).trimmed
                stripped = true
            }
        }
        return doi.isEmpty ? nil : "doi:\(doi)"
    }

    /// The `url` field, or a URL given in `howpublished` (`\url{…}`).
    private static func url(of entry: BibEntry) -> String? {
        let url = LaTeX.clean(entry["url"])
        if !url.isEmpty { return url }
        let published = LaTeX.clean(entry["howpublished"])
        return published.contains("://") ? published : nil
    }

    private static func addPublisher(_ entry: BibEntry, to ref: inout FormattedReference) {
        let publisher = LaTeX.clean(entry["publisher"])
        guard !publisher.isEmpty else { return }
        ref.space()
        ref.add(publisher)
        ref.period()
    }
}
