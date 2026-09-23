//  OnboardingView.swift
//  SynqApp — first-launch welcome sheet

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to SynqApp")
                    .font(.largeTitle.weight(.bold))
                Text("A quiet place to write, and to think it through.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                feature("text.cursor", "Just write",
                        "Flow, Focus, Typewriter and Zen modes keep you in the words. Every entry is a Markdown file you own.")
                feature("bubble.left.and.text.bubble.right", "Reflect",
                        "Talk an entry, your week or your month through with Claude or OpenAI, by typing or out loud.")
                feature("command", "Capture anywhere",
                        "Press ⌥Space in any app to jot a quick note. Record a video entry and SynqApp transcribes it.")
                feature("chart.bar.xaxis", "See your progress",
                        "Streaks, word counts and a week at a glance live in the sidebar.")
            }
            .frame(maxWidth: 380)

            Button(action: onDone) {
                Text("Start Writing").frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 500)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
