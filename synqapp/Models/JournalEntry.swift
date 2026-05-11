
//  JournalEntry.swift
//  SynqApp

import Foundation

enum EntryType {
    case text
    case video
}

struct JournalEntry: Identifiable, Equatable {
    let id: UUID
    /// Pattern: [uuid]-[yyyy-MM-dd-HH-mm-ss].md
    let filename: String
    let createdAt: Date
    var body: String
    var entryType: EntryType = .text
    var videoFilename: String? = nil

    // MARK: - Display

    var displayDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: createdAt)
    }

    var preview: String {
        if entryType == .video { return "Video Entry" }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Note" }
        let first = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let clean = first.trimmingCharacters(in: .whitespaces)
        if clean.count <= 30 { return clean }
        return String(clean.prefix(30)) + "…"
    }

    static func == (lhs: JournalEntry, rhs: JournalEntry) -> Bool {
        lhs.id == rhs.id
    }
}
