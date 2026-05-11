
//  ReflectionService.swift
//  Spill — builds context payload for the voice agent

import Foundation

enum ReflectionScope {
    case session
    case week
    case month

    var title: String {
        switch self {
        case .session: return "This Session"
        case .week:    return "This Week"
        case .month:   return "This Month"
        }
    }

    var subtitle: String {
        switch self {
        case .session: return "Reflect on what you're currently writing"
        case .week:    return "Explore patterns and themes from the past week"
        case .month:   return "Dive deep into your journey over the past month"
        }
    }
}

final class ReflectionService {

    static let aiSystemPrompt = """
You are a thoughtful, casual friend helping someone reflect on their journal entries. \
Speak naturally — no therapy-speak, no clinical language. \
Keep responses concise and conversational. \
Do NOT use markdown headings or bullet lists in your replies. \
Ground everything you say in what the person actually wrote.
"""

    static func buildContext(scope: ReflectionScope, currentText: String, allEntries: [JournalEntry]) -> String {
        switch scope {
        case .session:
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return noEntriesPlaceholder(scope: scope)
            }
            return """
[Current session]
\(text)

---
\(aiSystemPrompt)
"""

        case .week, .month:
            let cutoff: Date = {
                let cal = Calendar.current
                if scope == .week {
                    return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                } else {
                    return cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                }
            }()

            let relevant = allEntries.filter {
                $0.createdAt >= cutoff &&
                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if relevant.isEmpty {
                return noEntriesPlaceholder(scope: scope)
            }

            let blocks = relevant.map { entry -> String in
                let df = DateFormatter()
                df.dateFormat = "MMM d, yyyy"
                return "[\(df.string(from: entry.createdAt))]\n\(entry.body.trimmingCharacters(in: .whitespacesAndNewlines))"
            }.joined(separator: "\n\n---\n\n")

            return """
\(blocks)

---
\(aiSystemPrompt)
"""
        }
    }

    private static func noEntriesPlaceholder(scope: ReflectionScope) -> String {
        """
[No journal entries found for \(scope.title.lowercased())]
The user has not written anything for this period yet.

---
\(aiSystemPrompt)
"""
    }
}
