import Foundation

public enum Stats {

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    public static func wordCountLabel(_ text: String) -> String {
        let count = wordCount(text)
        return count == 1 ? "1 word" : "\(count) words"
    }

    /// Average reading speed ~238 wpm.
    public static func readingTimeLabel(_ text: String) -> String {
        let words = wordCount(text)
        guard words > 0 else { return "" }
        let minutes = max(1, Int(ceil(Double(words) / 238.0)))
        return minutes == 1 ? "~1 min read" : "~\(minutes) min read"
    }

    public static func todayWordCount(
        entries: [JournalEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        entries
            .filter { $0.entryType == .text && calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(0) { $0 + wordCount($1.body) }
    }

    /// Consecutive days with at least one non-empty entry, counting back from today
    /// (or from yesterday when nothing has been written yet today).
    public static func currentStreak(
        entries: [JournalEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let writtenDays = Set(
            entries
                .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { calendar.startOfDay(for: $0.createdAt) }
        )
        var day = calendar.startOfDay(for: now)
        if !writtenDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while writtenDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    public static func streakLabel(_ streak: Int) -> String {
        switch streak {
        case 0:  return ""
        case 1:  return "🔥 1 day"
        default: return "🔥 \(streak) days"
        }
    }

    /// 0.0 – 1.0
    public static func goalProgress(todayWords: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(todayWords) / Double(goal))
    }

    public static func goalLabel(todayWords: Int, goal: Int) -> String {
        guard goal > 0 else { return "" }
        return todayWords >= goal ? "Goal reached ✓" : "\(todayWords)/\(goal) today"
    }

    /// Lowercased #tags, e.g. "#Work and #gym_2" -> ["work", "gym_2"].
    public static func tags(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"(?<!\w)#([a-zA-Z][a-zA-Z0-9_]*)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { text[$0].lowercased() }
        }
    }

    /// Unique tags across entries, most frequent first (ties alphabetical).
    public static func allTags(in entries: [JournalEntry]) -> [String] {
        var freq: [String: Int] = [:]
        for entry in entries {
            for tag in tags(in: entry.content) { freq[tag, default: 0] += 1 }
        }
        return freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}

// MARK: - Insights

public struct Insights: Equatable, Sendable {
    public let streak: Int
    public let entriesThisYear: Int
    public let wordsThisYear: Int
    public let daysJournaledThisYear: Int
    /// Words written on each of the last seven days, oldest first; the last element is today.
    public let lastSevenDays: [DayActivity]

    public struct DayActivity: Equatable, Sendable {
        public let date: Date
        public let words: Int
    }

    public static func compute(entries: [JournalEntry], now: Date = Date(), calendar: Calendar = .current) -> Insights {
        let year = calendar.component(.year, from: now)
        let thisYear = entries.filter {
            calendar.component(.year, from: $0.createdAt) == year
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let today = calendar.startOfDay(for: now)
        let week: [DayActivity] = (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let words = entries
                .filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
                .reduce(0) { $0 + Stats.wordCount($1.content) }
            return DayActivity(date: day, words: words)
        }
        return Insights(
            streak: Stats.currentStreak(entries: entries, now: now, calendar: calendar),
            entriesThisYear: thisYear.count,
            wordsThisYear: thisYear.reduce(0) { $0 + Stats.wordCount($1.content) },
            daysJournaledThisYear: Set(thisYear.map { calendar.startOfDay(for: $0.createdAt) }).count,
            lastSevenDays: week
        )
    }
}

// MARK: - Timeline grouping

public struct EntrySection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let entries: [JournalEntry]
}

public enum Timeline {
    /// Pinned entries first, then newest-first groups by month ("September 2026").
    public static func sections(for entries: [JournalEntry], calendar: Calendar = .current) -> [EntrySection] {
        var sections: [EntrySection] = []
        let pinned = entries.filter(\.isPinned).sorted { $0.createdAt > $1.createdAt }
        if !pinned.isEmpty { sections.append(EntrySection(id: "pinned", title: "Pinned", entries: pinned)) }

        let rest = entries.filter { !$0.isPinned }.sorted { $0.createdAt > $1.createdAt }
        var current: (key: DateComponents, items: [JournalEntry])?
        func flush() {
            guard let c = current, let first = c.items.first else { return }
            let title = first.createdAt.formatted(.dateTime.month(.wide).year())
            sections.append(EntrySection(id: "\(c.key.year ?? 0)-\(c.key.month ?? 0)", title: title, entries: c.items))
        }
        for entry in rest {
            let key = calendar.dateComponents([.year, .month], from: entry.createdAt)
            if current?.key == key {
                current?.items.append(entry)
            } else {
                flush()
                current = (key, [entry])
            }
        }
        flush()
        return sections
    }

    /// Entries that mention every selected tag (case-insensitive).
    public static func filter(_ entries: [JournalEntry], tags: Set<String>) -> [JournalEntry] {
        guard !tags.isEmpty else { return entries }
        return entries.filter { tags.isSubset(of: Set(Stats.tags(in: $0.content))) }
    }
}
