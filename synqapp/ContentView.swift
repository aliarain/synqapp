
//  ContentView.swift
//  SynqApp — root view, mode switcher, keyboard hooks, toast overlay

import SwiftUI
import Combine
import SynqCore

struct ContentView: View {

    @StateObject private var vm = AppViewModel()
    @Environment(\.colorScheme) private var systemColorScheme

    // Timer
    @State private var timerRunning = false
    @State private var timerSeconds = 900
    @State private var timerTotal = 900

    // Bottom bar fade
    @State private var bottomNavOpacity: Double = 1.0
    @State private var isHoveringBar = false

    // Dictation
    @State private var isDictating = false

    // Typing idle
    @State private var idleTask: DispatchWorkItem?

    // Video recording
    @State private var showingVideoRecording = false
    @State private var isPreparingVideo = false
    @State private var preparedCameraManager: CameraManager?
    @State private var showingPermissionAlert = false
    @State private var permissionMessage = ""

    // Onboarding
    @State private var showOnboarding = false

    // Search
    @State private var showSearch = false

    // Reading view
    @State private var isReadingMode = false

    private var colorScheme: ColorScheme {
        vm.prefs.preferredColorScheme ?? systemColorScheme
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch vm.mode {
                case .writing:
                    writingView
                case .reflectionSelection:
                    ReflectionSelectionView(vm: vm, colorScheme: colorScheme)
                        .frame(minWidth: 720, minHeight: 500)
                case .voiceAgent(let context):
                    VoiceAgentView(vm: vm, context: context, colorScheme: colorScheme)
                        .frame(minWidth: 720, minHeight: 500)
                }
            }

