//  synqappApp.swift
//  SynqApp

import SwiftUI
import SynqCore

@main
struct SynqApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = AppViewModel()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("SynqApp", id: "main") {
            ContentView(vm: vm)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { SynqCommands(vm: vm, appDelegate: appDelegate) }

        Settings {
            SettingsView()
        }

        MenuBarExtra("SynqApp", systemImage: "book.closed", isInserted: $showMenuBarIcon) {
            MenuBarContent(appDelegate: appDelegate)
        }
    }
}

// MARK: - Menu bar extra

struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Quick Note") { appDelegate.showQuickCapture() }
        Button("Open SynqApp") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit SynqApp") { NSApp.terminate(nil) }
    }
}

// MARK: - Menu commands

struct SynqCommands: Commands {
    @ObservedObject var vm: AppViewModel
    let appDelegate: AppDelegate

    private var prefs: PreferencesService { vm.prefs }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { vm.newEntry() }
                .keyboardShortcut("n")
            Button("New Quick Note") { appDelegate.showQuickCapture() }
            Button("Record Video Entry") { vm.startVideoRecording() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Menu("Export") {
                if let entry = vm.activeEntry {
                    Button("Entry as PDF…") { EntryExporter.exportPDF(entry, vm: vm) }
                    Button("Entry as Markdown…") { EntryExporter.exportMarkdown(entry, vm: vm) }
                    Button("Entry as Plain Text…") { EntryExporter.exportPlainText(entry, vm: vm) }
                    Divider()
                }
                Button("Entire Journal as ZIP…") { EntryExporter.exportEverything(vm: vm) }
            }
            Button("Show Notes Folder in Finder") { vm.openFolder() }
        }

        CommandMenu("Writing") {
            Picker("Mode", selection: Binding(get: { prefs.writingMode }, set: { prefs.writingMode = $0 })) {
                ForEach(Array(WritingMode.allCases.enumerated()), id: \.element) { index, mode in
                    Text(mode.label).tag(mode)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(vm.isReadingMode ? "Edit Entry" : "Reading View") { vm.isReadingMode.toggle() }
                .keyboardShortcut("r")
            Toggle("Lock Backspace", isOn: Binding(get: { prefs.backspaceLocked }, set: { prefs.backspaceLocked = $0 }))
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Insert Writing Prompt") { vm.insertPrompt() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Bigger") { prefs.adjustFontSize(by: 1) }
                .keyboardShortcut("+")
            Button("Smaller") { prefs.adjustFontSize(by: -1) }
                .keyboardShortcut("-")
            Button("Choose Font…") { FontPanel.show() }
            Divider()
            Button(vm.timer.isRunning ? "Pause Focus Timer" : "Start Focus Timer") { vm.timer.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandMenu("Reflect") {
            Button("Reflect…") { vm.startReflection() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Write This Week's Recap") { vm.writeWeeklyRecap() }
            Divider()
            Button("Open in ChatGPT") { ChatHandoff.open(.chatGPT, text: vm.chatSourceText, vm: vm) }
            Button("Open in Claude") { ChatHandoff.open(.claude, text: vm.chatSourceText, vm: vm) }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var quickCaptureWindow: NSWindow?
    private var quickCaptureHost: NSHostingController<QuickCaptureWindowWrapper>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start global hotkey
        HotKeyService.shared.onTrigger = { [weak self] in
            self?.showQuickCapture()
        }
        HotKeyService.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyService.shared.stop()
    }

    // MARK: - Quick capture window

    func showQuickCapture() {
        if let existing = quickCaptureWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wrapper = QuickCaptureWindowWrapper { [weak self] text in
            self?.saveQuickCapture(text)
        } onDismiss: { [weak self] in
            self?.quickCaptureWindow?.orderOut(nil)
        }

        let host = NSHostingController(rootView: wrapper)
        quickCaptureHost = host

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = host
        window.center()
        window.setFrameAutosaveName("QuickCapture")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true

        quickCaptureWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func saveQuickCapture(_ text: String) {
        do {
            var entry = try FileService.shared.createNew()
            entry.body = text
            try FileService.shared.save(entry)
            NotificationCenter.default.post(name: .quickCaptureDidSave, object: nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let quickCaptureDidSave = Notification.Name("com.synqapp.quickCaptureDidSave")
}

// MARK: - Wrapper to manage dismiss state

struct QuickCaptureWindowWrapper: View {
    var onSave: (String) -> Void
    var onDismiss: () -> Void

    @State private var isPresented = true

    var body: some View {
        QuickCaptureView(isPresented: $isPresented, onSave: onSave)
            .onChange(of: isPresented) { _, presented in if !presented { onDismiss() } }
    }
}
