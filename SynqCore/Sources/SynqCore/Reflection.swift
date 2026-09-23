import Foundation

public enum ReflectionScope: CaseIterable, Sendable {
    case session
    case week
    case month

    public var title: String {
        switch self {
        case .session: return "This Session"
        case .week:    return "This Week"
        case .month:   return "This Month"
        }
    }

    public var subtitle: String {
        switch self {
        case .session: return "Reflect on what you're currently writing"
        case .week:    return "Explore patterns and themes from the past week"
        case .month:   return "Dive deep into your journey over the past month"
        }
    }
}

public enum Reflection {

    public static let systemPrompt = """
    You are a thoughtful, casual friend helping someone reflect on their journal entries. \
    Speak naturally, with no therapy-speak or clinical language. \
    Keep responses concise and conversational. \
    Do not use markdown headings or bullet lists in your replies. \
    Ground everything you say in what the person actually wrote, and help them notice connections they might have missed.
    """

    public static let voiceSystemPrompt = systemPrompt + """
     Your replies are read aloud, so keep each one to two to four short spoken sentences \
    and end with a question that invites them to keep talking.
    """

    public static let recapSystemPrompt = """
    You write short, warm weekly recaps of someone's private journal. \
    Use Markdown. Start with the heading given to you, then write: a two-sentence summary of the week, \
    a "Themes" section with three to five bullets, a "Wins" section, a "What weighed on you" section, \
    and finish with one question to carry into next week. Quote their own words where it helps. \
    Never invent events that are not in the entries.
    """

    /// Journal text to open a reflection with. The system prompt is sent separately.
    public static func context(
        scope: ReflectionScope,
        currentText: String,
        entries: [JournalEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        switch scope {
        case .session:
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty
                ? emptyContext(scope)
                : "Here is what I'm writing right now:\n\n\(text)"
        case .week, .month:
            let relevant = Self.entries(in: scope, from: entries, now: now, calendar: calendar)
            guard !relevant.isEmpty else { return emptyContext(scope) }
            return "Here are my journal entries from \(scope.title.lowercased()):\n\n" + format(relevant)
        }
    }

    /// Non-empty entries inside the scope's window, oldest first.
    public static func entries(
        in scope: ReflectionScope,
        from entries: [JournalEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [JournalEntry] {
        let cutoff: Date
        switch scope {
        case .session: return []
        case .week:    cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:   cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        }
        return entries
            .filter { $0.createdAt >= cutoff && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Opening message for a weekly recap, or nil when there is nothing to recap.
    public static func recapRequest(
        entries: [JournalEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (heading: String, message: String)? {
        let week = self.entries(in: .week, from: entries, now: now, calendar: calendar)
        guard let first = week.first else { return nil }
        let range = "\(first.createdAt.formatted(.dateTime.month(.abbreviated).day())) – \(now.formatted(.dateTime.month(.abbreviated).day()))"
        let heading = "# Weekly recap · \(range)"
        return (heading, "Heading to use: \(heading)\n\nMy entries:\n\n" + format(week))
    }

    static func format(_ entries: [JournalEntry]) -> String {
        entries.map { entry in
            let date = entry.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let kind = entry.entryType == .video ? " (spoken, video entry)" : ""
            return "[\(date)\(kind)]\n\(entry.content.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        .joined(separator: "\n\n---\n\n")
    }

    private static func emptyContext(_ scope: ReflectionScope) -> String {
        "I haven't written anything for \(scope.title.lowercased()) yet. Help me get started by asking what's on my mind."
    }
}

public enum PlainText {
    /// Strips common Markdown markers so an entry reads cleanly as .txt.
    public static func fromMarkdown(_ markdown: String) -> String {
        var text = markdown
        let rules: [(String, String)] = [
            (#"(?m)^#{1,6}\s+"#, ""),
            (#"\*{1,3}([^*\n]+)\*{1,3}"#, "$1"),
            (#"(?<!\w)_{1,3}([^_\n]+)_{1,3}(?!\w)"#, "$1"),
            (#"`([^`\n]+)`"#, "$1"),
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text
    }
}
