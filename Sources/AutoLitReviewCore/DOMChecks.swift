import Foundation

/// Settings from the optional `workspace.yml` at the top of the workspace
/// (docs/FILE_FORMAT.md §1.1):
///
/// ```yaml
/// dom_checks:
///   rq_text_string_check: True
///   all_n_references_check: True
/// ```
public struct WorkspaceConfig: Hashable, Sendable {
    /// The names looked for, in order.
    public static let fileNames = ["workspace.yml", "workspace.yaml"]

    /// Check that each research question's exact text appears in its report DOM.
    public var rqTextStringCheck = false
    /// Check that each report DOM says "Show all N references", where N is
    /// the number of references in the BibTeX file.
    public var allNReferencesCheck = false
    /// The file the settings came from, if there is one.
    public var fileName: String?
    /// What's wrong with the file, if anything (the checks it couldn't read
    /// stay off).
    public var problems: [String] = []

    public init() {}

    public var anyDOMCheck: Bool { rqTextStringCheck || allNReferencesCheck }

    /// Reads the settings from YAML text.
    public init(yaml text: String, fileName: String? = nil) {
        self.fileName = fileName
        let root: YAMLValue
        do {
            root = try MiniYAML.parse(text)
        } catch {
            problems.append(error.localizedDescription)
            return
        }
        guard let checks = root["dom_checks"] else { return }
        guard case .mapping = checks else {
            problems.append("dom_checks should hold settings such as \u{201C}rq_text_string_check: True\u{201D}")
            return
        }
        rqTextStringCheck = flag("rq_text_string_check", in: checks)
        allNReferencesCheck = flag("all_n_references_check", in: checks)
    }

    private mutating func flag(_ key: String, in checks: YAMLValue) -> Bool {
        guard let value = checks[key] else { return false }
        if let bool = value.bool { return bool }
        problems.append("dom_checks.\(key) is \u{201C}\(value.string ?? "not a single value")\u{201D}; use True or False")
        return false
    }

    /// Reads `workspace.yml` (or `.yaml`) from the workspace folder; the
    /// default settings (no checks) when there is none.
    public static func load(from root: URL, fileManager: FileManager = .default) -> WorkspaceConfig {
        for name in fileNames {
            let url = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                return WorkspaceConfig(yaml: try TextSupport.readText(url), fileName: name)
            } catch {
                var config = WorkspaceConfig()
                config.fileName = name
                config.problems = ["Couldn\u{2019}t read \(name): \(error.localizedDescription)"]
                return config
            }
        }
        return WorkspaceConfig()
    }
}

/// One DOM check's result for a research question.
public struct DOMCheckResult: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The research question's text.
        case questionText
        /// "Show all N references".
        case showAllReferences(Int)
    }

    public let kind: Kind
    public let passed: Bool

    public init(kind: Kind, passed: Bool) {
        self.kind = kind
        self.passed = passed
    }

    /// "Research question text" or "“Show all 123 references”".
    public var title: String {
        switch kind {
        case .questionText: return "Research question text"
        case .showAllReferences(let n): return "\u{201C}\(DOMText.showAllPhrase(n))\u{201D}"
        }
    }
}

/// The text of a saved page, for checking what it shows. Tags are removed
/// (scripts, styles and comments with their contents), character references
/// decoded, and every run of whitespace (including non-breaking spaces)
/// becomes one space. Because a tag may or may not separate words, the text
/// is kept both ways (tags removed, and tags replaced by a space). The
/// `value` of form fields is kept too, since a page may show the question in
/// a search box. Matching is then exact: case, punctuation and accents must
/// all agree.
public struct DOMText: Sendable {
    public let variants: [String]

    public init(html: String) {
        var joined = String.UnicodeScalarView()
        var spaced = String.UnicodeScalarView()
        var values: [String] = []
        let s = Array(html.unicodeScalars)
        let n = s.count
        var i = 0
        while i < n {
            guard s[i] == "<", i + 1 < n else {
                joined.append(s[i])
                spaced.append(s[i])
                i += 1
                continue
            }
            if Self.matches(s, at: i, "<!--") {
                i = Self.find(s, "-->", from: i + 4).map { $0 + 3 } ?? n
                spaced.append(" ")
                continue
            }
            let next = s[i + 1]
            guard Self.isLetter(next) || next == "/" || next == "!" || next == "?" else {
                joined.append(s[i])
                spaced.append(s[i])
                i += 1
                continue
            }
            // The end of the tag, skipping quoted attribute values.
            var j = i + 1
            var quote: Unicode.Scalar?
            while j < n {
                if let open = quote {
                    if s[j] == open { quote = nil }
                } else if s[j] == "\"" || s[j] == "'" {
                    quote = s[j]
                } else if s[j] == ">" {
                    break
                }
                j += 1
            }
            let tag = String(String.UnicodeScalarView(s[i..<min(j + 1, n)]))
            let name = Self.tagName(tag)
            if let value = Self.attribute("value", in: tag) { values.append(value) }
            spaced.append(" ")
            i = j + 1
            // Skip what a script or style holds.
            if (name == "script" || name == "style"), !tag.hasPrefix("</") {
                i = Self.find(s, "</\(name)", from: i, caseInsensitive: true) ?? n
            }
        }
        variants = [String(joined), String(spaced)].map { Self.normalise(Self.decodeEntities($0)) }
            + values.map { Self.normalise(Self.decodeEntities($0)) }
    }

