
//  FileService.swift
//  SynqApp — reads/writes Markdown + video files in ~/Documents/SynqApp/

import Foundation
import AppKit

// MARK: - Save error

enum SaveError: LocalizedError {
    case diskFull
    case permissionDenied
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .diskFull:         return "Disk is full. Free up space and try again."
        case .permissionDenied: return "Permission denied. Check folder access in System Settings."
        case .unknown(let e):   return "Save failed: \(e.localizedDescription)"
        }
    }

    static func from(_ error: Error) -> SaveError {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteOutOfSpaceError:          return .diskFull
        case NSFileWriteNoPermissionError:        return .permissionDenied
        default:                                  return .unknown(error)
        }
    }
}

// MARK: - FileService

final class FileService {

    static let shared = FileService()

    // ~/Documents/SynqApp/
    let synqDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SynqApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // ~/Documents/SynqApp/Videos/
    lazy var videosDir: URL = {
        let dir = synqDir.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let fm = FileManager.default

    // MARK: - Filename helpers

    /// Pattern: [uuid]-[yyyy-MM-dd-HH-mm-ss].md
    func makeFilename(id: UUID = UUID(), date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "[\(id.uuidString)]-[\(df.string(from: date))].md"
    }

    func parseComponents(from filename: String) -> (id: UUID, date: Date)? {
        guard filename.hasPrefix("["),
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else { return nil }

        let uuidStr = String(filename[filename.index(after: filename.startIndex)..<divider.lowerBound])
        guard let uuid = UUID(uuidString: uuidStr) else { return nil }

        let tsStart = divider.upperBound
        let tsEnd = filename.index(filename.endIndex, offsetBy: -4)
        let tsStr = String(filename[tsStart..<tsEnd])
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        guard let date = df.date(from: tsStr) else { return nil }

        return (uuid, date)
    }

    // MARK: - CRUD

    // Pinned entry IDs persisted in UserDefaults
    private var pinnedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "pinnedEntryIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "pinnedEntryIDs") }
    }

    func togglePin(_ entry: JournalEntry) {
        var ids = pinnedIDs
        if ids.contains(entry.id.uuidString) {
            ids.remove(entry.id.uuidString)
        } else {
            ids.insert(entry.id.uuidString)
        }
        pinnedIDs = ids
    }

    func isPinned(_ entry: JournalEntry) -> Bool {
        pinnedIDs.contains(entry.id.uuidString)
    }

    func loadAll() -> [JournalEntry] {
        guard let files = try? fm.contentsOfDirectory(at: synqDir, includingPropertiesForKeys: nil) else { return [] }
        let pins = pinnedIDs

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> JournalEntry? in
                let filename = url.lastPathComponent
                guard let (id, date) = parseComponents(from: filename),
                      let body = try? String(contentsOf: url, encoding: .utf8)
                else { return nil }

                let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
                let hasVideo = videoExists(videoFilename)

                return JournalEntry(
                    id: id,
                    filename: filename,
                    createdAt: date,
                    body: body,
                    entryType: hasVideo ? .video : .text,
                    videoFilename: hasVideo ? videoFilename : nil,
                    isPinned: pins.contains(id.uuidString)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
    }

    @discardableResult
    func save(_ entry: JournalEntry) throws -> JournalEntry {
        let url = synqDir.appendingPathComponent(entry.filename)
        do {
            try entry.body.write(to: url, atomically: true, encoding: .utf8)
            return entry
        } catch {
            throw SaveError.from(error)
        }
    }

    func delete(_ entry: JournalEntry) {
        let url = synqDir.appendingPathComponent(entry.filename)
        try? fm.removeItem(at: url)
        if let vf = entry.videoFilename { deleteVideoAssets(vf) }
    }

    func createNew() throws -> JournalEntry {
        let id = UUID()
        let now = Date()
        let filename = makeFilename(id: id, date: now)
        let entry = JournalEntry(id: id, filename: filename, createdAt: now, body: "")
        try save(entry)
        return entry
    }

    // MARK: - Welcome note

    func seedWelcomeNoteIfNeeded() throws {
        let welcome = """
# Welcome to SynqApp

This is your space to think out loud.

Write anything — a thought, a rant, a plan, a feeling. No formatting required. No audience. Just you.

When you're ready, hit **Reflect** to talk it through with an AI that's actually read what you wrote.

---

*Start writing below. Your notes save automatically to ~/Documents/SynqApp/*
"""
        let id = UUID()
        let filename = makeFilename(id: id, date: Date())
        let entry = JournalEntry(id: id, filename: filename, createdAt: Date(), body: welcome)
        try save(entry)
    }

    // MARK: - Video helpers

    func videoEntryDir(for videoFilename: String) -> URL {
        let base = (videoFilename as NSString).deletingPathExtension
        return videosDir.appendingPathComponent(base, isDirectory: true)
    }

    func videoURL(for videoFilename: String) -> URL {
        let managed = videoEntryDir(for: videoFilename).appendingPathComponent(videoFilename)
        if fm.fileExists(atPath: managed.path) { return managed }
        let flat = videosDir.appendingPathComponent(videoFilename)
        if fm.fileExists(atPath: flat.path) { return flat }
        return managed
    }

    func thumbnailURL(for videoFilename: String) -> URL {
        videoEntryDir(for: videoFilename).appendingPathComponent("thumbnail.jpg")
    }

    func transcriptURL(for videoFilename: String) -> URL {
        videoEntryDir(for: videoFilename).appendingPathComponent("transcript.md")
    }

    func videoExists(_ videoFilename: String) -> Bool {
        fm.fileExists(atPath: videoEntryDir(for: videoFilename).appendingPathComponent(videoFilename).path) ||
        fm.fileExists(atPath: videosDir.appendingPathComponent(videoFilename).path)
    }

    func deleteVideoAssets(_ videoFilename: String) {
        let dir = videoEntryDir(for: videoFilename)
        try? fm.removeItem(at: dir)
        try? fm.removeItem(at: videosDir.appendingPathComponent(videoFilename))
    }

    func loadTranscript(for videoFilename: String) -> String? {
        let url = transcriptURL(for: videoFilename)
        guard fm.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Open in Finder

    func openInFinder() {
        NSWorkspace.shared.open(synqDir)
    }

    // MARK: - Export

    func exportAsMarkdown(_ entry: JournalEntry, to url: URL) throws {
        try entry.body.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAsPlainText(_ entry: JournalEntry, to url: URL) throws {
        // Strip markdown syntax for plain text
        var text = entry.body
        // Remove heading markers
        text = text.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        // Remove bold/italic markers
        text = text.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"_{1,3}([^_]+)_{1,3}"#, with: "$1", options: .regularExpression)
        // Remove inline code
        text = text.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAllAsZip(entries: [JournalEntry], to url: URL) throws {
        // Write all .md files to a temp folder then zip
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SynqApp-Export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        for entry in entries where entry.entryType == .text {
            let name = entry.filename
            let dest = tmp.appendingPathComponent(name)
            try entry.body.write(to: dest, atomically: true, encoding: .utf8)
        }

        // Use Process to zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", url.path, "."]
        process.currentDirectoryURL = tmp
        try process.run()
        process.waitUntilExit()

        // Clean up temp
        try? fm.removeItem(at: tmp)
    }
}
