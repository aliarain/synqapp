//  SettingsView.swift
//  SynqApp — the Settings window (⌘,)

import SwiftUI
import AppKit
import SynqCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            WritingSettings()
                .tabItem { Label("Writing", systemImage: "character.cursor.ibeam") }
            AISettings()
                .tabItem { Label("AI", systemImage: "sparkles") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var prefs = PreferencesService.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(get: { prefs.appearance }, set: { prefs.appearance = $0 })) {
                ForEach(PreferencesService.Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Section("Quick Capture") {
                LabeledContent("Global shortcut") {
                    Text("⌥ Space").foregroundStyle(.secondary)
                }
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Link("SynqApp on GitHub", destination: URL(string: "https://github.com/aliarain/synqapp")!)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }
}

// MARK: - Writing

private struct WritingSettings: View {
    @ObservedObject private var prefs = PreferencesService.shared

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $prefs.selectedFont) {
                    Text("New York").tag("Serif")
                    Text("San Francisco").tag("System")
                    Text("SF Mono").tag("Mono")
                    if !PreferencesService.builtInFonts.contains(prefs.selectedFont) {
                        Divider()
                        Text(prefs.selectedFont).tag(prefs.selectedFont)
                    }
                }
                LabeledContent("Other font") {
                    Button("Choose…") { FontPanel.show() }
                }
                LabeledContent("Size") {
                    Stepper("\(Int(prefs.fontSizeValue)) pt", value: $prefs.fontSizeValue, in: PreferencesService.sizeRange, step: 1)
                }
                Picker("Default mode", selection: Binding(get: { prefs.writingMode }, set: { prefs.writingMode = $0 })) {
                    ForEach(WritingMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Lock backspace (keep writing, fix it later)", isOn: $prefs.backspaceLocked)
            }

            Section("Status Bar") {
                Toggle("Word count", isOn: $prefs.showWordCount)
                Toggle("Reading time", isOn: $prefs.showReadingTime)
                Toggle("Writing streak", isOn: $prefs.showStreak)
                Picker("Daily word goal", selection: $prefs.dailyWordGoal) {
                    Text("Off").tag(0)
                    ForEach([100, 250, 500, 750, 1000], id: \.self) { Text("\($0) words").tag($0) }
                }
            }

            Section("Sidebar") {
                Toggle("Filter by #tags", isOn: $prefs.showTags)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}

/// Opens the standard macOS font panel and saves the family the user picks.
enum FontPanel {
    private final class Receiver: NSObject, NSFontChanging {
        func changeFont(_ sender: NSFontManager?) {
            guard let sender else { return }
            let font = sender.convert(PreferencesService.shared.editorFont())
            if let family = font.familyName { PreferencesService.shared.selectedFont = family }
            PreferencesService.shared.fontSizeValue = Double(font.pointSize)
        }
        func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { [.collection, .face, .size] }
    }
    private static let receiver = Receiver()

    static func show() {
        let manager = NSFontManager.shared
        manager.target = receiver
        manager.setSelectedFont(PreferencesService.shared.editorFont(), isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }
}

// MARK: - AI

private struct AISettings: View {
    @ObservedObject private var prefs = PreferencesService.shared
    @State private var apiKey = ""
    @State private var status: KeyStatus?

    enum KeyStatus: Equatable { case removed, testing, valid, failure(String) }

    private var provider: AIProvider { prefs.aiProvider }

    var body: some View {
        Form {
            Picker("Provider", selection: Binding(get: { prefs.aiProvider }, set: { prefs.aiProvider = $0; loadKey() })) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Section {
                SecureField("API key", text: $apiKey, prompt: Text(provider.keyPlaceholder))
                    .onSubmit(saveAndTest)
                HStack {
                    statusView
                    Spacer()
                    Link("Get a key", destination: provider.keyConsoleURL)
                    Button("Save", action: saveAndTest)
                        .disabled(status == .testing)
                }
            } header: {
                Text("\(provider.displayName) API Key")
            } footer: {
                Text("Stored in your Keychain. Entries are sent from this Mac straight to \(provider.displayName), and only when you use Reflect or a recap.")
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Model", selection: modelBinding) {
                    ForEach(provider.suggestedModels) { model in
                        Text(model.name).tag(model.id)
                    }
                    if !provider.suggestedModels.contains(where: { $0.id == modelBinding.wrappedValue }) {
                        Text(modelBinding.wrappedValue).tag(modelBinding.wrappedValue)
                    }
                }
                if let blurb = provider.suggestedModels.first(where: { $0.id == modelBinding.wrappedValue })?.blurb {
                    Text(blurb).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Model ID", text: modelBinding, prompt: Text(provider.defaultModel))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
        .onAppear(perform: loadKey)
    }

    private var modelBinding: Binding<String> {
        Binding(get: { prefs.aiModel(for: provider) }, set: { prefs.setAIModel($0, for: provider) })
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .none:
            if KeychainService.shared.hasKey(for: provider) {
                Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        case .removed:
            Label("Removed", systemImage: "trash").foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
        case .valid:
            Label("Key works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
        }
    }

    private func loadKey() {
        apiKey = KeychainService.shared.apiKey(for: provider) ?? ""
        status = nil
    }

    private func saveAndTest() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        KeychainService.shared.setAPIKey(key, for: provider)
        guard !key.isEmpty else { status = .removed; return }
        status = .testing
        Task {
            switch await AIClient().validateKey(provider: provider, key: key) {
            case .success: status = .valid
            case .failure(let error): status = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @State private var path = FileService.shared.notesDir.path
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes folder") {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                }
                HStack {
                    Button("Show in Finder") { FileService.shared.openInFinder() }
                    Spacer()
                    if !FileService.shared.isUsingDefaultFolder {
                        Button("Use Default") { change { try FileService.shared.resetToDefaultFolder() } }
                    }
                    Button("Change…", action: choose)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text("Every entry is a plain Markdown file. Choose a folder in iCloud Drive to keep your journal in sync across your Macs. Existing entries, videos and pins move with it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 260)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where SynqApp keeps your journal. Your existing entries will be moved there."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        change { try FileService.shared.changeFolder(to: url) }
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = "Couldn't move your entries: \(error.localizedDescription)"
        }
        path = FileService.shared.notesDir.path
    }
}
