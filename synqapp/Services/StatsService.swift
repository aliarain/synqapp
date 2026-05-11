
//  StatsService.swift
//  SynqApp — word count, reading time, streak, daily goal

import Foundation

final class StatsService {

    static let shared = StatsService()
    private init() {}

    // MARK: - Word count

    func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }

    func wordCountLabel(_ text: String) -> String {
        let count = wordCount(text)
        return count == 1 ? "1 word" : "\(count) words"
    }

    // MARK: - Reading time

    /// Average reading speed ~238 wpm
    func readingTimeLabel(_ text: String) -> String {
        let words = wordCount(text)
        guard words > 0 else { return "" }
        let minutes = max(1, Int(ceil(Double(words) / 238.0)))
        return minutes == 1 ? "~1 min read" : "~\(minutes) min read"
    }

    // MARK: - Daily word count (words written today across all entries)

    func todayWordCount(entries: [JournalEntry]) -> Int {
        let cal = Calendar.current
        let today = Date()
        return entries
            .filter { cal.isDate($0.createdAt, inSameDayAs: today) && $0.entryType == .text }
            .reduce(0) { $0 + wordCount($1.body) }
    }

    // MARK: - Streak

    /// Returns the current consecutive writing streak in days
    func currentStreak(entries: [JournalEntry]) -> Int {
        let cal = Calendar.current
        let textEntries = entries.filter { $0.entryType == .text && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Get unique days that had writing
        let writtenDays = Set(textEntries.map { cal.startOfDay(for: $0.createdAt) })
        guard !writtenDays.isEmpty else { return 0 }

        var streak = 0
        var checkDate = cal.startOfDay(for: Date())

        // If nothing written today, start checking from yesterday
        if !writtenDays.contains(checkDate) {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while writtenDays.contains(checkDate) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return streak
    }

    func streakLabel(_ streak: Int) -> String {
        switch streak {
        case 0: return ""
        case 1: return "🔥 1 day"
        default: return "🔥 \(streak) days"
        }
    }

    // MARK: - Daily goal progress

    /// 0.0 – 1.0
    func goalProgress(entries: [JournalEntry], goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        let today = todayWordCount(entries: entries)
        return min(1.0, Double(today) / Double(goal))
    }

    func goalLabel(entries: [JournalEntry], goal: Int) -> String {
        guard goal > 0 else { return "" }
        let today = todayWordCount(entries: entries)
        if today >= goal {
            return "Goal reached ✓"
        }
        return "\(today)/\(goal) today"
    }

    // MARK: - Tags

    /// Extracts #tags from text
    func extractTags(from text: String) -> [String] {
        let pattern = #"(?<!\w)#([a-zA-Z][a-zA-Z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).lowercased()
        }
    }

    func allTags(from entries: [JournalEntry]) -> [String] {
        let all = entries.flatMap { extractTags(from: $0.body) }
        // Return unique, sorted by frequency
        var freq: [String: Int] = [:]
        all.forEach { freq[$0, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }.map { $0.key }
    }
}
