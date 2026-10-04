import Foundation
@testable import AutoLitReviewCore

/// A temporary folder, removed when the object goes away.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autolitreview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `text` to `path` (relative to the folder), creating folders.
    @discardableResult
    func write(_ path: String, _ text: String = "x") throws -> URL {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
        return target
    }

    func makeFolder(_ path: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(path, isDirectory: true),
                                                withIntermediateDirectories: true)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path)
    }

    /// The visible and hidden names in a subfolder ("" for the folder itself).
    func names(in path: String = "") throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent(path).path).sorted()
    }
}

/// `count` simple BibTeX entries with keys `<prefix>1`, `<prefix>2`, …;
/// the first `withAbstract` of them (all, by default) have an abstract.
func bibtex(_ count: Int, prefix: String = "ref", withAbstract: Int? = nil) -> String {
    guard count > 0 else { return "% no references\n" }
    let abstracts = withAbstract ?? count
    return (1...count).map { n in
        "@article{\(prefix)\(n),\n  title = {Paper \(n)},\n  year = {2024},\n"
            + (n <= abstracts ? "  abstract = {What paper \(n) found.},\n" : "") + "}\n"
    }
    .joined(separator: "\n")
}

/// Writes a complete single-RQ test with literal (canonical) names.
func writeSingleTest(_ ws: TempFolder, _ id: String, question: String = "What is known about X?",
                     references: Int = 3, namedCount: Int? = nil, skip: Set<String> = []) throws {
    let files: [(String, String, String)] = [
        ("query", "\(id)/\(id)_query/\(id)_query_asked.png", "png"),
        ("response", "\(id)/\(id)_query/\(id)_response_received.png", "png"),
        ("rq", "\(id)/\(id)_query/\(id)_RQ_asked.md", question + "\n"),
        ("bib", "\(id)/\(id)_references_n\(namedCount ?? references).bib", bibtex(references)),
        ("pdf", "\(id)/\(id)_report.pdf", "%PDF-1.4"),
        ("dom", "\(id)/\(id)_report_DOM.html", "<html></html>"),
    ]
    for (key, path, text) in files where !skip.contains(key) {
        try ws.write(path, text)
    }
}

/// Writes one complete variant of a multi-RQ test with literal names.
func writeVariant(_ ws: TempFolder, _ id: String, _ variant: Int, question: String? = nil,
                  references: Int = 2, skip: Set<String> = []) throws {
    let folder = "\(id)/\(id)_query_variant\(variant)"
    let prefix = "\(id)_variant\(variant)_"
    let files: [(String, String, String)] = [
        ("query", "\(folder)/\(prefix)query_asked.png", "png"),
        ("response", "\(folder)/\(prefix)response_received.png", "png"),
        ("rq", "\(folder)/\(prefix)RQ_asked.md", question ?? "Question \(variant)?"),
        ("bib", "\(id)/\(prefix)references_n\(references).bib", bibtex(references, prefix: "v\(variant)r")),
        ("pdf", "\(id)/\(prefix)report.pdf", "%PDF-1.4"),
        ("dom", "\(id)/\(prefix)report_DOM.html", "<html></html>"),
    ]
    for (key, path, text) in files where !skip.contains(key) {
        try ws.write(path, text)
    }
}

extension TestRun {
    var messages: [String] { allIssues.map(\.message) }

    func hasIssue(_ severity: Severity, containing text: String) -> Bool {
        allIssues.contains { $0.severity == severity && $0.message.contains(text) }
    }
}
