
//  ContentView.swift
//  SynqApp — root view, mode switcher, keyboard hooks, toast overlay

import SwiftUI
import Combine

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
                        .frame(minWidth: 800, minHeight: 600)
                case .voiceAgent(let context):
                    VoiceAgentView(vm: vm, context: context, colorScheme: colorScheme)
                        .frame(minWidth: 1100, minHeight: 600)
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
                // Video player or text editor
                if let videoURL = vm.currentVideoURL {
                    VideoPlayerView(videoURL: videoURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditorView(
                        text: $vm.editorText,
                        placeholder: vm.placeholder,
                        font: vm.prefs.selectedFont,
                        fontSize: vm.prefs.fontSize,
                        backspaceLocked: vm.prefs.backspaceLocked,
                        colorScheme: colorScheme
                    )
                    .onChange(of: vm.editorText) { _ in handleTextChange() }
                }

                // Bottom bar
                BottomBarView(
                    vm: vm,
                    prefs: vm.prefs,
                    timerRunning: $timerRunning,
                    timerSeconds: $timerSeconds,
                    timerTotal: $timerTotal,
                    isDictating: $isDictating,
                    onStartVideo: startVideoRecording,
                    colorScheme: colorScheme
                )
                .opacity(bottomNavOpacity)
                .animation(.easeInOut(duration: 1.0), value: bottomNavOpacity)
                .onHover { hovering in
                    isHoveringBar = hovering
                    updateBarOpacity()
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .background(
            colorScheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.08)
                : Color(red: 0.992, green: 0.992, blue: 0.992)
        )
        .background(
            KeyEventHandler(
                backspaceLocked: vm.prefs.backspaceLocked,
                onEscape: handleEscape
            )
        )
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

    // MARK: - Keyboard

    private func handleEscape() {
        guard let window = NSApp.keyWindow else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
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

// MARK: - Key event handler

struct KeyEventHandler: NSViewRepresentable {
    let backspaceLocked: Bool
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.backspaceLocked = backspaceLocked
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.backspaceLocked = backspaceLocked
        nsView.onEscape = onEscape
    }

    class KeyCaptureView: NSView {
        var backspaceLocked = false
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { false }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 53: onEscape?()
            case 51, 117: if backspaceLocked { return }; super.keyDown(with: event)
            default: super.keyDown(with: event)
            }
        }
    }
}
