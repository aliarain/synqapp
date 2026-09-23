//  ContentView.swift
//  SynqApp — main window: sidebar, editor or Reflect, toolbar

import SwiftUI
import SynqCore

struct ContentView: View {

    @ObservedObject var vm: AppViewModel
    @State private var visibilityBeforeZen: NavigationSplitViewVisibility?

    private var prefs: PreferencesService { vm.prefs }

    var body: some View {
        NavigationSplitView(columnVisibility: $vm.columnVisibility) {
            SidebarView(vm: vm)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            Group {
                switch vm.mode {
                case .writing: EditorScreen(vm: vm)
                case .reflect: ReflectView(vm: vm)
                }
            }
            .toolbar { toolbar }
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .toolbar(vm.isZen ? .hidden : .automatic, for: .windowToolbar)
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(prefs.preferredColorScheme)
        .onChange(of: prefs.writingMode) { _, mode in updateZen(mode == .zen) }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                ToastView(toast: toast) { withAnimation { vm.toast = nil } }
                    .padding(.bottom, 44)
            }
        }
        .overlay {
            if vm.isRecordingVideo, let manager = vm.cameraManager {
                VideoRecordingView(manager: manager) { url, transcript in
                    vm.finishVideoRecording(url: url, transcript: transcript)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $vm.showOnboarding) {
            OnboardingView {
                prefs.hasCompletedOnboarding = true
                vm.showOnboarding = false
            }
        }
        .alert("Camera Access Needed", isPresented: Binding(
            get: { vm.permissionMessage != nil },
            set: { if !$0 { vm.permissionMessage = nil } }
        )) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vm.permissionMessage ?? "")
        }
    }

    private var windowTitle: String {
        if vm.mode == .reflect { return "Reflect" }
        guard let entry = vm.activeEntry else { return "SynqApp" }
        let firstLine = vm.editorText.split(separator: "\n").first.map(String.init) ?? ""
        let title = firstLine.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if entry.entryType == .video { return entry.preview }
        return title.isEmpty ? "New Entry" : String(title.prefix(60))
    }

    private var windowSubtitle: String {
        guard vm.mode == .writing, let entry = vm.activeEntry else { return "" }
        return entry.createdAt.formatted(date: .complete, time: .shortened)
    }

    private func updateZen(_ entering: Bool) {
        withAnimation {
            if entering {
                visibilityBeforeZen = vm.columnVisibility
                vm.columnVisibility = .detailOnly
            } else if let previous = visibilityBeforeZen {
                vm.columnVisibility = previous
                visibilityBeforeZen = nil
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if vm.mode == .writing {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Writing Mode", selection: Binding(get: { prefs.writingMode }, set: { prefs.writingMode = $0 })) {
                        ForEach(WritingMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(prefs.writingMode.label, systemImage: prefs.writingMode.icon)
                }
                .help("Writing mode")

                Menu {
                    Button(vm.timer.isRunning ? "Pause" : "Start") { vm.timer.toggle() }
                    Button("Reset") { vm.timer.reset() }
                    Divider()
                    ForEach([5, 10, 15, 25, 45], id: \.self) { minutes in
                        Button("\(minutes) minutes") { vm.timer.reset(minutes: minutes); vm.timer.start() }
                    }
                } label: {
                    Label(vm.timer.label, systemImage: vm.timer.isRunning ? "timer" : "timer")
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                } primaryAction: {
                    vm.timer.toggle()
                }
                .help("Focus timer: click to start or pause")

                Toggle(isOn: $vm.isReadingMode) {
                    Label("Reading View", systemImage: "book")
                }
                .help("Reading view (⌘R)")
                .disabled(vm.currentVideoURL != nil)

                Button(action: vm.startVideoRecording) {
                    Label("Record Video", systemImage: "video")
                }
                .help("Record a video entry")

                ShareMenu(vm: vm)

                Button(action: vm.startReflection) {
                    Label("Reflect", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("Talk it through with AI (⇧⌘R)")
            }
        }
    }
}

// MARK: - Editor screen

struct EditorScreen: View {
    @ObservedObject var vm: AppViewModel
    private var prefs: PreferencesService { vm.prefs }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let url = vm.currentVideoURL, let entry = vm.activeEntry {
                    VideoEntryView(url: url, transcript: entry.transcript)
                } else if vm.isReadingMode {
                    ReadingView(text: vm.editorText, font: prefs.editorFont())
                } else {
                    WritingTextView(
                        text: $vm.editorText,
                        placeholder: vm.placeholder,
                        font: prefs.editorFont(),
                        mode: prefs.writingMode,
                        backspaceLocked: prefs.backspaceLocked,
                        onEscape: prefs.writingMode == .zen ? { prefs.writingMode = .flow } : nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !vm.isZen {
                Divider()
                StatusBar(vm: vm)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var vm: AppViewModel
    private var prefs: PreferencesService { vm.prefs }

    var body: some View {
        HStack(spacing: 14) {
            if vm.activeEntry?.entryType != .video {
                if prefs.showWordCount { Text(Stats.wordCountLabel(vm.editorText)) }
                if prefs.showReadingTime, !vm.editorText.isEmpty { Text(Stats.readingTimeLabel(vm.editorText)) }
            }
            if prefs.showStreak {
                let streak = Stats.currentStreak(entries: vm.entries)
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            if prefs.hasDailyGoal {
                let today = Stats.todayWordCount(entries: vm.entries)
                HStack(spacing: 6) {
                    ProgressView(value: Stats.goalProgress(todayWords: today, goal: prefs.dailyWordGoal))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                    Text(Stats.goalLabel(todayWords: today, goal: prefs.dailyWordGoal))
                }
                .help("Daily goal: \(prefs.dailyWordGoal) words")
            }

            Spacer()

            if vm.isWritingRecap {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Writing your weekly recap…")
                }
            }
            if prefs.backspaceLocked {
                Label("Backspace locked", systemImage: "lock.fill")
            }
            Text(prefs.writingMode.label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Video entry

struct VideoEntryView: View {
    let url: URL
    let transcript: String?

    var body: some View {
        VSplitView {
            VideoPlayerView(videoURL: url)
                .frame(minHeight: 240)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript").font(.headline)
                    Text(transcript ?? "No transcript for this video. Allow Speech Recognition for SynqApp in System Settings → Privacy & Security, then record again.")
                        .foregroundStyle(transcript == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 120)
        }
    }
}
