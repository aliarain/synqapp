
//  PreferencesService.swift
//  Spill — persisted user preferences via AppStorage

import SwiftUI
import Combine

final class PreferencesService: ObservableObject {

    // Theme
    @AppStorage("colorScheme") var colorSchemeRaw: String = "system" {
        willSet { objectWillChange.send() }
    }

    var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    func toggleTheme() {
        switch colorSchemeRaw {
        case "light": colorSchemeRaw = "dark"
        default:      colorSchemeRaw = "light"
        }
    }

    // Font
    static let fontSizes: [CGFloat] = [16, 18, 20, 22, 24, 26]
    static let systemFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
    }()

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

    func setRandomFont() {
        if let random = Self.systemFonts.randomElement() {
            selectedFont = random
        }
    }

    // Last active entry
    @AppStorage("lastEntryFilename") var lastEntryFilename: String = ""

    // Backspace lock
    @AppStorage("backspaceLocked") var backspaceLocked: Bool = false {
        willSet { objectWillChange.send() }
    }
}
