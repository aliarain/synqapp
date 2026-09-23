//  ReadingView.swift
//  SynqApp — read-only view of the entry with Markdown rendered

import SwiftUI

struct ReadingView: View {
    let text: String
    let font: NSFont

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    var body: some View {
        ScrollView {
            Text(rendered)
                .font(Font(font))
                .lineSpacing(font.pointSize * 0.35)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.vertical, 48)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
        }
    }
}
