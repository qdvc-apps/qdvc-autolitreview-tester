import Foundation

/// Small text helpers shared by the scanner, the exports and the app.
public enum TextSupport {
    /// Reads a text file. UTF-8 is expected; Latin-1 is accepted as a
    /// fallback (every byte sequence is valid Latin-1, so this only fails
    /// when the file can't be read at all). A leading byte-order mark is
    /// dropped.
    public static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// "a", "a and b", "a, b and c".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// The first `limit` items as a list, with "and N more" when there are
    /// more.
    public static func list(_ items: [String], limit: Int) -> String {
        guard items.count > limit, limit > 0 else { return list(items) }
        return items.prefix(limit).joined(separator: ", ") + " and \(items.count - limit) more"
    }

    /// "1 reference", "2 references".
    public static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) " + (count == 1 ? singular : (plural ?? singular + "s"))
    }
}

extension String {
    /// The string without leading/trailing whitespace and newlines.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
