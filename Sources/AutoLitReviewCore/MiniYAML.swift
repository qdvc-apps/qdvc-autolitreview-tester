import Foundation

/// A value from a YAML file.
public indirect enum YAMLValue: Hashable, Sendable {
    case scalar(String)
    case mapping([String: YAMLValue])
    case sequence([YAMLValue])

    public subscript(_ key: String) -> YAMLValue? {
        if case .mapping(let map) = self { return map[key] }
        return nil
    }

    public var string: String? {
        if case .scalar(let text) = self { return text }
        return nil
    }

    /// True for `true`, `yes` or `on` and false for `false`, `no` or `off`,
    /// in any case and quoted or not (so `True` and `"True"` both count);
    /// nil for anything else.
    public var bool: Bool? {
        switch string?.lowercased() {
        case "true", "yes", "on": return true
        case "false", "no", "off": return false
        default: return nil
        }
    }
}

public struct YAMLError: LocalizedError, Equatable {
    public let line: Int
    public let reason: String

    public var errorDescription: String? { "Line \(line): \(reason)" }
}

/// Reads the small subset of YAML a workspace.yml needs: nested block
/// mappings by indentation, block sequences of scalars (`- item`), flow
/// mappings and sequences on one line (`{a: b}`, `[a, b]`), single- and
/// double-quoted or plain scalars, `#` comments and `---`. Anchors, tags,
/// multi-line scalars and the like are not supported; there is no YAML
/// package in the Foundation-only core.
public enum MiniYAML {
    public static func parse(_ text: String) throws -> YAMLValue {
        var lines: [Line] = []
        for (offset, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            var content = stripComment(String(raw))
            while content.last?.isWhitespace == true { content.removeLast() }
            let indent = content.prefix { $0 == " " || $0 == "\t" }.count
            let body = content.trimmed
            if body.isEmpty || body == "---" || body == "..." { continue }
            lines.append(Line(number: offset + 1, indent: indent, text: body))
        }
        guard let first = lines.first else { return .mapping([:]) }
        var index = 0
        let value = try parseBlock(lines, &index, indent: first.indent)
        if index < lines.count {
            throw YAMLError(line: lines[index].number, reason: "unexpected indentation")
        }
        return value
    }

    struct Line {
        let number: Int
        let indent: Int
        let text: String
    }

    private static func parseBlock(_ lines: [Line], _ index: inout Int, indent: Int) throws -> YAMLValue {
        if lines[index].text == "-" || lines[index].text.hasPrefix("- ") {
            var items: [YAMLValue] = []
            while index < lines.count, lines[index].indent == indent,
                  lines[index].text == "-" || lines[index].text.hasPrefix("- ") {
                let item = String(lines[index].text.dropFirst()).trimmed
                index += 1
                if item.isEmpty, index < lines.count, lines[index].indent > indent {
                    items.append(try parseBlock(lines, &index, indent: lines[index].indent))
                } else {
                    items.append(try inlineValue(item, line: lines[index - 1].number))
                }
            }
            return .sequence(items)
        }
        var map: [String: YAMLValue] = [:]
        while index < lines.count, lines[index].indent == indent {
            let line = lines[index]
            guard let (key, rest) = splitKey(line.text) else {
                throw YAMLError(line: line.number, reason: "expected \u{201C}key: value\u{201D}")
            }
            index += 1
            if rest.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    map[key] = try parseBlock(lines, &index, indent: lines[index].indent)
                } else {
                    map[key] = .scalar("")
                }
            } else {
                map[key] = try inlineValue(rest, line: line.number)
            }
        }
        return .mapping(map)
    }

    /// A scalar, or a one-line flow mapping or sequence.
    private static func inlineValue(_ text: String, line: Int) throws -> YAMLValue {
        if text.hasPrefix("{") {
            guard text.hasSuffix("}") else { throw YAMLError(line: line, reason: "unclosed \u{201C}{\u{201D}") }
            var map: [String: YAMLValue] = [:]
            for part in splitFlow(String(text.dropFirst().dropLast())) where !part.isEmpty {
                guard let (key, rest) = splitKey(part) else {
                    throw YAMLError(line: line, reason: "expected \u{201C}key: value\u{201D} in \u{201C}{\u{2026}}\u{201D}")
                }
                map[key] = try inlineValue(rest, line: line)
            }
            return .mapping(map)
        }
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { throw YAMLError(line: line, reason: "unclosed \u{201C}[\u{201D}") }
            return .sequence(try splitFlow(String(text.dropFirst().dropLast())).filter { !$0.isEmpty }
                .map { try inlineValue($0, line: line) })
        }
        return .scalar(unquote(text))
    }

    /// Splits "key: value" (or "key:") at the first colon followed by a space
    /// or the end, outside quotes.
    private static func splitKey(_ text: String) -> (String, String)? {
        var quote: Character?
        var previous: Character?
        for index in text.indices {
            let c = text[index]
            if let open = quote {
                if c == open, previous != "\\" { quote = nil }
            } else if c == "\"" || c == "'", index == text.startIndex {
                // Only a quoted key; an apostrophe later on is just a letter.
                quote = c
            } else if c == ":" {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " || text[next] == "\t" {
                    let key = unquote(String(text[..<index]).trimmed)
                    guard !key.isEmpty else { return nil }
                    return (key, String(text[next...]).trimmed)
                }
            }
            previous = c
        }
        return nil
    }

    /// Splits flow content on top-level commas.
    private static func splitFlow(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for c in text {
            if let open = quote {
                if c == open { quote = nil }
            } else if c == "\"" || c == "'", current.trimmed.isEmpty || current.hasSuffix(": ") {
                quote = c
            } else if c == "{" || c == "[" {
                depth += 1
            } else if c == "}" || c == "]" {
                depth -= 1
            } else if c == ",", depth == 0 {
                parts.append(current.trimmed)
                current = ""
                continue
            }
            current.append(c)
        }
        parts.append(current.trimmed)
        return parts
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        let inner = String(text.dropFirst().dropLast())
        if first == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Drops a `#` comment: one at the start of the line or after a space,
    /// outside quotes.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for index in line.indices {
            let c = line[index]
            if let open = quote {
                if c == open { quote = nil }
            } else if c == "\"" || c == "'", " \t:[{,".contains(previous) {
                // A quote only opens a scalar where one can start.
                quote = c
            } else if c == "#", previous == " " || previous == "\t" {
                return String(line[..<index])
            }
            previous = c
        }
        return line
    }
}
