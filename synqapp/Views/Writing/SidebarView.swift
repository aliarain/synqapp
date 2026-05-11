
//  SidebarView.swift
//  Spill — notes history sidebar

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {

    @ObservedObject var vm: AppViewModel
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("\(vm.entries.count) notes")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Button {
                    vm.openFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Entry list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.entries) { entry in
                        SidebarRowView(
                            entry: entry,
                            isSelected: vm.activeEntry?.id == entry.id,
                            colorScheme: colorScheme,
                            onSelect: { vm.open(entry) },
                            onDelete: { vm.delete(entry) },
                            onExport: { exportPDF(entry: entry) }
                        )
                        Divider()
                    }
                }
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func exportPDF(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let title = entry.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? "Note"
        panel.nameFieldStringValue = "\(title).pdf"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            PDFExportService.export(entry: entry, to: url,
                                   fontName: vm.prefs.selectedFont,
                                   fontSize: vm.prefs.fontSize)
        }
    }
}

// MARK: - Row

struct SidebarRowView: View {

    let entry: JournalEntry
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    @State private var hovering = false

    private var selectionBg: Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.871, blue: 0.408).opacity(0.7)
                : Color(red: 0.545, green: 0.761, blue: 1.0)
        }
        if hovering {
            return colorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color.black.opacity(0.05)
        }
        return Color.clear
    }

    private var titleColor: Color {
        if isSelected && colorScheme == .dark { return Color.black }
        return .primary
    }

    private var dateColor: Color {
        if isSelected && colorScheme == .dark { return Color.black.opacity(0.7) }
        return .secondary
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Text(entry.displayDate)
                    .font(.system(size: 13))
                    .foregroundColor(dateColor)
            }
            Spacer()

            if hovering {
                HStack(spacing: 8) {
                    // Export
                    Button { onExport() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Export as PDF")
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                    // Delete
                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete entry")
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selectionBg)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) { hovering = h }
        }
    }
}
