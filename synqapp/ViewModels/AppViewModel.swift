//  AppViewModel.swift
//  SynqApp — central state for the main window

import SwiftUI
import Combine
import SynqCore

enum AppMode: Equatable {
    case writing
    case reflect
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

final class AppViewModel: ObservableObject {

    // MARK: State

    @Published var mode: AppMode = .writing
    @Published var entries: [JournalEntry] = []
    @Published var activeEntry: JournalEntry?
    @Published var editorText: String = "" {
        didSet { if editorText != oldValue { scheduleAutosave() } }
    }
    @Published var isReadingMode = false
    @Published var toast: ToastMessage?
    @Published var showOnboarding = false
    @Published var permissionMessage: String?
    @Published var isRecordingVideo = false
    @Published var cameraManager: CameraManager?
    @Published var isWritingRecap = false

    @Published var columnVisibility: NavigationSplitViewVisibility =
        UserDefaults.standard.bool(forKey: "sidebarHidden") ? .detailOnly : .all {
        didSet { UserDefaults.standard.set(columnVisibility == .detailOnly, forKey: "sidebarHidden") }
    }

    let prefs = PreferencesService.shared
    let fileService = FileService.shared
    let timer = FocusTimer()

    private var autosaveTask: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private var recapTask: Task<Void, Never>?

    static let placeholders = [
        "What's on your mind?",
        "Start anywhere…",
        "What happened today?",
        "What are you avoiding thinking about?",
        "What do you wish you'd said?",
        "What made you feel something today?",
        "Describe the last hour honestly.",
        "What's the thing you keep coming back to?",
    ]
    @Published var placeholder: String = placeholders.randomElement()!

    init() {
        prefs.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .quickCaptureDidSave)
            .merge(with: NotificationCenter.default.publisher(for: .notesFolderDidChange))
            .sink { [weak self] _ in self?.loadEntries() }
            .store(in: &cancellables)
        loadEntries()
        showOnboarding = !prefs.hasCompletedOnboarding
    }

    var isZen: Bool { prefs.writingMode == .zen && mode == .writing }

    // MARK: - Entries

    func loadEntries() {
        entries = fileService.loadAll()
        restoreActiveEntry()
    }

