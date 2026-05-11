
//  OnboardingView.swift
//  SynqApp — one-time welcome + feature setup

import SwiftUI

struct OnboardingView: View {

    @ObservedObject var prefs: PreferencesService
    var onDone: () -> Void

    @State private var page = 0
    private let totalPages = 3

    var body: some View {
        ZStack {
            // Background
            (prefs.isDark
                ? Color(red: 0.08, green: 0.08, blue: 0.08)
                : Color(red: 0.992, green: 0.992, blue: 0.992))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    goalsPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: page)

                // Dots + button
                VStack(spacing: 20) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: page)
                        }
                    }

                    // Action button
                    Button(action: advance) {
                        Text(page == totalPages - 1 ? "Start Writing" : "Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                    if page < totalPages - 1 {
                        Button("Skip") { finish() }
                            .buttonStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("✦")
                .font(.system(size: 48))
            Text("Welcome to SynqApp")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("A calm place to write, reflect, and think.\nYour notes live locally — always yours.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Set up your experience")
                .font(.system(size: 22, weight: .semibold))
                .padding(.bottom, 24)

            VStack(spacing: 0) {
                OnboardingToggleRow(
                    icon: "number",
                    title: "Word count",
                    subtitle: "See words written in the bottom bar",
                    isOn: Binding(get: { prefs.showWordCount }, set: { prefs.showWordCount = $0 })
                )
                Divider().padding(.leading, 44)
                OnboardingToggleRow(
                    icon: "clock",
                    title: "Reading time",
                    subtitle: "Estimated read time for each entry",
                    isOn: Binding(get: { prefs.showReadingTime }, set: { prefs.showReadingTime = $0 })
                )
                Divider().padding(.leading, 44)
                OnboardingToggleRow(
                    icon: "flame",
                    title: "Writing streak",
                    subtitle: "Track consecutive days you've written",
                    isOn: Binding(get: { prefs.showStreak }, set: { prefs.showStreak = $0 })
                )
                Divider().padding(.leading, 44)
                OnboardingToggleRow(
                    icon: "tag",
                    title: "Tags",
                    subtitle: "Use #tags in entries to organize them",
                    isOn: Binding(get: { prefs.showTags }, set: { prefs.showTags = $0 })
                )
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var goalsPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("Set a daily writing goal")
                .font(.system(size: 22, weight: .semibold))
            Text("Optional — pick a word count to aim for each day.\nYou can change this anytime in Settings.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Goal picker
            HStack(spacing: 12) {
                ForEach([0, 100, 250, 500, 750, 1000], id: \.self) { goal in
                    Button {
                        prefs.dailyWordGoal = goal
                    } label: {
                        Text(goal == 0 ? "None" : "\(goal)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(prefs.dailyWordGoal == goal ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                prefs.dailyWordGoal == goal
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Navigation

    private func advance() {
        if page < totalPages - 1 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        prefs.hasCompletedOnboarding = true
        onDone()
    }
}

// MARK: - Toggle row

struct OnboardingToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
