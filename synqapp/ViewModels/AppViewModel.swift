
//  AppViewModel.swift
//  SynqApp — central state machine

import SwiftUI
import Combine
import SynqCore

// MARK: - App mode

enum AppMode {
    case writing
    case reflectionSelection
    case voiceAgent(context: String)
}

// MARK: - Toast

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

// MARK: - AppViewModel

final class AppViewModel: ObservableObject {

    // MARK: Mode
    @Published var mode: AppMode = .writing

    // MARK: Entries
    @Published var entries: [JournalEntry] = []
    @Published var activeEntry: JournalEntry?

    // MARK: Editor
    @Published var editorText: String = "" {
        didSet { scheduleAutosave() }
    }

    // MARK: Video
    @Published var currentVideoURL: URL? = nil

    // MARK: Sidebar
    @Published var sidebarVisible: Bool = UserDefaults.standard.bool(forKey: "sidebarVisible") {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
    }

    // MARK: Settings
    @Published var showSettings: Bool = false

    // MARK: Toast / error
    @Published var toast: ToastMessage? = nil

    // MARK: Services
    let prefs = PreferencesService.shared
    let fileService = FileService.shared

    // MARK: Autosave
    private var autosaveTask: DispatchWorkItem?
    private var prefsCancellable: AnyCancellable?

    // MARK: Placeholders
    static let placeholders = [
        "What's on your mind?",
        "Start anywhere…",
        "What happened today?",
        "What are you avoiding thinking about?",
        "What do you wish you'd said?",
        "What made you feel something today?",
        "Describe the last hour honestly.",
        "What's the thing you keep coming back to?"
    ]
    @Published var placeholder: String = placeholders.randomElement()!

    // MARK: - Init

    init() {
        // Forward prefs changes through AppViewModel so SwiftUI re-renders on theme/mode changes
        prefsCancellable = prefs.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        loadEntries()
    }

    // MARK: - Entry management

    func loadEntries() {
        entries = fileService.loadAll()
        restoreActiveEntry()
    }

    private func restoreActiveEntry() {
        if !prefs.lastEntryFilename.isEmpty,
           let match = entries.first(where: { $0.filename == prefs.lastEntryFilename }) {
            open(match)
            return
        }
        if let first = entries.first {
            open(first)
        } else {
            // Welcome note only once; an emptied journal just gets a fresh page.
            let seededKey = "hasSeededWelcomeNote"
            do {
                if UserDefaults.standard.bool(forKey: seededKey) {
                    _ = try fileService.createNew()
                } else {
                    try fileService.seedWelcomeNote()
                    UserDefaults.standard.set(true, forKey: seededKey)
                }
                entries = fileService.loadAll()
                if let first = entries.first { open(first) }
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func open(_ entry: JournalEntry) {
        saveCurrentEntry()
        activeEntry = entry
        if entry.entryType == .video, let vf = entry.videoFilename {
            currentVideoURL = fileService.videoURL(for: vf)
            editorText = ""
        } else {
            currentVideoURL = nil
            editorText = entry.body
        }
        prefs.lastEntryFilename = entry.filename
        placeholder = Self.placeholders.randomElement()!
    }

    func newEntry() {
        saveCurrentEntry()
        // Don't duplicate if today's active entry is already empty text
        if let active = activeEntry,
           active.entryType == .text,
           active.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        do {
            let entry = try fileService.createNew()
            entries.insert(entry, at: 0)
            open(entry)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func delete(_ entry: JournalEntry) {
        do {
            try fileService.delete(entry)
        } catch {
            showError("Couldn't move the entry to the Trash: \(error.localizedDescription)")
            return
        }
        entries.removeAll { $0.id == entry.id }
        if activeEntry?.id == entry.id {
            if let next = entries.first { open(next) }
            else { newEntry() }
        }
    }

    func togglePin(_ entry: JournalEntry) {
        fileService.togglePin(entry)
        // Reload to get updated sort order (pinned first)
        let activeID = activeEntry?.id
        entries = fileService.loadAll()
        if let id = activeID, let restored = entries.first(where: { $0.id == id }) {
            activeEntry = restored
        }
    }

    func saveCurrentEntry() {
        guard var entry = activeEntry, entry.entryType == .text else { return }
        entry.body = editorText
        do {
            let saved = try fileService.save(entry)
            if let idx = entries.firstIndex(where: { $0.id == saved.id }) {
                entries[idx] = saved
            }
            activeEntry = saved
        } catch let e as SaveError {
            showError(e.localizedDescription)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveCurrentEntry()
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    // MARK: - Video entry

    func saveVideoEntry(from tempURL: URL, transcript: String?) {
        let id = UUID()
        let now = Date()
        let filename = fileService.makeFilename(id: id, date: now)
        let videoFilename = EntryFilename.videoName(for: filename)

        do {
            // Create video entry directory
            let dir = fileService.videoEntryDir(for: videoFilename)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Copy video
            let destURL = dir.appendingPathComponent(videoFilename)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destURL)

            // Save transcript
            if let t = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                try t.write(to: fileService.transcriptURL(for: videoFilename), atomically: true, encoding: .utf8)
            }

            // Save metadata .md
            let metaURL = fileService.notesDir.appendingPathComponent(filename)
            try "Video Entry".write(to: metaURL, atomically: true, encoding: .utf8)

            let entry = JournalEntry(
                id: id,
                filename: filename,
                createdAt: now,
                body: "Video Entry",
                entryType: .video,
                videoFilename: videoFilename,
                transcript: transcript
            )
            entries.insert(entry, at: 0)
            open(entry)
        } catch {
            showError("Could not save video: \(error.localizedDescription)")
        }
    }

    // MARK: - Navigation

    func startReflection() {
        saveCurrentEntry()
        mode = .reflectionSelection
    }

    func selectScope(_ scope: ReflectionScope) {
        let context = Reflection.context(scope: scope, currentText: chatSourceText, entries: entries)
        mode = .voiceAgent(context: context)
    }

    func backToWriting() {
        mode = .writing
    }

    // MARK: - Chat prompt helpers

    var chatSourceText: String {
        if activeEntry?.entryType == .video {
            return activeEntry?.content ?? ""
        }
        return editorText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Folder

    func openFolder() {
        fileService.openInFinder()
    }

    // MARK: - Toast

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.toast = ToastMessage(text: message, isError: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.toast?.isError == true { self.toast = nil }
        }
    }

    func showInfo(_ message: String) {
        DispatchQueue.main.async {
            self.toast = ToastMessage(text: message, isError: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.toast = nil
        }
    }
}
