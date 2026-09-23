import Foundation

public struct SearchResult: Identifiable, Sendable {
    public var id: UUID { entry.id }
    public let entry: JournalEntry
    public let matchSnippet: String
    public let matchCount: Int
}

public enum Search {

    /// Case-insensitive search over written entries and video transcripts.
    /// Most matches first, then most recent.
    public static func run(query: String, in entries: [JournalEntry]) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return entries.compactMap { entry -> SearchResult? in
            let text = entry.content
            let ranges = text.ranges(of: q, options: [.caseInsensitive, .diacriticInsensitive])
            guard let first = ranges.first else { return nil }
            return SearchResult(entry: entry, matchSnippet: snippet(in: text, around: first), matchCount: ranges.count)
        }
        .sorted {
            $0.matchCount != $1.matchCount
                ? $0.matchCount > $1.matchCount
                : $0.entry.createdAt > $1.entry.createdAt
        }
    }

    static func snippet(in text: String, around match: Range<String.Index>) -> String {
        let start = text.index(match.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = text[start..<end]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}

extension String {
    func ranges(of needle: String, options: String.CompareOptions) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let found = range(of: needle, options: options, range: searchStart..<endIndex) {
            result.append(found)
            searchStart = found.upperBound
        }
        return result
    }
}