    private func restoreActiveEntry() {
        if let match = entries.first(where: { $0.filename == prefs.lastEntryFilename }) ?? entries.first {
            open(match)
            return
        }
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

    func open(_ entry: JournalEntry) {
        saveCurrentEntry()
        mode = .writing
        activeEntry = entry
        editorText = entry.entryType == .video ? "" : entry.body
        autosaveTask?.cancel()
        prefs.lastEntryFilename = entry.filename
        placeholder = Self.placeholders.randomElement()!
    }

    var currentVideoURL: URL? {
        guard let entry = activeEntry, entry.entryType == .video, let vf = entry.videoFilename else { return nil }
        return fileService.videoURL(for: vf)
    }

    func newEntry() {
        saveCurrentEntry()
        mode = .writing
        isReadingMode = false
        if let active = activeEntry, active.entryType == .text,
           active.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        do {
            let entry = try fileService.createNew()
            entries.insert(entry, at: entries.firstIndex(where: { !$0.isPinned }) ?? entries.endIndex)
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
            activeEntry = nil
            if let next = entries.first { open(next) } else { newEntry() }
        }
    }

    func togglePin(_ entry: JournalEntry) {
        saveCurrentEntry()
        fileService.togglePin(entry)
        entries = fileService.loadAll()
        if let id = activeEntry?.id { activeEntry = entries.first { $0.id == id } }
    }

    func saveCurrentEntry() {
        guard var entry = activeEntry, entry.entryType == .text, entry.body != editorText else { return }
        entry.body = editorText
        do {
            let saved = try fileService.save(entry)
            if let idx = entries.firstIndex(where: { $0.id == saved.id }) { entries[idx] = saved }
            activeEntry = saved
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveCurrentEntry() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func insertPrompt() {
        let prompt = WritingPromptsService.shared.randomPrompt()
        let prefix = editorText.isEmpty ? "" : editorText + "\n\n"
        editorText = prefix + prompt + "\n"
    }

    func openFolder() { fileService.openInFinder() }

    // MARK: - Video

    func startVideoRecording() {
        guard cameraManager == nil else { return }
        saveCurrentEntry()
        let manager = CameraManager()
        manager.onReadyToRecord = { [weak self] in
            withAnimation { self?.isRecordingVideo = true }
        }
        manager.onCannotRecord = { [weak self] in
            self?.cameraManager = nil
            self?.permissionMessage = "SynqApp needs camera and microphone access to record video entries. You can allow it in System Settings → Privacy & Security."
        }
        cameraManager = manager
        manager.checkPermissions()
    }

    func finishVideoRecording(url: URL?, transcript: String?) {
        isRecordingVideo = false
        cameraManager = nil
        if let url { saveVideoEntry(from: url, transcript: transcript) }
    }

    private func saveVideoEntry(from tempURL: URL, transcript: String?) {
        let id = UUID()
        let now = Date()
        let filename = fileService.makeFilename(id: id, date: now)
        let videoFilename = EntryFilename.videoName(for: filename)
        let fm = FileManager.default
        do {
            let dir = fileService.videoEntryDir(for: videoFilename)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let destURL = dir.appendingPathComponent(videoFilename)
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.moveItem(at: tempURL, to: destURL)

            let cleaned = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cleaned, !cleaned.isEmpty {
                try cleaned.write(to: fileService.transcriptURL(for: videoFilename), atomically: true, encoding: .utf8)
            }
            try "Video Entry".write(to: fileService.notesDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)

            let entry = JournalEntry(id: id, filename: filename, createdAt: now, body: "Video Entry",
                                     entryType: .video, videoFilename: videoFilename, transcript: cleaned)
            entries.insert(entry, at: entries.firstIndex(where: { !$0.isPinned }) ?? entries.endIndex)
            open(entry)
            if cleaned?.isEmpty ?? true {
                showInfo("Video saved. No transcript: allow Speech Recognition in System Settings to get one.")
            }
        } catch {
            showError("Could not save video: \(error.localizedDescription)")
        }
    }

    // MARK: - Reflect

    func startReflection() {
        saveCurrentEntry()
        isReadingMode = false
        mode = .reflect
    }

    func backToWriting() {
        mode = .writing
    }

    var chatSourceText: String {
        activeEntry?.entryType == .video ? (activeEntry?.content ?? "") : editorText
    }

    func reflectionContext(for scope: ReflectionScope) -> String {
        Reflection.context(scope: scope, currentText: chatSourceText, entries: entries)
    }

    /// Writes an AI recap of the past week into a new entry, streaming it in as it arrives.
    func writeWeeklyRecap() {
        guard !isWritingRecap else { return }
        saveCurrentEntry()
        guard let recap = Reflection.recapRequest(entries: entries) else {
            showInfo("Nothing to recap yet. Write a few entries this week first.")
            return
        }
        guard let request = prefs.aiRequest(system: Reflection.recapSystemPrompt, turns: [ChatTurn(.user, recap.message)]) else {
            showError(AIError.missingKey(prefs.aiProvider).localizedDescription)
            return
        }
        do {
            let entry = try fileService.createNew()
            entries.insert(entry, at: entries.firstIndex(where: { !$0.isPinned }) ?? entries.endIndex)
            open(entry)
        } catch {
            showError(error.localizedDescription)
            return
        }
        isWritingRecap = true
        let entryID = activeEntry?.id
        recapTask = Task { [weak self] in
            do {
                for try await chunk in AIClient().stream(request) {
                    guard let self, self.activeEntry?.id == entryID else { break }
                    self.editorText += chunk
                }
            } catch {
                self?.showError(error.localizedDescription)
            }
            self?.isWritingRecap = false
            self?.saveCurrentEntry()
        }
    }

    // MARK: - Toast

    func showError(_ message: String) {
        let toast = ToastMessage(text: message, isError: true)
        withAnimation { self.toast = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.toast?.id == toast.id { withAnimation { self?.toast = nil } }
        }
    }

    func showInfo(_ message: String) {
        let toast = ToastMessage(text: message, isError: false)
        withAnimation { self.toast = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.toast?.id == toast.id { withAnimation { self?.toast = nil } }
        }
    }
}

// MARK: - Focus timer

/// Counts down only while running, so an idle timer costs nothing (the old one redrew the window every second).
final class FocusTimer: ObservableObject {
    @Published private(set) var remaining: Int = PreferencesService.shared.timerMinutes * 60
    @Published private(set) var isRunning = false
    private var task: Task<Void, Never>?

    var label: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        if remaining == 0 { reset() }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning else { return }
                self.remaining -= 1
                if self.remaining <= 0 {
                    self.isRunning = false
                    NSSound(named: "Glass")?.play()
                    return
                }
            }
        }
    }

    func pause() {
        isRunning = false
        task?.cancel()
    }

    func reset(minutes: Int? = nil) {
        pause()
        if let minutes { PreferencesService.shared.timerMinutes = minutes }
        remaining = PreferencesService.shared.timerMinutes * 60
    }
}
