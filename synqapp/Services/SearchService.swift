
//  SearchService.swift
//  SynqApp — full-text search across all journal entries

import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let entry: JournalEntry
    let matchSnippet: String   // surrounding context of the match
    let matchCount: Int
}

final class SearchService {

    static let shared = SearchService()
    private init() {}

    /// Search all entries for a query string. Returns ranked results.
    func search(query: String, in entries: [JournalEntry]) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var results: [SearchResult] = []

        for entry in entries where entry.entryType == .text {
            let body = entry.body
            let lower = body.lowercased()
            guard lower.contains(q) else { continue }

            // Count occurrences
            var count = 0
            var searchRange = lower.startIndex..<lower.endIndex
            while let range = lower.range(of: q, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<lower.endIndex
            }

            // Build snippet around first match
            let snippet = buildSnippet(body: body, query: q)
            results.append(SearchResult(
                id: entry.id,
                entry: entry,
                matchSnippet: snippet,
                matchCount: count
            ))
        }

        // Sort: most matches first, then most recent
        return results.sorted {
            if $0.matchCount != $1.matchCount { return $0.matchCount > $1.matchCount }
            return $0.entry.createdAt > $1.entry.createdAt
        }
    }

    private func buildSnippet(body: String, query: String) -> String {
        let lower = body.lowercased()
        guard let matchRange = lower.range(of: query) else {
            return String(body.prefix(80)) + (body.count > 80 ? "…" : "")
        }

        // Get ~60 chars before and after the match
        let matchStart = matchRange.lowerBound
        let matchEnd = matchRange.upperBound

        let snippetStart = body.index(matchStart, offsetBy: -40, limitedBy: body.startIndex) ?? body.startIndex
        let snippetEnd = body.index(matchEnd, offsetBy: 60, limitedBy: body.endIndex) ?? body.endIndex

        var snippet = String(body[snippetStart..<snippetEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        if snippetStart > body.startIndex { snippet = "…" + snippet }
        if snippetEnd < body.endIndex { snippet = snippet + "…" }

        return snippet
    }
}
