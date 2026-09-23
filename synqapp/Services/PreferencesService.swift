//  PreferencesService.swift
//  SynqApp — persisted user preferences

import SwiftUI
import Combine
import SynqCore

final class PreferencesService: ObservableObject {

    /// One instance for the whole app so every view sees changes immediately.
    static let shared = PreferencesService()
    private init() {}

    // MARK: - AI

    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.anthropic.rawValue {
        willSet { objectWillChange.send() }
    }

    var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .anthropic }
        set { aiProviderRaw = newValue.rawValue }
    }

    func aiModel(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: "aiModel.\(provider.rawValue)") ?? ""
        return stored.isEmpty ? provider.defaultModel : stored
    }

    func setAIModel(_ model: String, for provider: AIProvider) {
        objectWillChange.send()
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: "aiModel.\(provider.rawValue)")
    }

    /// Everything needed to call the selected provider, or nil when no key is saved.
    func aiRequest(system: String, turns: [ChatTurn]) -> AIRequest? {
        let provider = aiProvider
        guard let key = KeychainService.shared.apiKey(for: provider) else { return nil }
        return AIRequest(provider: provider, model: aiModel(for: provider), apiKey: key, system: system, turns: turns)
    }

    // MARK: - Theme

    @AppStorage("colorScheme") var colorSchemeRaw: String = "light" {
        willSet { objectWillChange.send() }
    }

    var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var isDark: Bool { colorSchemeRaw == "dark" }

    func toggleTheme() {
        colorSchemeRaw = isDark ? "light" : "dark"
    }

    func setTheme(_ scheme: ColorScheme) {
        colorSchemeRaw = scheme == .dark ? "dark" : "light"
    }

    // MARK: - Font

    static let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]

    @AppStorage("selectedFont") var selectedFont: String = "Arial" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("fontSize") var fontSizeIndex: Int = 0 {
        willSet { objectWillChange.send() }
    }

    var fontSize: CGFloat { Self.fontSizes[fontSizeIndex] }

    func cycleFontSize() {
        fontSizeIndex = (fontSizeIndex + 1) % Self.fontSizes.count
    }

    func setFont(_ name: String) {
        selectedFont = name
    }

    // MARK: - Writing mode

    @AppStorage("writingMode") var writingModeRaw: String = WritingMode.flow.rawValue {
        willSet { objectWillChange.send() }
    }

    var writingMode: WritingMode {
        get { WritingMode(rawValue: writingModeRaw) ?? .flow }
        set { writingModeRaw = newValue.rawValue }
    }

    func cycleWritingMode() {
        let all = WritingMode.allCases
        let current = all.firstIndex(of: writingMode) ?? 0
        writingMode = all[(current + 1) % all.count]
    }

    // MARK: - Word count & reading time

    @AppStorage("showWordCount") var showWordCount: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("showReadingTime") var showReadingTime: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Streak & daily goal

    @AppStorage("showStreak") var showStreak: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("dailyWordGoal") var dailyWordGoal: Int = 0 {
        willSet { objectWillChange.send() }
    }

    var hasDailyGoal: Bool { dailyWordGoal > 0 }

    // MARK: - Tags

    @AppStorage("showTags") var showTags: Bool = true {
        willSet { objectWillChange.send() }
    }

    // MARK: - Onboarding

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Misc

    @AppStorage("lastEntryFilename") var lastEntryFilename: String = ""

    @AppStorage("backspaceLocked") var backspaceLocked: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("lineWidth") private var lineWidthRaw: Double = 650 {
        willSet { objectWillChange.send() }
    }

    var lineWidth: CGFloat {
        get { CGFloat(lineWidthRaw) }
        set { lineWidthRaw = Double(newValue) }
    }
}
