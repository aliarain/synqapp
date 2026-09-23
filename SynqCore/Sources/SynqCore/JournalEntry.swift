import Foundation

public enum EntryType: Sendable {
    case text
    case video
}

public struct JournalEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Pattern: [uuid]-[yyyy-MM-dd-HH-mm-ss].md
    public let filename: String
    public let createdAt: Date
    public var body: String
    public var entryType: EntryType
    public var videoFilename: String?
    public var transcript: String?
    public var isPinned: Bool

    public init(
        id: UUID,
        filename: String,
        createdAt: Date,
        body: String,
        entryType: EntryType = .text,
        videoFilename: String? = nil,
        transcript: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
        self.body = body
        self.entryType = entryType
        self.videoFilename = videoFilename
        self.transcript = transcript
        self.isPinned = isPinned
    }

    /// What the entry "says": the written body for text entries, the spoken transcript for video.
    public var content: String {
        switch entryType {
        case .text:  return body
        case .video: return transcript ?? ""
        }
    }

    public var displayDate: String {
        createdAt.formatted(.dateTime.month(.abbreviated).day())
    }

    public var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entryType == .video ? "Video Entry" : "New Note" }
        let first = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let clean = first
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let prefix = entryType == .video ? "🎥 " : ""
        if clean.count <= 30 { return prefix + clean }
        return prefix + String(clean.prefix(30)) + "…"
    }

    public static func == (lhs: JournalEntry, rhs: JournalEntry) -> Bool {
        lhs.id == rhs.id
    }
}

public enum EntryFilename {
    private static let stampFormat = "yyyy-MM-dd-HH-mm-ss"

    private static func formatter() -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = stampFormat
        return df
    }

    public static func make(id: UUID, date: Date) -> String {
        "[\(id.uuidString)]-[\(formatter().string(from: date))].md"
    }

    public static func parse(_ filename: String) -> (id: UUID, date: Date)? {
        guard filename.hasPrefix("["),
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else { return nil }

        let uuidStr = filename[filename.index(after: filename.startIndex)..<divider.lowerBound]
        guard let uuid = UUID(uuidString: String(uuidStr)) else { return nil }

        let stamp = filename[divider.upperBound..<filename.index(filename.endIndex, offsetBy: -4)]
        guard let date = formatter().date(from: String(stamp)) else { return nil }
        return (uuid, date)
    }

    /// Name of the companion video file for an entry's markdown file.
    public static func videoName(for markdownName: String) -> String {
        (markdownName as NSString).deletingPathExtension + ".mov"
    }
}
