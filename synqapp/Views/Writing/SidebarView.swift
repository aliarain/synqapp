//  SidebarView.swift
//  SynqApp — native sidebar: insights, entries grouped by month, search, tag filter

import SwiftUI
import AppKit
import SynqCore

struct SidebarView: View {

    @ObservedObject var vm: AppViewModel

    @State private var query = ""
    @State private var selectedTags: Set<String> = []
    @State private var pendingDelete: JournalEntry?

    private var visibleEntries: [JournalEntry] { Timeline.filter(vm.entries, tags: selectedTags) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var selection: Binding<UUID?> {
        Binding(
            get: { vm.activeEntry?.id },
            set: { id in
                if let id, let entry = vm.entries.first(where: { $0.id == id }), id != vm.activeEntry?.id {
                    vm.open(entry)
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            if isSearching {
                let results = Search.run(query: query, in: visibleEntries)
                Section(results.isEmpty ? "No Results" : "Results") {
                    ForEach(results) { result in
                        row(result.entry, snippet: result.matchSnippet)
                    }
                }
            } else {
                if selectedTags.isEmpty {
                    Section("Insights") {
                        InsightsView(insights: Insights.compute(entries: vm.entries))
                            .selectionDisabled()
                    }
                }
                ForEach(Timeline.sections(for: visibleEntries)) { section in
                    Section(section.title) {
                        ForEach(section.entries) { row($0, snippet: nil) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
        .safeAreaInset(edge: .bottom, spacing: 0) { storageFooter }
        .toolbar {
            ToolbarItemGroup {
                if vm.prefs.showTags { tagFilterMenu }
                Button(action: vm.newEntry) {
                    Label("New Entry", systemImage: "square.and.pencil")
                }
                .help("New entry (⌘N)")
            }
        }
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
        .onDeleteCommand {
            if let entry = vm.activeEntry { pendingDelete = entry }
        }
    }

    // MARK: - Rows

    private func row(_ entry: JournalEntry, snippet: String?) -> some View {
        EntryRow(entry: entry, snippet: snippet)
            .tag(entry.id)
            .contextMenu {
                Button(entry.isPinned ? "Unpin" : "Pin") { vm.togglePin(entry) }
                Menu("Export") {
                    Button("PDF…") { EntryExporter.exportPDF(entry, vm: vm) }
                    Button("Markdown…") { EntryExporter.exportMarkdown(entry, vm: vm) }
                    Button("Plain Text…") { EntryExporter.exportPlainText(entry, vm: vm) }
                }
                Divider()
                Button("Move to Trash…", role: .destructive) { pendingDelete = entry }
            }
            .swipeActions(edge: .leading) {
                Button { vm.togglePin(entry) } label: {
                    Label(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = entry } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private var tagFilterMenu: some View {
        let tags = Stats.allTags(in: vm.entries)
        return Menu {
            if tags.isEmpty {
                Text("Add #tags to entries to filter by them")
            } else {
                ForEach(tags.prefix(30), id: \.self) { tag in
                    Toggle("#\(tag)", isOn: Binding(
                        get: { selectedTags.contains(tag) },
                        set: { on in if on { selectedTags.insert(tag) } else { selectedTags.remove(tag) } }
                    ))
                }
                if !selectedTags.isEmpty {
                    Divider()
                    Button("Show All Entries") { selectedTags.removeAll() }
                }
            }
        } label: {
            Label("Filter", systemImage: selectedTags.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .help(selectedTags.isEmpty ? "Filter by tag" : "Filtering by " + selectedTags.sorted().map { "#\($0)" }.joined(separator: ", "))
    }

    private var storageFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: vm.openFolder) {
                HStack(spacing: 8) {
                    Image(systemName: FileService.shared.notesDir.path.contains("Mobile Documents") ? "icloud" : "internaldrive")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(FileService.shared.isUsingDefaultFolder ? "On My Mac" : FileService.shared.notesDir.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(vm.entries.count) \(vm.entries.count == 1 ? "entry" : "entries")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show notes folder in Finder\n\(FileService.shared.notesDir.path)")
        }
    }
}

// MARK: - Entry row

struct EntryRow: View {
    let entry: JournalEntry
    let snippet: String?

    private var detail: String {
        if let snippet { return snippet }
        let lines = entry.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "---" }
        return lines.dropFirst().joined(separator: " ")
            .replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if entry.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                }
                Text(entry.preview.replacingOccurrences(of: "🎥 ", with: ""))
                    .font(.headline)
                    .lineLimit(1)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                if entry.entryType == .video {
                    Image(systemName: "video.fill")
                }
                Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Insights

struct InsightsView: View {
    let insights: Insights

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if insights.streak > 0 {
                Label("\(insights.streak)-day streak", systemImage: "flame.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline) {
                stat(insights.entriesThisYear, "Entries")
                stat(insights.wordsThisYear, "Words")
                stat(insights.daysJournaledThisYear, "Days")
            }
            weekBars
            Text("This year · last 7 days")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekBars: some View {
        let peak = max(1, insights.lastSevenDays.map(\.words).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(insights.lastSevenDays.enumerated()), id: \.offset) { index, day in
                let isToday = index == insights.lastSevenDays.count - 1
                VStack(spacing: 3) {
                    Capsule()
                        .fill(day.words > 0 ? Color.accentColor.opacity(isToday ? 1 : 0.55) : Color.secondary.opacity(0.2))
                        .frame(height: max(4, 28 * CGFloat(day.words) / CGFloat(peak)))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.words) words on \(day.date.formatted(.dateTime.weekday(.wide)))")
            }
        }
        .frame(height: 42, alignment: .bottom)
    }
}
