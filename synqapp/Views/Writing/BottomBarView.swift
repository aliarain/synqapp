
//  BottomBarView.swift
//  SynqApp — bottom utility bar

import SwiftUI
import SynqCore

struct BottomBarView: View {

    @ObservedObject var vm: AppViewModel
    @ObservedObject var prefs: PreferencesService

    @Binding var timerRunning: Bool
    @Binding var timerSeconds: Int
    @Binding var timerTotal: Int
    @Binding var isDictating: Bool

    var onStartVideo: () -> Void
    var onPrompt: (String) -> Void   // called with prompt text
    var onReadingToggle: () -> Void

    let colorScheme: ColorScheme

    @State private var randomFontName: String? = nil

    private var editorBg: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.992, green: 0.992, blue: 0.992)
    }

    var body: some View {
        // Drop the least important controls first as the window narrows, instead of squashing labels.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                fontSection(compact: false)
                Spacer(minLength: 16)
                utilitySection
            }
            HStack(spacing: 0) {
                fontSection(compact: true)
                Spacer(minLength: 16)
                utilitySection
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                utilitySection
            }
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

    private func fontSection(compact: Bool) -> some View {
        FontButtonsSection(
            prefs: prefs,
            colorScheme: colorScheme,
            randomFontName: $randomFontName,
            editorText: vm.editorText,
            entries: vm.entries,
            compact: compact,
            onPrompt: onPrompt
        )
    }

    private var utilitySection: some View {
            UtilityButtonsSection(
                vm: vm,
                prefs: prefs,
                timerRunning: $timerRunning,
                timerSeconds: $timerSeconds,
                timerTotal: $timerTotal,
                isDictating: $isDictating,
                onStartVideo: onStartVideo,
                onReadingToggle: onReadingToggle,
                colorScheme: colorScheme
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
    var compact = false
    var onPrompt: (String) -> Void

    @State private var showFontPicker = false

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    // Label for the font button — shows current font if it's not Arial/Times
    private var fontButtonLabel: String {
        switch prefs.selectedFont {
        case "Arial":            return "Arial"
        case "Times New Roman":  return "Serif"
        default:                 return prefs.selectedFont
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Font size
            BarButton(label: "\(Int(prefs.fontSize))px", color: labelColor) {
                prefs.cycleFontSize()
            }
            if !compact {
            dot(labelColor)

            // Arial
            BarButton(label: "Arial", color: labelColor) {
                prefs.setFont("Arial")
                randomFontName = nil
            }
            dot(labelColor)

            // Serif
            BarButton(label: "Serif", color: labelColor) {
                prefs.setFont("Times New Roman")
                randomFontName = nil
            }
            dot(labelColor)

            // Font picker — shows current custom font name or "Fonts"
            BarButton(
                label: (randomFontName != nil || (prefs.selectedFont != "Arial" && prefs.selectedFont != "Times New Roman"))
                    ? prefs.selectedFont
                    : "Fonts",
                color: labelColor
            ) {
                showFontPicker = true
            }
            .popover(
                isPresented: $showFontPicker,
                attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)),
                arrowEdge: .top
            ) {
                FontPickerPopover(
                    selectedFont: prefs.selectedFont,
                    colorScheme: colorScheme,
                    onSelect: { font in
                        prefs.setFont(font)
                        randomFontName = font
                        showFontPicker = false
                    }
                )
            }

            }

            // ── Stats cluster ────────────────────────────────────────
            if prefs.showWordCount {
                dot(labelColor)
                Text(Stats.wordCountLabel(editorText))
                    .font(.system(size: 12))
                    .foregroundColor(labelColor)
            }

            if prefs.showReadingTime && !compact {
                let rt = Stats.readingTimeLabel(editorText)
                if !rt.isEmpty {
                    dot(labelColor)
                    Text(rt)
                        .font(.system(size: 12))
                        .foregroundColor(labelColor)
                }
            }

            if prefs.showStreak {
                let streak = Stats.currentStreak(entries: entries)
                if streak > 0 {
                    dot(labelColor)
                    Text(Stats.streakLabel(streak))
                        .font(.system(size: 12))
                        .foregroundColor(labelColor)
                }
            }

            if prefs.hasDailyGoal && !compact {
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

// MARK: - Font picker popover

struct FontPickerPopover: View {

    let selectedFont: String
    let colorScheme: ColorScheme
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // All installed font families, cached
    private static let allFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }()

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.allFonts }
        return Self.allFonts.filter { $0.lowercased().contains(q) }
    }

    private var bg: Color {
        colorScheme == .dark
            ? Color(red: 0.1, green: 0.1, blue: 0.1)
            : Color.white
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search fonts…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Font list
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Quick picks at top
                        if searchText.isEmpty {
                            quickPickRow("Arial", label: "Arial")
                            quickPickRow("Times New Roman", label: "Times New Roman")
                            quickPickRow("Georgia", label: "Georgia")
                            quickPickRow("Helvetica Neue", label: "Helvetica Neue")
                            quickPickRow("Menlo", label: "Menlo")
                            Divider().padding(.vertical, 4)
                        }

                        ForEach(filtered, id: \.self) { font in
                            fontRow(font)
                                .id(font)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 320)
                .onAppear {
                    searchFocused = true
                    // Scroll to selected font
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(selectedFont, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 240)
        .background(bg)
    }

    @ViewBuilder
    private func quickPickRow(_ font: String, label: String) -> some View {
        fontRowContent(font: font, displayLabel: label)
    }

    @ViewBuilder
    private func fontRow(_ font: String) -> some View {
        fontRowContent(font: font, displayLabel: font)
    }

    @ViewBuilder
    private func fontRowContent(font: String, displayLabel: String) -> some View {
        let isSelected = selectedFont == font

        Button {
            onSelect(font)
        } label: {
            HStack {
                // Font name in its own typeface
                Text(displayLabel)
                    .font(.custom(font, size: 14))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}

// MARK: - Daily goal indicator

struct DailyGoalIndicator: View {
    let entries: [JournalEntry]
    let goal: Int
    let colorScheme: ColorScheme

    var body: some View {
        let todayWords = Stats.todayWordCount(entries: entries)
        let progress = Stats.goalProgress(todayWords: todayWords, goal: goal)
        let label = Stats.goalLabel(todayWords: todayWords, goal: goal)
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
    var onReadingToggle: () -> Void

    let colorScheme: ColorScheme

    @State private var showingModePicker = false
    @State private var showingChatMenu = false

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    var body: some View {
        HStack(spacing: 8) {

            BarButton(label: "Reflect", color: .accentColor) {
                vm.startReflection()
            }
            .help("Talk this through with AI")

            BarIconButton(icon: "arrow.up.forward.app", color: labelColor, help: "Open in ChatGPT or Claude") {
                showingChatMenu = true
            }
            .popover(isPresented: $showingChatMenu, arrowEdge: .top) {
                ChatMenuView(sourceText: vm.chatSourceText, colorScheme: colorScheme, isPresented: $showingChatMenu)
            }

            dot(labelColor)

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

            // Reading view
            BarIconButton(icon: "book", color: labelColor, help: "Reading view (⌘R)") {
                onReadingToggle()
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
                .lineLimit(1)
                .fixedSize()
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
