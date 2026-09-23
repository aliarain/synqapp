
//  SidebarView.swift
//  SynqApp — notes history sidebar with pinned entries, export menu

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SynqCore

struct SidebarView: View {

    @ObservedObject var vm: AppViewModel
    let colorScheme: ColorScheme

    private var pinned: [JournalEntry] { vm.entries.filter { $0.isPinned } }
    private var unpinned: [JournalEntry] { vm.entries.filter { !$0.isPinned } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("\(vm.entries.count)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Button { vm.openFolder() } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")

                // Export all as ZIP
                Button { exportAllZip() } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export all entries as ZIP")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Pinned section
                    if !pinned.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(pinned) { entry in
                            rowView(entry)
                            Divider()
                        }
                    }

                    // All entries
                    if !pinned.isEmpty && !unpinned.isEmpty {
                        sectionHeader("Entries")
                    }
                    ForEach(unpinned) { entry in
                        rowView(entry)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func rowView(_ entry: JournalEntry) -> some View {
        SidebarRowView(
            entry: entry,
            isSelected: vm.activeEntry?.id == entry.id,
            colorScheme: colorScheme,
            onSelect: { vm.open(entry) },
            onDelete: { vm.delete(entry) },
            onPin: { vm.togglePin(entry) },
            onExportPDF: { exportPDF(entry: entry) },
            onExportMD: { exportMD(entry: entry) },
            onExportTXT: { exportTXT(entry: entry) }
        )
    }

    // MARK: - Export actions

    private func exportPDF(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(entry.preview).pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            PDFExportService.export(entry: entry, to: url,
                                   fontName: vm.prefs.selectedFont,
                                   fontSize: vm.prefs.fontSize)
        }
    }

    private func exportMD(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(entry.preview).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? FileService.shared.exportAsMarkdown(entry, to: url)
        }
    }

    private func exportTXT(entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(entry.preview).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? FileService.shared.exportAsPlainText(entry, to: url)
        }
    }

    private func exportAllZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]
        panel.nameFieldStringValue = "SynqApp-Export.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FileService.shared.exportAllAsZip(entries: vm.entries, to: url)
            } catch {
                vm.showError("Export failed: \(error.localizedDescription)")
            }
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
    let onPin: () -> Void
    let onExportPDF: () -> Void
    let onExportMD: () -> Void
    let onExportTXT: () -> Void

    @State private var hovering = false
    @State private var showExportMenu = false

    private var selectionBg: Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.871, blue: 0.408).opacity(0.7)
                : Color(red: 0.545, green: 0.761, blue: 1.0)
        }
        if hovering {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
        }
        return Color.clear
    }

    private var titleColor: Color {
        isSelected && colorScheme == .dark ? Color.black : .primary
    }

    private var dateColor: Color {
        isSelected && colorScheme == .dark ? Color.black.opacity(0.7) : .secondary
    }

    var body: some View {
        HStack {
            // Pin indicator
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(colorScheme == .dark ? .black.opacity(0.5) : .secondary)
                    .rotationEffect(.degrees(45))
            }

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
                HStack(spacing: 6) {
                    // Pin / unpin
                    Button { onPin() } label: {
                        Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(entry.isPinned ? "Unpin" : "Pin to top")
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                    // Export menu
                    Button { showExportMenu = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Export")
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                    .popover(isPresented: $showExportMenu,
                             attachmentAnchor: .point(.center),
                             arrowEdge: .trailing) {
                        ExportMenuView(
                            onPDF: { showExportMenu = false; onExportPDF() },
                            onMD:  { showExportMenu = false; onExportMD() },
                            onTXT: { showExportMenu = false; onExportTXT() }
                        )
                    }

                    // Delete
                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
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
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { hovering = h } }
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
