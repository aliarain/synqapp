//  FileService.swift
//  SynqApp — reads/writes Markdown + video files in the notes folder the user chose

import Foundation
import AppKit
import SynqCore

// MARK: - Save error

enum SaveError: LocalizedError {
    case diskFull
    case permissionDenied
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .diskFull:         return "Disk is full. Free up space and try again."
        case .permissionDenied: return "SynqApp can't write to the notes folder. Choose it again in Settings → Storage."
        case .unknown(let e):   return "Save failed: \(e.localizedDescription)"
        }
    }

    static func from(_ error: Error) -> SaveError {
        switch (error as NSError).code {
        case NSFileWriteOutOfSpaceError:   return .diskFull
        case NSFileWriteNoPermissionError: return .permissionDenied
        default:                           return .unknown(error)
        }
    }
}

extension Notification.Name {
    static let notesFolderDidChange = Notification.Name("com.synqapp.notesFolderDidChange")
}

// MARK: - FileService

final class FileService {

    static let shared = FileService()

    private let fm = FileManager.default
    private let bookmarkKey = "notesFolderBookmark"

    /// Inside the app sandbox this resolves to ~/Library/Containers/com.raptrx.synqapp/Data/Documents/SynqApp.
    let defaultDir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SynqApp", isDirectory: true)

    private(set) var notesDir: URL

    var isUsingDefaultFolder: Bool { notesDir.standardizedFileURL == defaultDir.standardizedFileURL }

    var videosDir: URL { notesDir.appendingPathComponent("Videos", isDirectory: true) }

    private var pinsURL: URL { notesDir.appendingPathComponent(".synqapp-pins.json") }

    private init() {
        notesDir = defaultDir
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                notesDir = url
                if stale { saveBookmark(for: url) }
            }
        }
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        migrateLegacyPins()
    }

    // MARK: - Choosing the folder

    /// Points SynqApp at `newDir` and moves every existing note, video and the pins file there.
    func changeFolder(to newDir: URL) throws {
        let oldDir = notesDir
        guard newDir.standardizedFileURL != oldDir.standardizedFileURL else { return }
        try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        try moveContents(of: oldDir, into: newDir)

        if oldDir != defaultDir { oldDir.stopAccessingSecurityScopedResource() }
        if newDir.standardizedFileURL == defaultDir.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        } else {
            saveBookmark(for: newDir)
        }
        notesDir = newDir
        NotificationCenter.default.post(name: .notesFolderDidChange, object: nil)
    }

    func resetToDefaultFolder() throws {
        try changeFolder(to: defaultDir)
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    private func moveContents(of source: URL, into destination: URL) throws {
        let items = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in items where isSynqItem(item.lastPathComponent) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, fm.fileExists(atPath: target.path) {
                try moveContents(of: item, into: target)
                try? fm.removeItem(at: item)
            } else if !fm.fileExists(atPath: target.path) {
                try fm.moveItem(at: item, to: target)
            }
        }
    }

    /// Only files SynqApp owns move with the folder, so pointing at an existing folder never drags unrelated files around.
    private func isSynqItem(_ name: String) -> Bool {
        EntryFilename.parse(name) != nil || name == "Videos" || name == ".synqapp-pins.json"
            || (name.hasPrefix("[") && (name.hasSuffix(".mov") || !name.contains(".")))
    }

    // MARK: - Pins (stored beside the notes so they travel with the folder)

    private var pinnedIDs: Set<String> {
        get {
            guard let data = try? Data(contentsOf: pinsURL),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(ids)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.sorted()) {
                try? data.write(to: pinsURL, options: .atomic)
            }
        }
    }

    private func migrateLegacyPins() {
        let legacyKey = "pinnedEntryIDs"
        guard let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) else { return }
        pinnedIDs = pinnedIDs.union(legacy)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    func togglePin(_ entry: JournalEntry) {
        var ids = pinnedIDs
        if ids.remove(entry.id.uuidString) == nil { ids.insert(entry.id.uuidString) }
        pinnedIDs = ids
    }

    // MARK: - CRUD

    func makeFilename(id: UUID = UUID(), date: Date = Date()) -> String {
        EntryFilename.make(id: id, date: date)
    }

    func loadAll() -> [JournalEntry] {
        guard let files = try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil) else { return [] }
        let pins = pinnedIDs

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> JournalEntry? in
                let filename = url.lastPathComponent
                guard let (id, date) = EntryFilename.parse(filename),
                      let body = try? String(contentsOf: url, encoding: .utf8)
                else { return nil }

                let videoFilename = EntryFilename.videoName(for: filename)
                let hasVideo = videoExists(videoFilename)

                return JournalEntry(
                    id: id,
                    filename: filename,
                    createdAt: date,
                    body: body,
                    entryType: hasVideo ? .video : .text,
                    videoFilename: hasVideo ? videoFilename : nil,
                    transcript: hasVideo ? loadTranscript(for: videoFilename) : nil,
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
        let url = notesDir.appendingPathComponent(entry.filename)
        do {
            try entry.body.write(to: url, atomically: true, encoding: .utf8)
            return entry
        } catch {
            throw SaveError.from(error)
        }
    }

    /// Moves the entry (and its video) to the Trash so it can be restored from Finder.
    func delete(_ entry: JournalEntry) throws {
        try trash(notesDir.appendingPathComponent(entry.filename))
        if let vf = entry.videoFilename {
            try trash(videoEntryDir(for: vf))
            try trash(videosDir.appendingPathComponent(vf))
        }
        var ids = pinnedIDs
        if ids.remove(entry.id.uuidString) != nil { pinnedIDs = ids }
    }

    private func trash(_ url: URL) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    func createNew(body: String = "") throws -> JournalEntry {
        let id = UUID()
        let now = Date()
        let entry = JournalEntry(id: id, filename: makeFilename(id: id, date: now), createdAt: now, body: body)
        try save(entry)
        return entry
    }

    // MARK: - Welcome note

    func seedWelcomeNote() throws {
        try createNew(body: """
# Welcome to SynqApp

This is your space to think out loud.

Write anything: a thought, a rant, a plan, a feeling. No formatting required. No audience. Just you.

When you're ready, hit **Reflect** in the bottom bar to talk it through with an AI that has actually read what you wrote. Press **⌥Space** anywhere on your Mac to jot a quick note.

---

*Every entry is a plain Markdown file. Choose where they live (an iCloud Drive folder keeps them in sync across your Macs) in Settings → Storage.*
""")
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

    func transcriptURL(for videoFilename: String) -> URL {
        videoEntryDir(for: videoFilename).appendingPathComponent("transcript.md")
    }

    func videoExists(_ videoFilename: String) -> Bool {
        fm.fileExists(atPath: videoEntryDir(for: videoFilename).appendingPathComponent(videoFilename).path) ||
        fm.fileExists(atPath: videosDir.appendingPathComponent(videoFilename).path)
    }

    func loadTranscript(for videoFilename: String) -> String? {
        let url = transcriptURL(for: videoFilename)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Finder

    func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([notesDir])
    }

    // MARK: - Export

    func exportAsMarkdown(_ entry: JournalEntry, to url: URL) throws {
        try entry.content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAsPlainText(_ entry: JournalEntry, to url: URL) throws {
        try PlainText.fromMarkdown(entry.content).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Zips the whole notes folder (entries, videos, transcripts) using the system's built-in archiver.
    func exportAllAsZip(to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: notesDir, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }
}
