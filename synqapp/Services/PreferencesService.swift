//  PreferencesService.swift
//  SynqApp — persisted user preferences

import SwiftUI
import AppKit
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

    // MARK: - Appearance

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue {
        willSet { objectWillChange.send() }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    // MARK: - Font

    /// "System", "Serif" and "Mono" map to the system font designs; anything else is a font family name.
    static let builtInFonts = ["Serif", "System", "Mono"]
    static let sizeRange: ClosedRange<Double> = 13...32

    @AppStorage("editorFont") var selectedFont: String = "Serif" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("editorFontSize") var fontSizeValue: Double = 18 {
        willSet { objectWillChange.send() }
    }

    var fontSize: CGFloat { CGFloat(fontSizeValue) }

    func adjustFontSize(by delta: Double) {
        fontSizeValue = min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, fontSizeValue + delta))
    }

    func editorFont(size: CGFloat? = nil) -> NSFont {
        let size = size ?? fontSize
        let base = NSFont.systemFont(ofSize: size)
        switch selectedFont {
        case "System": return base
        case "Serif":  return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case "Mono":   return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default:       return NSFont(name: selectedFont, size: size) ?? base
        }
    }

    // MARK: - Focus timer

    @AppStorage("timerMinutes") var timerMinutes: Int = 15 {
        willSet { objectWillChange.send() }
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

}
