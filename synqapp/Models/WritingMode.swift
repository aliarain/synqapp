
//  WritingMode.swift
//  SynqApp — focus modes for the writing surface

import SwiftUI

enum WritingMode: String, CaseIterable, Identifiable {
    case flow       = "flow"        // Default — full chrome
    case focus      = "focus"       // Dim everything except active paragraph
    case typewriter = "typewriter"  // Active line stays vertically centered
    case zen        = "zen"         // No chrome at all, pure text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flow:       return "Flow"
        case .focus:      return "Focus"
        case .typewriter: return "Typewriter"
        case .zen:        return "Zen"
        }
    }

    var icon: String {
        switch self {
        case .flow:       return "text.alignleft"
        case .focus:      return "scope"
        case .typewriter: return "arrow.up.and.down.text.horizontal"
        case .zen:        return "circle"
        }
    }

    var description: String {
        switch self {
        case .flow:       return "Normal writing with all controls visible"
        case .focus:      return "Dims surrounding text, highlights active paragraph"
        case .typewriter: return "Keeps your cursor line vertically centered"
        case .zen:        return "Hides everything — just you and the words"
        }
    }

    var keyboardShortcut: String {
        switch self {
        case .flow:       return "⌘1"
        case .focus:      return "⌘2"
        case .typewriter: return "⌘3"
        case .zen:        return "⌘4"
        }
    }
}
