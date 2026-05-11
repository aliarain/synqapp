
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

    let colorScheme: ColorScheme

    @State private var randomFontName: String? = nil

    // Exact same color as the editor background — no visible seam
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
                randomFontName: $randomFontName
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
            // Fades from transparent at top to solid editor color at bottom
            // so the bar dissolves into the page — no visible border or contrast
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

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    var body: some View {
        HStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private func dot(_ color: Color) -> some View {
        Text("•").font(.system(size: 10)).foregroundColor(color)
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

    @State private var showingChatMenu = false

    private var labelColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray
    }

    var body: some View {
        HStack(spacing: 8) {
            // Reflect
            BarButton(label: "Reflect", color: labelColor) { vm.startReflection() }

            dot(labelColor)

            // Timer
            TimerButtonView(
                isRunning: $timerRunning,
                seconds: $timerSeconds,
                totalSeconds: $timerTotal
            )

            dot(labelColor)

            // Video
            BarIconButton(icon: "video.fill", color: labelColor, help: "Record video entry") {
                onStartVideo()
            }

            dot(labelColor)

            // Chat
            BarButton(label: "Chat", color: labelColor) { showingChatMenu = true }
                .popover(isPresented: $showingChatMenu,
                         attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)),
                         arrowEdge: .top) {
                    ChatMenuView(
                        sourceText: vm.chatSourceText,
                        colorScheme: colorScheme,
                        isPresented: $showingChatMenu
                    )
                }

            dot(labelColor)

            // New Entry
            BarIconButton(icon: "square.and.pencil", color: labelColor, help: "New Entry") {
                vm.newEntry()
            }

            dot(labelColor)

            // Theme
            BarIconButton(
                icon: colorScheme == .dark ? "sun.max" : "moon",
                color: labelColor,
                help: "Toggle theme"
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

            // Sidebar
            BarIconButton(
                icon: "clock.arrow.circlepath",
                color: vm.sidebarVisible ? .primary : labelColor,
                help: "History"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) { vm.sidebarVisible.toggle() }
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
