
//  ReadingView.swift
//  SynqApp — clean reading mode, no editing chrome

import SwiftUI

struct ReadingView: View {

    let text: String
    let font: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    var onExit: () -> Void

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.992, green: 0.992, blue: 0.992)
    }

    private var textColor: Color {
        colorScheme == .dark
            ? Color(red: 0.9, green: 0.9, blue: 0.9)
            : Color(red: 0.165, green: 0.165, blue: 0.165)
    }

    private var lineSpacing: CGFloat { fontSize * 0.35 }

    // Parse basic markdown to AttributedString
    private var displayText: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            bgColor.ignoresSafeArea()

            // Reading content
            ScrollView(.vertical, showsIndicators: false) {
                Text(displayText)
                    .font(.custom(font, size: fontSize))
                    .foregroundColor(textColor)
                    .lineSpacing(lineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding(.top, 60)
                    .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity)

            // Exit button — top right, subtle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { onExit() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                    Text("Edit")
                        .font(.system(size: 13))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 20)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
            .help("Back to editing (⌘R)")
        }
        .transition(.opacity)
    }
}
