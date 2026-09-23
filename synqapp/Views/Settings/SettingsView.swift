
//  SettingsView.swift
//  SynqApp — API key configuration, model selection, voice backend

import SwiftUI
import SynqCore

struct SettingsView: View {

    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var prefs = PreferencesService.shared

    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var keyStatus: KeyStatus? = nil
    @State private var notesPath = FileService.shared.notesDir.path
    @State private var storageError: String?

    enum KeyStatus {
        case saved, testing, valid, failure(String)
    }

    private var provider: AIProvider { prefs.aiProvider }

    private var bg: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.992, green: 0.992, blue: 0.992)
    }

    private var cardBg: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Settings")
                                .font(.system(size: 26, weight: .semibold))
                            Text("Your keys are stored in the system Keychain — never in plain text.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // ── AI ───────────────────────────────────────────────
                    SettingsSection(title: "AI Reflection", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Provider", selection: Binding(
                                get: { prefs.aiProvider },
                                set: { prefs.aiProvider = $0; loadKey() }
                            )) {
                                ForEach(AIProvider.allCases) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(provider.displayName) API key", systemImage: "key.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    Group {
                                        if showKey {
                                            TextField(provider.keyPlaceholder, text: $apiKey)
                                        } else {
                                            SecureField(provider.keyPlaceholder, text: $apiKey)
                                        }
                                    }
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    )
                                    .onSubmit(saveAndTestKey)

                                    Button { showKey.toggle() } label: {
                                        Image(systemName: showKey ? "eye.slash" : "eye")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(showKey ? "Hide key" : "Show key")
                                }

                                HStack(spacing: 10) {
                                    Button("Save & Test", action: saveAndTestKey)
                                        .controlSize(.small)
                                        .disabled(isTesting)
                                    keyStatusLabel
                                    Spacer()
                                    Link("Get a key →", destination: provider.keyConsoleURL)
                                        .font(.system(size: 12))
                                }
                                Text("Stored in your Mac's Keychain. Your entries go straight from this Mac to \(provider.displayName), only when you reflect.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Label("Model", systemImage: "cpu")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("Model", selection: Binding(
                                    get: { prefs.aiModel(for: provider) },
                                    set: { prefs.setAIModel($0, for: provider) }
                                )) {
                                    ForEach(provider.suggestedModels) { m in
                                        Text("\(m.name) · \(m.blurb)").tag(m.id)
                                    }
                                    if !provider.suggestedModels.contains(where: { $0.id == prefs.aiModel(for: provider) }) {
                                        Text("Custom · \(prefs.aiModel(for: provider))").tag(prefs.aiModel(for: provider))
                                    }
                                }
                                .labelsHidden()

                                HStack(spacing: 6) {
                                    Text("Model ID")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    TextField(provider.defaultModel, text: Binding(
                                        get: { prefs.aiModel(for: provider) },
                                        set: { prefs.setAIModel($0, for: provider) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }

                    // ── Storage ──────────────────────────────────────────
                    SettingsSection(title: "Storage", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes folder", systemImage: "folder")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(notesPath)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                            HStack(spacing: 8) {
                                Button("Change Folder…", action: chooseFolder).controlSize(.small)
                                Button("Show in Finder") { FileService.shared.openInFinder() }.controlSize(.small)
                                if !FileService.shared.isUsingDefaultFolder {
                                    Button("Use Default") { moveNotes { try FileService.shared.resetToDefaultFolder() } }
                                        .controlSize(.small)
                                }
                            }
                            Text("Entries are plain Markdown files. Pick a folder in iCloud Drive to sync them across your Macs. Existing notes and videos move with you.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let storageError {
                                Text(storageError).font(.system(size: 11)).foregroundColor(.red)
                            }
                        }
                    }

                    // ── Writing Features ─────────────────────────────────
                    SettingsSection(title: "Writing Features", colorScheme: colorScheme) {
                        VStack(spacing: 0) {
                            SettingsToggleRow(icon: "number", title: "Word count",
                                             subtitle: "Show live word count in the bottom bar",
                                             isOn: $prefs.showWordCount)
                            Divider().padding(.leading, 44)
                            SettingsToggleRow(icon: "clock", title: "Reading time",
                                             subtitle: "Estimated read time shown in bottom bar",
                                             isOn: $prefs.showReadingTime)
                            Divider().padding(.leading, 44)
                            SettingsToggleRow(icon: "flame", title: "Writing streak",
                                             subtitle: "Track consecutive days you've written",
                                             isOn: $prefs.showStreak)
                            Divider().padding(.leading, 44)
                            SettingsToggleRow(icon: "tag", title: "Tags",
                                             subtitle: "Parse #tags from entries for filtering",
                                             isOn: $prefs.showTags)
                            Divider().padding(.leading, 44)

                            // Daily word goal
                            HStack(spacing: 12) {
                                Image(systemName: "target")
                                    .font(.system(size: 15))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily word goal")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(prefs.dailyWordGoal == 0
                                         ? "No goal set"
                                         : "\(prefs.dailyWordGoal) words per day")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    ForEach([0, 100, 250, 500, 750, 1000], id: \.self) { goal in
                                        Button {
                                            prefs.dailyWordGoal = goal
                                        } label: {
                                            Text(goal == 0 ? "Off" : "\(goal)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(prefs.dailyWordGoal == goal ? .white : .primary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    prefs.dailyWordGoal == goal
                                                        ? Color.accentColor
                                                        : Color.secondary.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 6)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }

                    // ── About ────────────────────────────────────────────
                    SettingsSection(title: "About", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SynqApp").font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(appVersion).font(.system(size: 13)).foregroundColor(.secondary)
                            }
                            HStack {
                                Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                                Link("GitHub →", destination: URL(string: "https://github.com/aliarain/synqapp")!)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                }
                .padding(28)
            }
        }
        .frame(width: 520, height: 680)
        .onAppear { loadKey() }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var isTesting: Bool {
        if case .testing = keyStatus { return true }
        return false
    }

    @ViewBuilder
    private var keyStatusLabel: some View {
        switch keyStatus {
        case .none:
            EmptyView()
        case .saved:
            Label("Removed", systemImage: "trash").font(.system(size: 12)).foregroundColor(.secondary)
        case .testing:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Testing…") }
                .font(.system(size: 12))
        case .valid:
            Label("Saved · key works", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundColor(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.system(size: 12)).foregroundColor(.red)
                .lineLimit(2)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where SynqApp keeps your entries. Your existing notes will be moved there."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        moveNotes { try FileService.shared.changeFolder(to: url) }
    }

    private func moveNotes(_ change: () throws -> Void) {
        do {
            try change()
            storageError = nil
        } catch {
            storageError = "Couldn't move your notes: \(error.localizedDescription)"
        }
        notesPath = FileService.shared.notesDir.path
    }

    private func loadKey() {
        apiKey = KeychainService.shared.apiKey(for: provider) ?? ""
        keyStatus = nil
    }

    private func saveAndTestKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        KeychainService.shared.setAPIKey(key, for: provider)
        guard !key.isEmpty else { keyStatus = .saved; return }
        keyStatus = .testing
        Task {
            switch await AIClient().validateKey(provider: provider, key: key) {
            case .success: keyStatus = .valid
            case .failure(let error): keyStatus = .failure(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func infoBox(_ text: String, colorScheme: ColorScheme) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
}

// MARK: - Section wrapper

struct SettingsSection<Content: View>: View {
    let title: String
    let colorScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    private var cardBg: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cardBg)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 4, y: 2)
                )
        }
    }
}

// MARK: - Settings toggle row

struct SettingsToggleRow: View {
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
