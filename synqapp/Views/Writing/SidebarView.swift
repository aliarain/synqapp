
//  SidebarView.swift
//  SynqApp — notes history sidebar with pinned entries, export menu

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SynqCore

struct SidebarView: View {

    @ObservedObject var vm: AppViewModel
    let colorScheme: ColorScheme

    @State private var pendingDelete: JournalEntry?
    @State private var query = ""
    @State private var selectedTags: Set<String> = []

    private var visibleEntries: [JournalEntry] { Timeline.filter(vm.entries, tags: selectedTags) }
    private var searchResults: [SearchResult] { Search.run(query: query, in: visibleEntries) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                    if !isSearching {
                        InsightsCard(insights: Insights.compute(entries: vm.entries), colorScheme: colorScheme)
                            .padding(.bottom, 4)
                        if vm.prefs.showTags { tagChips }
                    }

                    if isSearching {
                        sectionHeader(searchResults.isEmpty ? "No matches" : "\(searchResults.count) matching")
                        ForEach(searchResults) { result in
                            card(result.entry, snippet: result.matchSnippet)
                        }
                    } else {
                        ForEach(Timeline.sections(for: visibleEntries)) { section in
                            Section {
                                ForEach(section.entries) { card($0, snippet: nil) }
                            } header: {
                                sectionHeader(section.title)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Divider()
            storageBar
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .confirmationDialog(
            "Move “\(pendingDelete?.preview ?? "")” to the Trash?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Move to Trash", role: .destructive) { vm.delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can restore it from the Trash in Finder.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Text("Journal")
                .font(.system(size: 22, weight: .bold))
            Spacer()
            iconButton("square.and.pencil", help: "New entry") { vm.newEntry() }
            iconButton("arrow.down.circle", help: "Export everything (notes, videos, transcripts) as a ZIP") { exportAllZip() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 12))
            TextField("Search entries and transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var tagChips: some View {
        let tags = Stats.allTags(in: vm.entries)
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(20), id: \.self) { tag in
                        let on = selectedTags.contains(tag)
                        Button {
                            if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                        } label: {
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundColor(on ? .white : .primary)
                                .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .padding(.horizontal, 4)
            .background(.regularMaterial)
    }

    private func card(_ entry: JournalEntry, snippet: String?) -> some View {
        EntryCard(
            entry: entry,
            snippet: snippet,
            isSelected: vm.activeEntry?.id == entry.id,
            colorScheme: colorScheme,
            onSelect: { vm.open(entry) },
            onDelete: { pendingDelete = entry },
            onPin: { vm.togglePin(entry) },
            onExportPDF: { exportPDF(entry: entry) },
            onExportMD: { exportMD(entry: entry) },
            onExportTXT: { exportTXT(entry: entry) }
        )
    }

    private var storageBar: some View {
        Button { vm.openFolder() } label: {
            HStack(spacing: 8) {
                Image(systemName: FileService.shared.notesDir.path.contains("Mobile Documents") ? "icloud" : "folder")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(FileService.shared.isUsingDefaultFolder ? "On this Mac" : FileService.shared.notesDir.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("\(vm.entries.count) \(vm.entries.count == 1 ? "entry" : "entries") · Markdown files")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(FileService.shared.notesDir.path)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Export actions

    private func exportPDF(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(entry.preview).pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            run("PDF export") {
                try PDFExportService.export(entry: entry, to: url,
                                            fontName: vm.prefs.selectedFont,
                                            fontSize: vm.prefs.fontSize)
            }
        }
    }

    private func exportMD(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(entry.preview).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            run("Export") { try FileService.shared.exportAsMarkdown(entry, to: url) }
        }
    }

    private func exportTXT(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(entry.preview).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            run("Export") { try FileService.shared.exportAsPlainText(entry, to: url) }
        }
    }

    private func run(_ what: String, _ action: () throws -> Void) {
        do {
            try action()
            vm.showInfo("\(what) saved")
        } catch {
            vm.showError("\(what) failed: \(error.localizedDescription)")
        }
    }

    private func exportAllZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]
        panel.nameFieldStringValue = "SynqApp-Export.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            run("Export") { try FileService.shared.exportAllAsZip(to: url) }
        }
    }
}

// MARK: - Insights

struct InsightsCard: View {
    let insights: Insights
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insights").font(.system(size: 13, weight: .semibold))
                Spacer()
                if insights.streak > 0 {
                    Text("🔥 \(insights.streak)-day streak")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                stat(insights.entriesThisYear, "entries")
                stat(insights.wordsThisYear, "words")
                stat(insights.daysJournaledThisYear, "days")
            }

            weekBars
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.8))
        )
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("\(label) this year")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekBars: some View {
        let peak = max(1, insights.lastSevenDays.map(\.words).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(insights.lastSevenDays.enumerated()), id: \.offset) { index, day in
                let isToday = index == insights.lastSevenDays.count - 1
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.words > 0 ? (isToday ? Color.accentColor : Color.accentColor.opacity(0.45)) : Color.primary.opacity(0.08))
                        .frame(height: max(4, 34 * CGFloat(day.words) / CGFloat(peak)))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.words) words on \(day.date.formatted(.dateTime.weekday(.wide)))")
            }
        }
        .frame(height: 50, alignment: .bottom)
    }
}

// MARK: - Entry card

struct EntryCard: View {

    let entry: JournalEntry
    let snippet: String?
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onExportPDF: () -> Void
    let onExportMD: () -> Void
    let onExportTXT: () -> Void

    @State private var hovering = false
    @State private var showExportMenu = false

    private var bodyPreview: String {
        if let snippet { return snippet }
        let lines = entry.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "---" }
        return lines.dropFirst().joined(separator: " ")
            .replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.18) }
        if hovering { return Color.primary.opacity(0.06) }
        return colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.55)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if entry.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.orange)
                }
                Text(entry.preview)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovering { actions }
            }

            if !bodyPreview.isEmpty {
                Text(bodyPreview)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                if entry.entryType == .video {
                    Label("Video", systemImage: "video.fill").labelStyle(.titleAndIcon)
                } else {
                    let words = Stats.wordCount(entry.body)
                    if words > 0 { Text("· \(words) words") }
                }
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin to Top", action: onPin)
            Menu("Export") {
                Button("PDF…", action: onExportPDF)
                Button("Markdown…", action: onExportMD)
                Button("Plain Text…", action: onExportTXT)
            }
            Divider()
            Button("Move to Trash…", role: .destructive, action: onDelete)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onPin) {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
            }
            .help(entry.isPinned ? "Unpin" : "Pin to top")

            Button { showExportMenu = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export")
            .popover(isPresented: $showExportMenu, arrowEdge: .trailing) {
                ExportMenuView(
                    onPDF: { showExportMenu = false; onExportPDF() },
                    onMD:  { showExportMenu = false; onExportMD() },
                    onTXT: { showExportMenu = false; onExportTXT() }
                )
            }

            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .help("Move to Trash")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .buttonStyle(.plain)
    }
}

// MARK: - Export menu popover

struct ExportMenuView: View {
    let onPDF: () -> Void
    let onMD: () -> Void
    let onTXT: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            exportRow(icon: "doc.richtext", label: "PDF", action: onPDF)
            Divider()
            exportRow(icon: "doc.text", label: "Markdown (.md)", action: onMD)
            Divider()
            exportRow(icon: "doc.plaintext", label: "Plain Text (.txt)", action: onTXT)
        }
        .frame(width: 180)
    }

    @ViewBuilder
    private func exportRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.accentColor)
                Text(label).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}
