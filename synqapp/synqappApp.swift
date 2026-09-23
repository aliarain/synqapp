
//  synqappApp.swift
//  SynqApp

import SwiftUI
import SynqCore

@main
struct SynqApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 680)

        MenuBarExtra("SynqApp", systemImage: "pencil.line", isInserted: $showMenuBarIcon) {
            MenuBarContent(appDelegate: appDelegate)
        }
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Note") { appDelegate.showQuickCapture() }
            .keyboardShortcut(.space, modifiers: .option)
        Button("Open SynqApp") {
            if let window = NSApp.windows.first(where: { $0.frameAutosaveName == "SynqAppMain" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit SynqApp") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var quickCaptureWindow: NSWindow?
    private var quickCaptureHost: NSHostingController<QuickCaptureWindowWrapper>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.center()
            window.setFrameAutosaveName("SynqAppMain")
            window.title = "SynqApp"
            // Center the title in the toolbar
            window.titleVisibility = .visible
            window.toolbar = nil   // remove toolbar so title sits centered in titlebar
        }

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
            // Post notification so ContentView can reload entries
            NotificationCenter.default.post(name: .quickCaptureDidSave, object: nil)
        } catch {
            print("[QuickCapture] Save failed: \(error)")
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
            .onChange(of: isPresented) { if !$0 { onDismiss() } }
    }
}
