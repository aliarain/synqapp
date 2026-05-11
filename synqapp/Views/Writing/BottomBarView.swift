
//  BottomBarView.swift
//  SynqApp — bottom utility bar

import SwiftUI

struct BottomBarView: View {

    @ObservedObject var vm: AppViewModel
    @ObservedObject var prefs: PreferencesService

    @Binding var timerRunning: Bool
    @Binding var timerSeconds: Int
    @Binding var timerTotal: Int
    @Binding var isDictating: Bool

    var onStartVideo: () -> Void
    var onPrompt: (String) -> Void   // called with prompt text

    let colorScheme: ColorScheme

    @State private var randomFontName: String? = nil

    private var editorBg: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.992, green: 0.992, blue: 0.992)
    }

    var body: some View {
        HStack(spacing: 0) {
            FontButtonsSection(
                prefs: prefs,
                colorScheme: colorScheme,
                randomFontName: $randomFontName,
                editorText: vm.editorText,
                entries: vm.entries,
                onPrompt: onPrompt
            )
            Spacer()
            UtilityButtonsSection(
                vm: vm,
                prefs: prefs,
                timerRunning: $timerRunning,
                timerSeconds: $timerSeconds,
                timerTotal: $timerTotal,
                isDictating: $isDictating,
                onStartVideo: onStartVideo,
                colorScheme: colorScheme
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [editorBg.opacity(0), editorBg],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Font cluster

struct FontButtonsSection: View {
    @ObservedObject var prefs: PreferencesService
    let colorScheme: ColorScheme
    @Binding var randomFontName: String?
    let editorText: String
    let entries: [JournalEntry]
    var onPrompt: (String) -> Void

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    private var stats: StatsService { StatsService.shared }

    var body: some View {
        HStack(spacing: 8) {
            // Font size
            BarButton(label: "\(Int(prefs.fontSize))px", color: labelColor) {
                prefs.cycleFontSize()
            }
            dot(labelColor)
            BarButton(label: "Arial", color: labelColor) {
                prefs.setFont("Arial"); randomFontName = nil
            }
            dot(labelColor)
            BarButton(label: "Serif", color: labelColor) {
                prefs.setFont("Times New Roman"); randomFontName = nil
            }
            dot(labelColor)
            BarButton(
                label: randomFontName.map { "Random \($0)" } ?? "Random",
                color: labelColor
            ) {
                let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
                if let pick = families.randomElement() {
                    prefs.setFont(pick)
                    randomFontName = pick
                }
            }

            // ── Stats cluster ────────────────────────────────────────
            if prefs.showWordCount {
                dot(labelColor)
                Text(stats.wordCountLabel(editorText))
                    .font(.system(size: 12))
                    .foregroundColor(labelColor)
            }

            if prefs.showReadingTime {
                let rt = stats.readingTimeLabel(editorText)
                if !rt.isEmpty {
                    dot(labelColor)
                    Text(rt)
                        .font(.system(size: 12))
                        .foregroundColor(labelColor)
                }
            }

            if prefs.showStreak {
                let streak = stats.currentStreak(entries: entries)
                if streak > 0 {
                    dot(labelColor)
                    Text(stats.streakLabel(streak))
                        .font(.system(size: 12))
                        .foregroundColor(labelColor)
                }
            }

            if prefs.hasDailyGoal {
                dot(labelColor)
                DailyGoalIndicator(
                    entries: entries,
                    goal: prefs.dailyWordGoal,
                    colorScheme: colorScheme
                )
            }

            // Writing prompt button
            dot(labelColor)
            BarIconButton(icon: "sparkles", color: labelColor, help: "Writing prompt") {
                onPrompt(WritingPromptsService.shared.randomPrompt())
            }
        }
    }

    @ViewBuilder
    private func dot(_ color: Color) -> some View {
        Text("•").font(.system(size: 10)).foregroundColor(color)
    }
}

// MARK: - Daily goal indicator

struct DailyGoalIndicator: View {
    let entries: [JournalEntry]
    let goal: Int
    let colorScheme: ColorScheme

    private var stats: StatsService { StatsService.shared }

    var body: some View {
        let progress = stats.goalProgress(entries: entries, goal: goal)
        let label = stats.goalLabel(entries: entries, goal: goal)
        let done = progress >= 1.0

        HStack(spacing: 5) {
            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(done ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(width: 36, height: 4)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(done ? .green : .secondary)
        }
        .help("Daily goal: \(goal) words")
    }
}

// MARK: - Utility cluster

struct UtilityButtonsSection: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var prefs: PreferencesService

    @Binding var timerRunning: Bool
    @Binding var timerSeconds: Int
    @Binding var timerTotal: Int
    @Binding var isDictating: Bool

    var onStartVideo: () -> Void

    let colorScheme: ColorScheme

    @State private var showingModePicker = false

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    var body: some View {
        HStack(spacing: 8) {

            // Timer
            TimerButtonView(
                isRunning: $timerRunning,
                seconds: $timerSeconds,
                totalSeconds: $timerTotal
            )

            dot(labelColor)

            // Writing mode
            BarButton(label: prefs.writingMode.label, color: labelColor) {
                showingModePicker = true
            }
            .popover(
                isPresented: $showingModePicker,
                attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)),
                arrowEdge: .top
            ) {
                WritingModePicker(
                    mode: Binding(
                        get: { prefs.writingMode },
                        set: { prefs.writingMode = $0 }
                    ),
                    colorScheme: colorScheme,
                    isPresented: $showingModePicker
                )
            }

            dot(labelColor)

            // Video
            BarIconButton(icon: "video.fill", color: labelColor, help: "Record video entry") {
                onStartVideo()
            }

            dot(labelColor)

            // New Entry
            BarIconButton(icon: "square.and.pencil", color: labelColor, help: "New Entry") {
                vm.newEntry()
            }

            dot(labelColor)

            // Theme
            BarIconButton(
                icon: prefs.isDark ? "sun.max.fill" : "moon.fill",
                color: prefs.isDark
                    ? Color(red: 1.0, green: 0.871, blue: 0.408)
                    : Color(red: 0.35, green: 0.35, blue: 0.55),
                help: prefs.isDark ? "Switch to Light" : "Switch to Dark"
            ) {
                prefs.toggleTheme()
            }

            dot(labelColor)

            // Dictation
            BarIconButton(
                icon: "mic.fill",
                color: isDictating ? .red : labelColor,
                help: "Dictation"
            ) {
                isDictating.toggle()
                NSApp.sendAction(Selector(("toggleDictation:")), to: nil, from: nil)
            }

            dot(labelColor)

            // Backspace lock
            BarIconButton(
                icon: prefs.backspaceLocked ? "lock.fill" : "lock.open",
                color: prefs.backspaceLocked ? .orange : labelColor,
                help: prefs.backspaceLocked ? "Unlock backspace" : "Lock backspace"
            ) {
                prefs.backspaceLocked.toggle()
            }

            dot(labelColor)

            // Sidebar / history
            BarIconButton(
                icon: "clock.arrow.circlepath",
                color: vm.sidebarVisible ? .primary : labelColor,
                help: "History"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) { vm.sidebarVisible.toggle() }
            }

            dot(labelColor)

            // Settings
            BarIconButton(
                icon: "gearshape",
                color: labelColor,
                help: "Settings"
            ) {
                vm.showSettings = true
            }
        }
    }

    @ViewBuilder
    private func dot(_ color: Color) -> some View {
        Text("•").font(.system(size: 10)).foregroundColor(color)
    }
}

// MARK: - Reusable controls

struct BarButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(hovering ? .primary : color)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            h ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }
}

struct BarIconButton: View {
    let icon: String
    let color: Color
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(hovering ? .primary : color)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in
            hovering = h
            h ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }
}
