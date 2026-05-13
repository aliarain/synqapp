
//  QuickCaptureView.swift
//  SynqApp — floating quick capture window (⌥Space from anywhere)

import SwiftUI

struct QuickCaptureView: View {

    @Binding var isPresented: Bool
    var onSave: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private let bg = Color(NSColor.windowBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "pencil.line")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                Text("Quick Capture")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌘↩ save  ·  ESC cancel")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Text area
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($focused)
                .frame(minHeight: 100, maxHeight: 200)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Footer
            HStack {
                Text(text.isEmpty ? "" : "\(wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Save to SynqApp") { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary.opacity(0.3)
                            : Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(bg)
        .onAppear { focused = true }
    }

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }

    private func dismiss() {
        text = ""
        isPresented = false
    }
}