    /// Whether `text` (whitespace normalised as for the page) appears.
    public func contains(_ text: String) -> Bool {
        let needle = Self.normalise(text)
        guard !needle.isEmpty else { return false }
        return variants.contains { $0.contains(needle) }
    }

    /// "Show all 123 references" ("Show all 1 reference" for one).
    public static func showAllPhrase(_ n: Int) -> String {
        n == 1 ? "Show all 1 reference" : "Show all \(n) references"
    }

    /// Whether the page says "Show all N references", with or without a
    /// thousands separator (1,234 or 1234), or "Show all 1 reference(s)".
    public func showsAll(_ n: Int) -> Bool {
        var phrases = ["Show all \(n) references", showAllGrouped(n)]
        if n == 1 { phrases.append("Show all 1 reference") }
        return phrases.contains { self.contains($0) }
    }

    private func showAllGrouped(_ n: Int) -> String { "Show all \(Exporter.grouped(n)) references" }

    // MARK: Helpers

    static func normalise(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" || $0 == "\u{200B}" })
            .joined(separator: " ")
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "shy": "", "zwj": "", "zwnj": "",
        "eacute": "\u{E9}", "egrave": "\u{E8}", "aacute": "\u{E1}", "agrave": "\u{E0}", "ouml": "\u{F6}",
        "uuml": "\u{FC}", "auml": "\u{E4}", "ccedil": "\u{E7}", "szlig": "\u{DF}", "copy": "\u{A9}",
    ]

    /// Decodes `&amp;`, `&#39;`, `&#x2019;` and the common named references.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(12).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String($0) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String($0) }
                } else {
                    decoded = entities[name]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }

    private static func tagName(_ tag: String) -> String {
        tag.drop { $0 == "<" || $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
    }

    /// A quoted (or bare) attribute value from a tag, by name.
    private static func attribute(_ name: String, in tag: String) -> String? {
        var searchStart = tag.startIndex
        while let match = tag.range(of: name + "=", options: .caseInsensitive, range: searchStart..<tag.endIndex) {
            searchStart = match.upperBound
            guard match.lowerBound > tag.startIndex,
                  tag[tag.index(before: match.lowerBound)].isWhitespace else { continue }
            let rest = tag[match.upperBound...]
            guard let first = rest.first else { return nil }
            if first == "\"" || first == "'" {
                let body = rest.dropFirst()
                return String(body.prefix { $0 != first })
            }
            return String(rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
        }
        return nil
    }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
    }

    private static func matches(_ s: [Unicode.Scalar], at index: Int, _ pattern: String,
                                caseInsensitive: Bool = false) -> Bool {
        let p = Array(pattern.unicodeScalars)
        guard index + p.count <= s.count else { return false }
        for k in 0..<p.count {
            var a = s[index + k].value, b = p[k].value
            if caseInsensitive {
                if a >= 65, a <= 90 { a += 32 }
                if b >= 65, b <= 90 { b += 32 }
            }
            if a != b { return false }
        }
        return true
    }

    private static func find(_ s: [Unicode.Scalar], _ pattern: String, from start: Int,
                             caseInsensitive: Bool = false) -> Int? {
        var i = start
        while i < s.count {
            if matches(s, at: i, pattern, caseInsensitive: caseInsensitive) { return i }
            i += 1
        }
        return nil
    }
}

extension DOMText {
    /// Runs the checks the workspace asks for on one research question,
    /// against its report DOM. Returns the results (shown in the inspector)
    /// and a warning for each check that failed.
    static func check(_ question: ResearchQuestion, dom: DOMText, config: WorkspaceConfig,
                      domPath: String) -> (results: [DOMCheckResult], issues: [Issue]) {
        var results: [DOMCheckResult] = []
        var issues: [Issue] = []
        if config.rqTextStringCheck, let text = question.question {
            let passed = dom.contains(text)
            results.append(DOMCheckResult(kind: .questionText, passed: passed))
            if !passed {
                issues.append(.warning("\(domPath): the research question\u{2019}s exact text doesn\u{2019}t appear in the report DOM"))
            }
        }
        if config.allNReferencesCheck, let n = question.referencesFound ?? question.referencesInFileName {
            let passed = dom.showsAll(n)
            results.append(DOMCheckResult(kind: .showAllReferences(n), passed: passed))
            if !passed {
                issues.append(.warning("\(domPath): \u{201C}\(showAllPhrase(n))\u{201D} doesn\u{2019}t appear in the report DOM"))
            }
        }
        return (results, issues)
    }
}
