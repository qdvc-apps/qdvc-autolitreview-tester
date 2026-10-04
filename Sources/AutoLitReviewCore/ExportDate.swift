import Foundation

/// The date a BibTeX file was exported, from a line such as
/// `EXPORT DATE: 02 October 2026` (Scopus writes one at the top of its
/// exports). It is a calendar date with no time or time zone, so it reads the
/// same everywhere. A test's date is the export date of its BibTeX files, or
/// their range when its variants were exported on different days.
public struct ExportDate: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil unless the date exists (no 31 April, 29 February only in leap years).
    public init?(year: Int, month: Int, day: Int) {
        guard (1000...9999).contains(year), (1...12).contains(month),
              (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: ExportDate, rhs: ExportDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                    "August", "September", "October", "November", "December"]

    /// "2026-10-02"
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// "2 October 2026"
    public var long: String { "\(day) \(Self.monthNames[month - 1]) \(year)" }

    /// "2 Oct 2026"
    public var short: String { "\(day) \(Self.shortMonth(month)) \(year)" }

    /// "Jan" … "Dec".
    public static func shortMonth(_ month: Int) -> String { String(monthNames[month - 1].prefix(3)) }

    // MARK: Finding and parsing

    /// Every distinct date given after "EXPORT DATE:" (any case, colon
    /// optional) anywhere in the text, earliest first.
    public static func find(in text: String) -> [ExportDate] {
        var dates = Set<ExportDate>()
        var searchStart = text.startIndex
        while let match = text.range(of: "export date", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            searchStart = match.upperBound
            var rest = text[match.upperBound...].drop { $0 == " " || $0 == "\t" }
            if rest.first == ":" { rest = rest.dropFirst() }
            let value = rest.prefix { !$0.isNewline && !"};\"".contains($0) }
            if let date = parse(String(value)) { dates.insert(date) }
        }
        return dates.sorted()
    }

    /// Parses "02 October 2026", "2 Oct 2026", "October 2, 2026",
    /// "2026-10-02" and "02/10/2026" (day first). Only the first three
    /// words or numbers count, so trailing text is ignored.
    public static func parse(_ text: String) -> ExportDate? {
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(3).map(String.init)
        guard tokens.count == 3 else { return nil }
        let numbers = tokens.map { Int($0) }
        if let a = numbers[0], let b = numbers[1], let c = numbers[2] {
            // yyyy-mm-dd, or dd/mm/yyyy.
            if tokens[0].count == 4 { return ExportDate(year: a, month: b, day: c) }
            if tokens[2].count == 4 { return ExportDate(year: c, month: b, day: a) }
            return nil
        }
        if let day = numbers[0], let month = monthNumber(tokens[1]), let year = numbers[2], tokens[2].count == 4 {
            return ExportDate(year: year, month: month, day: day)
        }
        if let month = monthNumber(tokens[0]), let day = numbers[1], let year = numbers[2], tokens[2].count == 4 {
            return ExportDate(year: year, month: month, day: day)
        }
        return nil
    }

    /// "October", "Oct", "oct", "Sept" → 10, 10, 10, 9.
    static func monthNumber(_ word: String) -> Int? {
        let lower = word.lowercased()
        guard lower.count >= 3 else { return nil }
        if lower == "sept" { return 9 }
        for (index, name) in monthNames.enumerated() {
            let full = name.lowercased()
            if lower == full || lower == String(full.prefix(3)) { return index + 1 }
        }
        return nil
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // MARK: Ranges

    /// "2 October 2026", "1–2 October 2026", "30 September – 2 October 2026"
    /// or "31 December 2025 – 2 January 2026"; nil for no dates.
    public static func longRange(_ dates: [ExportDate]) -> String? {
        range(dates) { monthNames[$0 - 1] }
    }

    /// As `longRange`, with three-letter months: "2 Oct 2026",
    /// "1–2 Oct 2026", "30 Sep – 2 Oct 2026" (the Markdown export).
    public static func shortRange(_ dates: [ExportDate]) -> String? {
        range(dates) { shortMonth($0) }
    }

    private static func range(_ dates: [ExportDate], month name: (Int) -> String) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let end = "\(last.day) \(name(last.month)) \(last.year)"
        if first == last { return end }
        if first.year == last.year, first.month == last.month {
            return "\(first.day)\u{2013}\(end)"
        }
        if first.year == last.year {
            return "\(first.day) \(name(first.month)) \u{2013} \(end)"
        }
        return "\(first.day) \(name(first.month)) \(first.year) \u{2013} \(end)"
    }

    /// "2026-10-02", or "2026-10-01 to 2026-10-02"; nil for no dates.
    public static func isoRange(_ dates: [ExportDate]) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first == last ? first.iso : "\(first.iso) to \(last.iso)"
    }
}
