
//  SettingsView.swift
//  SynqApp — API key configuration, model selection, voice backend

import SwiftUI

struct SettingsView: View {

    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state (loaded from Keychain on appear)

    @State private var openAIKey: String = ""
    @State private var livekitURL: String = ""
    @State private var livekitTokenURL: String = ""
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "aiModel") ?? "gpt-4o-mini"

    @State private var showOpenAIKey = false
    @State private var isSaved = false
    @State private var isTestingKey = false
    @State private var keyTestResult: KeyTestResult? = nil

    enum KeyTestResult {
        case success, failure(String)
    }

    private let models = ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"]

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

                    // ── OpenAI ──────────────────────────────────────────
                    SettingsSection(title: "AI · OpenAI", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 14) {

                            // API Key
                            VStack(alignment: .leading, spacing: 6) {
                                Label("API Key", systemImage: "key.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    Group {
                                        if showOpenAIKey {
                                            TextField("sk-...", text: $openAIKey)
                                        } else {
                                            SecureField("sk-...", text: $openAIKey)
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

                                    Button {
                                        showOpenAIKey.toggle()
                                    } label: {
                                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                HStack(spacing: 8) {
                                    // Test key
                                    Button {
                                        testOpenAIKey()
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isTestingKey {
                                                ProgressView().controlSize(.mini)
                                            }
                                            Text(isTestingKey ? "Testing…" : "Test Key")
                                        }
                                        .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor)
                                    .disabled(openAIKey.isEmpty || isTestingKey)

                                    if let result = keyTestResult {
                                        switch result {
                                        case .success:
                                            Label("Valid", systemImage: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.green)
                                        case .failure(let msg):
                                            Label(msg, systemImage: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }

                            Divider()

                            // Model picker
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Model", systemImage: "cpu")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("", selection: $selectedModel) {
                                    ForEach(models, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: selectedModel) { m in
                                    UserDefaults.standard.set(m, forKey: "aiModel")
                                }

                                Text(modelDescription(selectedModel))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            // Get key link
                            HStack {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                                Link("Get an OpenAI API key →",
                                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    // ── LiveKit Voice ────────────────────────────────────
                    SettingsSection(title: "Voice · LiveKit", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 14) {

                            infoBox(
                                "Voice Reflect uses LiveKit for real-time audio. You need a running token server — see the README for the one-command local setup.",
                                colorScheme: colorScheme
                            )

                            // LiveKit server URL
                            settingsField(
                                label: "LiveKit Server URL",
                                icon: "server.rack",
                                placeholder: "wss://your-livekit-server.com",
                                text: $livekitURL,
                                colorScheme: colorScheme
                            )

                            // Token endpoint
                            settingsField(
                                label: "Token Endpoint",
                                icon: "link",
                                placeholder: "http://localhost:8000/getToken",
                                text: $livekitTokenURL,
                                colorScheme: colorScheme
                            )

                            HStack {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                                Link("LiveKit Cloud (free tier) →",
                                     destination: URL(string: "https://cloud.livekit.io")!)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    // ── About ────────────────────────────────────────────
                    SettingsSection(title: "About", colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SynqApp").font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text("v1.0.0").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                            Text("Open source · MIT License")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            HStack {
                                Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                                Link("GitHub →", destination: URL(string: "https://github.com")!)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    // Save button
                    HStack {
                        Spacer()
                        Button(action: save) {
                            HStack(spacing: 6) {
                                if isSaved {
                                    Image(systemName: "checkmark")
                                }
                                Text(isSaved ? "Saved" : "Save Settings")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                isSaved ? Color.green : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
                .padding(28)
            }
        }
        .frame(width: 520, height: 680)
        .onAppear { loadFromKeychain() }
    }

    // MARK: - Helpers

    private func loadFromKeychain() {
        openAIKey = KeychainService.shared.openAIKey ?? ""
        livekitURL = KeychainService.shared.livekitURL ?? ""
        livekitTokenURL = KeychainService.shared.livekitTokenURL ?? ""
    }

    private func save() {
        if !openAIKey.isEmpty {
            KeychainService.shared.save(openAIKey, for: .openAIKey)
        } else {
            KeychainService.shared.delete(.openAIKey)
        }
        if !livekitURL.isEmpty {
            KeychainService.shared.save(livekitURL, for: .livekitURL)
        }
        if !livekitTokenURL.isEmpty {
            KeychainService.shared.save(livekitTokenURL, for: .livekitToken)
        }

        withAnimation { isSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isSaved = false }
        }
    }

    private func testOpenAIKey() {
        isTestingKey = true
        keyTestResult = nil

        // Minimal API call to validate the key
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isTestingKey = false
                if let http = response as? HTTPURLResponse {
                    keyTestResult = http.statusCode == 200
                        ? .success
                        : .failure(http.statusCode == 401 ? "Invalid key" : "HTTP \(http.statusCode)")
                } else {
                    keyTestResult = .failure(error?.localizedDescription ?? "No response")
                }
            }
        }.resume()
    }

    private func modelDescription(_ model: String) -> String {
        switch model {
        case "gpt-4o-mini":  return "Fast and cheap — great for daily journaling"
        case "gpt-4o":       return "Smarter, slower — better for deep reflection"
        case "gpt-4-turbo":  return "High quality, higher cost"
        case "gpt-3.5-turbo": return "Fastest, lowest cost"
        default:             return ""
        }
    }

    @ViewBuilder
    private func settingsField(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        colorScheme: ColorScheme
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                )
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
