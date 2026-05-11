
//  SearchView.swift
//  SynqApp — full-text search overlay (⌘F)

import SwiftUI

struct SearchView: View {

    @Binding var isPresented: Bool
    let entries: [JournalEntry]
    let colorScheme: ColorScheme
    var onSelect: (JournalEntry) -> Void

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @FocusState private var fieldFocused: Bool

    private var bg: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.992, green: 0.992, blue: 0.992)
    }

    private var cardBg: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Search panel
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))

                    TextField("Search all entries…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($fieldFocused)
                        .onSubmit { /* first result already shown */ }

                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { dismiss() } label: {
                        Text("ESC")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Results
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyState
                } else if results.isEmpty {
                    noResults
                } else {
                    resultsList
                }
            }
            .frame(width: 560)
            .frame(maxHeight: 480)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            .padding(.top, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            fieldFocused = true
        }
        .onChange(of: query) { q in
            results = SearchService.shared.search(query: q, in: entries)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Type to search across all your entries")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(height: 80)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("No entries found for "\(query)"")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
    }

    private var resultsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    SearchResultRow(
                        result: result,
                        query: query,
                        colorScheme: colorScheme
                    ) {
                        onSelect(result.entry)
                        dismiss()
                    }
                    if result.id != results.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) { isPresented = false }
    }
}

// MARK: - Result row

struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var hovering = false

    private var hoverBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.entry.preview)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(result.entry.displayDate)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if result.matchCount > 1 {
                            Text("\(result.matchCount)×")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    HighlightedText(text: result.matchSnippet, highlight: query)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hovering ? hoverBg : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            h ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }
}

// MARK: - Highlighted text

struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        let lower = text.lowercased()
        let q = highlight.lowercased()

        if q.isEmpty || !lower.contains(q) {
            return Text(text)
        }

        var result = Text("")
        var remaining = text[text.startIndex...]

        while let range = remaining.range(of: q, options: .caseInsensitive) {
            let before = String(remaining[remaining.startIndex..<range.lowerBound])
            let match = String(remaining[range])
            result = result + Text(before) + Text(match).foregroundColor(.accentColor).bold()
            remaining = remaining[range.upperBound...]
        }
        result = result + Text(String(remaining))
        return result
    }
}