            // Toast
            if let toast = vm.toast {
                ToastView(toast: toast) { vm.toast = nil }
                    .padding(.bottom, 80)
                    .padding(.horizontal, 20)
                    .animation(.spring(), value: vm.toast?.id)
            }
        }
        .preferredColorScheme(vm.prefs.preferredColorScheme)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickTimer()
        }
        .sheet(isPresented: $vm.showSettings) {
            SettingsView(colorScheme: colorScheme)
        }
        // Onboarding — one time only
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(prefs: vm.prefs) { showOnboarding = false }
        }
        .onAppear {
            if !vm.prefs.hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOnboarding = true
                }
            }
        }
        // Reload entries when quick capture saves
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureDidSave)) { _ in
            vm.loadEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notesFolderDidChange)) { _ in
            vm.loadEntries()
        }
        // Search overlay
        .overlay {
            if showSearch {
                SearchView(
                    isPresented: $showSearch,
                    entries: vm.entries,
                    colorScheme: colorScheme
                ) { entry in
                    vm.open(entry)
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        // Video recording overlay
        .overlay {
            if showingVideoRecording {
                VideoRecordingView(
                    isPresented: $showingVideoRecording,
                    cameraManager: preparedCameraManager
                ) { url, transcript in
                    vm.saveVideoEntry(from: url, transcript: transcript)
                    showingVideoRecording = false
                    preparedCameraManager = nil
                }
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permissionMessage)
        }
    }

    // MARK: - Writing view

    @ViewBuilder
    private var writingView: some View {
        HStack(spacing: 0) {
            // Sidebar
            if vm.sidebarVisible {
                SidebarView(vm: vm, colorScheme: colorScheme)
                    .transition(.move(edge: .leading))
                Divider()
            }

            // Editor + bottom bar
            ZStack(alignment: .bottom) {
                // Video player or text editor or reading view
                if let videoURL = vm.currentVideoURL {
                    VideoPlayerView(videoURL: videoURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isReadingMode {
                    ReadingView(
                        text: vm.editorText,
                        font: vm.prefs.selectedFont,
                        fontSize: vm.prefs.fontSize,
                        colorScheme: colorScheme,
                        onExit: { withAnimation { isReadingMode = false } }
                    )
                } else {
                    TextEditorView(
                        text: $vm.editorText,
                        placeholder: vm.placeholder,
                        font: vm.prefs.selectedFont,
                        fontSize: vm.prefs.fontSize,
                        backspaceLocked: vm.prefs.backspaceLocked,
                        colorScheme: colorScheme,
                        writingMode: vm.prefs.writingMode
                    )
                    .onChange(of: vm.editorText) { _ in handleTextChange() }
                }

                // Bottom bar — hidden in Zen unless hovering
                if vm.prefs.writingMode != .zen || isHoveringBar {
                    BottomBarView(
                        vm: vm,
                        prefs: vm.prefs,
                        timerRunning: $timerRunning,
                        timerSeconds: $timerSeconds,
                        timerTotal: $timerTotal,
                        isDictating: $isDictating,
                        onStartVideo: startVideoRecording,
                        onPrompt: { prompt in
                            let prefix = vm.editorText.isEmpty ? "" : vm.editorText + "\n\n"
                            vm.editorText = prefix + prompt + "\n"
                        },
                        onReadingToggle: { withAnimation { isReadingMode.toggle() } },
                        colorScheme: colorScheme
                    )
                    .opacity(bottomNavOpacity)
                    .animation(.easeInOut(duration: 1.0), value: bottomNavOpacity)
                    .onHover { hovering in
                        isHoveringBar = hovering
                        updateBarOpacity()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: vm.sidebarVisible ? 1020 : 720, minHeight: 500)
        .background(
            colorScheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.08)
                : Color(red: 0.992, green: 0.992, blue: 0.992)
        )
        .keyboardShortcuts(
            backspaceLocked: vm.prefs.backspaceLocked,
            writingMode: vm.prefs.writingMode,
            onModeChange: { vm.prefs.writingMode = $0 },
            onZenExit: {
                if vm.prefs.writingMode == .zen { vm.prefs.writingMode = .flow }
            },
            onSearch: { withAnimation { showSearch = true } },
            onReadingToggle: { withAnimation { isReadingMode.toggle() } }
        )
        // Zen mode hides the bottom bar entirely
        .onChange(of: vm.prefs.writingMode) { mode in
            if mode == .zen {
                withAnimation(.easeInOut(duration: 0.5)) { bottomNavOpacity = 0 }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { bottomNavOpacity = 1 }
            }
        }
    }

    // MARK: - Timer

    private func tickTimer() {
        guard timerRunning else { return }
        if timerSeconds > 0 {
            timerSeconds -= 1
        } else {
            timerRunning = false
            timerSeconds = timerTotal
            withAnimation(.easeInOut(duration: 1.0)) { bottomNavOpacity = 1.0 }
        }
        updateBarOpacity()
    }

    private func updateBarOpacity() {
        if isHoveringBar || !timerRunning {
            withAnimation(.easeInOut(duration: 0.3)) { bottomNavOpacity = 1.0 }
        } else {
            withAnimation(.easeInOut(duration: 1.0)) { bottomNavOpacity = 0.0 }
        }
    }

    // MARK: - Typing idle

    private func handleTextChange() {
        idleTask?.cancel()
        let task = DispatchWorkItem {
            if timerRunning { timerRunning = false }
        }
        idleTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    // MARK: - Video recording

    private func startVideoRecording() {
        guard !isPreparingVideo else { return }
        isPreparingVideo = true

        let manager = CameraManager()
        manager.onReadyToRecord = {
            DispatchQueue.main.async {
                preparedCameraManager = manager
                isPreparingVideo = false
                withAnimation { showingVideoRecording = true }
            }
        }
        manager.onCannotRecord = {
            DispatchQueue.main.async {
                isPreparingVideo = false
                permissionMessage = "SynqApp needs camera and microphone access to record video entries. Please enable them in System Settings."
                showingPermissionAlert = true
            }
        }
        manager.checkPermissions()
        preparedCameraManager = manager
    }
}

// MARK: - Keyboard shortcut monitor (ViewModifier)
// NSEvent.addLocalMonitorForEvents intercepts before NSTextView gets it

struct KeyboardShortcutMonitor: ViewModifier {
    let backspaceLocked: Bool
    let writingMode: WritingMode
    let onModeChange: (WritingMode) -> Void
    let onZenExit: () -> Void
    let onSearch: () -> Void
    let onReadingToggle: () -> Void

    @State private var monitor: Any? = nil

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { remove() }
            .onChange(of: backspaceLocked) { _ in reinstall() }
            .onChange(of: writingMode.rawValue) { _ in reinstall() }
    }

    private func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) &&
               !event.modifierFlags.contains(.shift) &&
               !event.modifierFlags.contains(.option) {
                switch event.charactersIgnoringModifiers {
                case "1": DispatchQueue.main.async { self.onModeChange(.flow) };       return nil
                case "2": DispatchQueue.main.async { self.onModeChange(.focus) };      return nil
                case "3": DispatchQueue.main.async { self.onModeChange(.typewriter) }; return nil
                case "4": DispatchQueue.main.async { self.onModeChange(.zen) };        return nil
                case "f": DispatchQueue.main.async { self.onSearch() };                return nil
                case "r": DispatchQueue.main.async { self.onReadingToggle() };         return nil
                default: break
                }
            }

            if event.keyCode == 53 {
                if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                    DispatchQueue.main.async { window.toggleFullScreen(nil) }
                    return nil
                }
                var shouldConsume = false
                if Thread.isMainThread {
                    shouldConsume = self.writingMode == .zen
                } else {
                    DispatchQueue.main.sync { shouldConsume = self.writingMode == .zen }
                }
                if shouldConsume {
                    DispatchQueue.main.async { self.onZenExit() }
                    return nil
                }
                return event
            }

            if self.backspaceLocked && (event.keyCode == 51 || event.keyCode == 117) {
                return nil
            }

            return event
        }
    }

    private func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func reinstall() { install() }
}

extension View {
    func keyboardShortcuts(
        backspaceLocked: Bool,
        writingMode: WritingMode,
        onModeChange: @escaping (WritingMode) -> Void,
        onZenExit: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onReadingToggle: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardShortcutMonitor(
            backspaceLocked: backspaceLocked,
            writingMode: writingMode,
            onModeChange: onModeChange,
            onZenExit: onZenExit,
            onSearch: onSearch,
            onReadingToggle: onReadingToggle
        ))
    }
}
