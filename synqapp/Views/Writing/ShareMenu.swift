//  ShareMenu.swift
//  SynqApp — toolbar Share menu: hand the entry to ChatGPT or Claude, or export it

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SynqCore

struct ShareMenu: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        Menu {
            Section("Talk it through in") {
                Button("ChatGPT") { ChatHandoff.open(.chatGPT, text: vm.chatSourceText, vm: vm) }
                Button("Claude") { ChatHandoff.open(.claude, text: vm.chatSourceText, vm: vm) }
                Button("Copy Prompt") { ChatHandoff.copy(.chatGPT, text: vm.chatSourceText); vm.showInfo("Prompt copied") }
            }
            if let entry = vm.activeEntry {
                Section("Export") {
                    Button("PDF…") { EntryExporter.exportPDF(entry, vm: vm) }
                    Button("Markdown…") { EntryExporter.exportMarkdown(entry, vm: vm) }
                    Button("Plain Text…") { EntryExporter.exportPlainText(entry, vm: vm) }
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .help("Share or export this entry")
        .disabled(vm.chatSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

enum ChatHandoff {
    enum Target { case chatGPT, claude }

    static let chatGPT = """
below is my journal entry. wyt? talk through it with me like a friend. \
don't therapize me and give me a whole breakdown, don't repeat my thoughts with headings. \
really take all of this, and tell me back stuff truly as if you're an old homie.

Keep it casual, help me make new connections i don't see, comfort, validate, challenge, all of it. \
don't be afraid to say a lot.

do not just go through every single thing i say and repeat it back. \
process everything, make connections i don't see, and deliver it back as a story.

start by saying: "hey, thanks for showing me this. my thoughts:"

my entry:
"""

    static let claude = """
Take a look at my journal entry below. Respond with deep insight that feels personal, not clinical. \
Imagine you're a mentor who truly gets both my background and my psychological patterns. \
Uncover the deeper meaning behind my scattered thoughts.

Keep it casual, help me make new connections i don't see, comfort, validate, challenge, all of it.

Be willing to be profound without sounding like therapy. \
See the patterns I can't see and articulate them so it feels like an epiphany.

Start with: "hey, thanks for showing me this. my thoughts:"

Here's my journal entry:
"""

    private static func prompt(_ target: Target, text: String) -> String {
        (target == .chatGPT ? chatGPT : claude) + "\n\n" + text
    }

    /// `.urlQueryAllowed` leaves `&`, `=` and `+` unescaped, which cut prompts short at the first ampersand.
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func open(_ target: Target, text: String, vm: AppViewModel) {
        let full = prompt(target, text: text)
        let base = target == .chatGPT ? "https://chatgpt.com/?q=" : "https://claude.ai/new?q="
        // Very long prompts don't survive a URL; copy them and open a blank chat instead.
        if full.count > 6000 || full.addingPercentEncoding(withAllowedCharacters: unreserved) == nil {
            copy(target, text: text)
            NSWorkspace.shared.open(URL(string: target == .chatGPT ? "https://chatgpt.com/" : "https://claude.ai/new")!)
            vm.showInfo("Your entry is long, so the prompt was copied. Paste it into the chat.")
            return
        }
        if let encoded = full.addingPercentEncoding(withAllowedCharacters: unreserved), let url = URL(string: base + encoded) {
            NSWorkspace.shared.open(url)
        }
    }

    static func copy(_ target: Target, text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt(target, text: text), forType: .string)
    }
}

enum EntryExporter {
    private static func save(_ entry: JournalEntry, ext: String, type: UTType, vm: AppViewModel, write: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "\(entry.preview.replacingOccurrences(of: "/", with: "-")).\(ext)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(url)
                vm.showInfo("Exported \(url.lastPathComponent)")
            } catch {
                vm.showError("Export failed: \(error.localizedDescription)")
            }
        }
    }

    static func exportPDF(_ entry: JournalEntry, vm: AppViewModel) {
        save(entry, ext: "pdf", type: .pdf, vm: vm) { url in
            try PDFExportService.export(entry: entry, to: url, font: vm.prefs.editorFont(size: 12))
        }
    }

    static func exportMarkdown(_ entry: JournalEntry, vm: AppViewModel) {
        save(entry, ext: "md", type: UTType(filenameExtension: "md") ?? .plainText, vm: vm) { url in
            try FileService.shared.exportAsMarkdown(entry, to: url)
        }
    }

    static func exportPlainText(_ entry: JournalEntry, vm: AppViewModel) {
        save(entry, ext: "txt", type: .plainText, vm: vm) { url in
            try FileService.shared.exportAsPlainText(entry, to: url)
        }
    }

    static func exportEverything(vm: AppViewModel) {
        vm.saveCurrentEntry()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "SynqApp Journal.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FileService.shared.exportAllAsZip(to: url)
                vm.showInfo("Exported \(url.lastPathComponent)")
            } catch {
                vm.showError("Export failed: \(error.localizedDescription)")
            }
        }
    }
}
