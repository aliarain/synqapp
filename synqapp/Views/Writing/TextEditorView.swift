
//  TextEditorView.swift
//  SynqApp — writing surface with Flow / Focus / Typewriter / Zen modes

import SwiftUI
import AppKit

struct TextEditorView: View {

    @Binding var text: String
    let placeholder: String
    let font: String
    let fontSize: CGFloat
    let backspaceLocked: Bool
    let colorScheme: ColorScheme
    let writingMode: WritingMode

    // Typewriter scroll offset
    @State private var typewriterOffset: CGFloat = 0
    @State private var viewHeight: CGFloat = 600

    // Focus mode — track which paragraph is active
    @State private var activeParagraphRange: NSRange? = nil

    private var editorFont: Font { .custom(font, size: fontSize) }
    private var lineSpacing: CGFloat { fontSize * 0.3 }

    // MARK: - Theme colors

    var bgColor: Color {
        switch colorScheme {
        case .dark:  return Color(red: 0.08, green: 0.08, blue: 0.08)
        default:     return Color(red: 0.992, green: 0.992, blue: 0.992)
        }
    }

    private var textColor: Color {
        colorScheme == .dark
            ? Color(red: 0.9, green: 0.9, blue: 0.9)
            : Color(red: 0.165, green: 0.165, blue: 0.165)
    }

