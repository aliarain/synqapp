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
