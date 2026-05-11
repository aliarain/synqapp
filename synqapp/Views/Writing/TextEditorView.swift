
//  TextEditorView.swift
//  Spill — the main writing surface

import SwiftUI

struct TextEditorView: View {

    @Binding var text: String
    let placeholder: String
    let font: String
    let fontSize: CGFloat
    let backspaceLocked: Bool
    let colorScheme: ColorScheme

    @State private var viewHeight: CGFloat = 600

    private var editorFont: Font {
        .custom(font, size: fontSize)
    }

    private var lineSpacing: CGFloat { fontSize * 0.3 }

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

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.871, blue: 0.408)
            : Color(red: 0.078, green: 0.502, blue: 0.969)
    }

    private var placeholderColor: Color {
        colorScheme == .dark
            ? Color.gray.opacity(0.6)
            : Color.gray.opacity(0.5)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                bgColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Placeholder
                        if text.isEmpty {
                            Text(placeholder)
                                .font(editorFont)
                                .foregroundColor(placeholderColor)
                                .lineSpacing(lineSpacing)
                                .padding(.leading, 5)
                                .padding(.top, 40)
                                .allowsHitTesting(false)
                        }

                        // Editor
                        TextEditor(text: $text)
                            .font(editorFont)
                            .foregroundColor(textColor)
                            .lineSpacing(lineSpacing)
                            .tint(accentColor)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.leading, 5)
                            .padding(.top, 40)
                            .frame(minHeight: geo.size.height)
                            .id("\(font)-\(fontSize)")
                    }
                    .frame(maxWidth: 650)
                    .padding(.bottom, geo.size.height / 4)
                }
                .frame(maxWidth: .infinity)
                .background(bgColor)
            }
            .onAppear { viewHeight = geo.size.height }
            .onChange(of: geo.size.height) { viewHeight = $1 }
            .background(bgColor)
        }
        .background(bgColor)
    }
}