    private var dimmedTextColor: Color {
        colorScheme == .dark
            ? Color(white: 0.35)
            : Color(white: 0.75)
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.871, blue: 0.408)
            : Color(red: 0.078, green: 0.502, blue: 0.969)
    }

    private var placeholderColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.5) : Color.gray.opacity(0.4)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                bgColor.ignoresSafeArea()

                switch writingMode {
                case .flow:
                    flowEditor(geo: geo)
                case .focus:
                    focusEditor(geo: geo)
                case .typewriter:
                    typewriterEditor(geo: geo)
                case .zen:
                    zenEditor(geo: geo)
                }
            }
            .onAppear { viewHeight = geo.size.height }
            .onChange(of: geo.size.height) { viewHeight = $1 }
        }
        .background(bgColor)
        .animation(.easeInOut(duration: 0.3), value: writingMode)
        .animation(.easeInOut(duration: 0.25), value: colorScheme)
    }

    // MARK: - Flow (default)

    @ViewBuilder
    private func flowEditor(geo: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                placeholderOverlay()
                baseEditor()
                    .frame(minHeight: geo.size.height)
            }
            .frame(maxWidth: 650)
            .padding(.bottom, geo.size.height / 4)
        }
        .frame(maxWidth: .infinity)
        .background(bgColor)
    }

    // MARK: - Focus (dim surrounding paragraphs)

    @ViewBuilder
    private func focusEditor(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    placeholderOverlay()
                    FocusModeEditor(
                        text: $text,
                        font: font,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        textColor: textColor,
                        dimmedColor: dimmedTextColor,
                        accentColor: accentColor,
                        colorScheme: colorScheme
                    )
                    .frame(minHeight: geo.size.height)
                }
                .frame(maxWidth: 650)
                .padding(.bottom, geo.size.height / 4)
            }
            .frame(maxWidth: .infinity)
            .background(bgColor)

            // Focus mode label
            focusModeLabel("Focus Mode — active paragraph highlighted")
        }
    }

    // MARK: - Typewriter (cursor stays centered)

    @ViewBuilder
    private func typewriterEditor(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    placeholderOverlay()
                        .padding(.top, geo.size.height / 2 - fontSize)
                    baseEditor()
                        .padding(.top, geo.size.height / 2 - fontSize)
                        .frame(minHeight: geo.size.height)
                }
                .frame(maxWidth: 650)
                .padding(.bottom, geo.size.height / 2)
            }
            .frame(maxWidth: .infinity)
            .background(bgColor)

            focusModeLabel("Typewriter Mode")
        }
    }

    // MARK: - Zen (no chrome, centered, wider column)

    @ViewBuilder
    private func zenEditor(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            bgColor.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    placeholderOverlay()
                    baseEditor()
                        .frame(minHeight: geo.size.height)
                }
                .frame(maxWidth: 720)  // slightly wider in zen
                .padding(.bottom, geo.size.height / 4)
            }
            .frame(maxWidth: .infinity)
            .background(bgColor)

            // Subtle zen indicator top-center
            VStack {
                HStack {
                    Spacer()
                    Text("ZEN")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1))
                        .tracking(3)
                        .padding(.top, 14)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    // MARK: - Shared components

    @ViewBuilder
    private func baseEditor() -> some View {
        TextEditor(text: $text)
            .font(editorFont)
            .foregroundColor(textColor)
            .lineSpacing(lineSpacing)
            .tint(accentColor)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)          // hide TextEditor's own native scrollbar
            .background(Color.clear)
            .padding(.leading, 5)
            .padding(.top, 40)
            .id("\(font)-\(fontSize)-\(colorScheme)-\(writingMode)")
    }

    @ViewBuilder
    private func placeholderOverlay() -> some View {
        if text.isEmpty {
            Text(placeholder)
                .font(editorFont)
                .foregroundColor(placeholderColor)
                .lineSpacing(lineSpacing)
                .padding(.leading, 5)
                .padding(.top, 40)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func focusModeLabel(_ label: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark
                                     ? Color.white.opacity(0.15)
                                     : Color.black.opacity(0.12))
                    .padding(.bottom, 80)
                    .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Focus mode editor (NSViewRepresentable for paragraph dimming)

struct FocusModeEditor: NSViewRepresentable {

    @Binding var text: String
    let font: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let textColor: NSColor
    let dimmedColor: NSColor
    let accentColor: NSColor
    let colorScheme: ColorScheme

    init(
        text: Binding<String>,
        font: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        textColor: Color,
        dimmedColor: Color,
        accentColor: Color,
        colorScheme: ColorScheme
    ) {
        _text = text
        self.font = font
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.textColor = NSColor(textColor)
        self.dimmedColor = NSColor(dimmedColor)
        self.accentColor = NSColor(accentColor)
        self.colorScheme = colorScheme
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 5, height: 40)
        textView.insertionPointColor = accentColor
        textView.typingAttributes = typingAttributes()

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(sel)
        }

        textView.typingAttributes = typingAttributes()
        textView.insertionPointColor = accentColor
        context.coordinator.applyFocusStyling(textView: textView)
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        let nsFont = NSFont(name: font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return [
            .font: nsFont,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusModeEditor
        weak var textView: NSTextView?

        init(_ parent: FocusModeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            applyFocusStyling(textView: tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            applyFocusStyling(textView: tv)
        }

        func applyFocusStyling(textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            // Find active paragraph range
            let cursorPos = textView.selectedRange().location
            let safePos = min(cursorPos, max(0, storage.length - 1))
            let activeParagraph = (storage.string as NSString).paragraphRange(for: NSRange(location: safePos, length: 0))

            // Dim everything
            storage.addAttribute(.foregroundColor, value: parent.dimmedColor, range: fullRange)

            // Highlight active paragraph
            if activeParagraph.length > 0 {
                storage.addAttribute(.foregroundColor, value: parent.textColor, range: activeParagraph)
            }
        }
    }
}

// MARK: - Mode picker popover

struct WritingModePicker: View {
    @Binding var mode: WritingMode
    let colorScheme: ColorScheme
    @Binding var isPresented: Bool

    private var bg: Color {
        colorScheme == .dark ? Color(white: 0.1) : Color.white
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WritingMode.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: m.icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                            .foregroundColor(mode == m ? .accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(m.label)
                                    .font(.system(size: 13, weight: mode == m ? .semibold : .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(m.keyboardShortcut)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text(m.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if mode == m {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(mode == m
                             ? Color.accentColor.opacity(0.08)
                             : Color.clear)
                .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                if m != WritingMode.allCases.last {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 280)
        .background(bg, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
