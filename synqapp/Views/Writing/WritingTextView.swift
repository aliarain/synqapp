//  WritingTextView.swift
//  SynqApp — the writing surface: a native NSTextView with Flow / Focus / Typewriter / Zen behaviour

import SwiftUI
import AppKit

struct WritingTextView: NSViewRepresentable {

    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let mode: WritingMode
    let backspaceLocked: Bool
    var onEscape: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = WritingNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(self, textChanged: true)
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let textChanged = textView.string != text
        if textChanged {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        context.coordinator.parent = self
        context.coordinator.apply(self, textChanged: textChanged)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingTextView
        weak var textView: WritingNSTextView?
        private var appliedFont: NSFont?
        private var appliedMode: WritingMode?

        init(_ parent: WritingTextView) { self.parent = parent }

        func apply(_ config: WritingTextView, textChanged: Bool) {
            guard let tv = textView else { return }
            tv.placeholder = config.placeholder
            tv.backspaceLocked = config.backspaceLocked
            tv.onEscape = config.onEscape
            tv.columnWidth = config.mode == .zen ? 760 : 680
            tv.centersCaret = config.mode == .typewriter

            let style = NSMutableParagraphStyle()
            style.lineSpacing = config.font.pointSize * 0.35
            style.paragraphSpacing = config.font.pointSize * 0.4
            tv.typingAttributes = [.font: config.font, .paragraphStyle: style, .foregroundColor: NSColor.textColor]
            tv.defaultParagraphStyle = style
            tv.insertionPointColor = .controlAccentColor

            if textChanged || appliedFont != config.font || appliedMode != config.mode, let storage = tv.textStorage {
                let full = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.addAttributes([.font: config.font, .paragraphStyle: style, .foregroundColor: NSColor.textColor], range: full)
                storage.endEditing()
                appliedFont = config.font
                appliedMode = config.mode
                tv.updateInsets()
                tv.needsDisplay = true
            }
            styleFocus(tv)
            if config.mode == .typewriter {
                // Wait for the new insets to lay out before measuring where the caret is.
                DispatchQueue.main.async { tv.centerCaret(animated: false) }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? WritingNSTextView else { return }
            parent.text = tv.string
            styleFocus(tv)
            if parent.mode == .typewriter { tv.centerCaret(animated: true) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? WritingNSTextView else { return }
            styleFocus(tv)
            if parent.mode == .typewriter { tv.centerCaret(animated: true) }
        }

        /// Focus mode dims every paragraph except the one being written.
        private func styleFocus(_ tv: NSTextView) {
            guard let storage = tv.textStorage, let layout = tv.layoutManager, storage.length > 0 else { return }
            let full = NSRange(location: 0, length: storage.length)
            guard parent.mode == .focus else {
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
                return
            }
            let caret = min(tv.selectedRange().location, storage.length - 1)
            let active = (storage.string as NSString).paragraphRange(for: NSRange(location: max(0, caret), length: 0))
            layout.addTemporaryAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, forCharacterRange: full)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: active)
        }
    }
}

// MARK: - Text view

final class WritingNSTextView: NSTextView {

    var columnWidth: CGFloat = 680 { didSet { if columnWidth != oldValue { updateInsets() } } }
    var centersCaret = false { didSet { if centersCaret != oldValue { updateInsets() } } }
    var backspaceLocked = false
    var onEscape: (() -> Void)?
    var placeholder = "" { didSet { if string.isEmpty { needsDisplay = true } } }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    /// NSTextView scrolls the caret into view on its own; in Typewriter mode we centre it instead.
    override func scrollRangeToVisible(_ range: NSRange) {
        if centersCaret { centerCaret(animated: false) } else { super.scrollRangeToVisible(range) }
    }

    /// Centres a readable column in any window width; Typewriter mode adds half a screen above and below
    /// so the first and last lines can sit in the middle too.
    func updateInsets() {
        let visibleHeight = enclosingScrollView?.contentView.bounds.height ?? 600
        let horizontal = max(28, (bounds.width - columnWidth) / 2)
        let vertical = centersCaret ? max(48, visibleHeight / 2 - 20) : 48
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
    }

    func centerCaret(animated: Bool) {
        guard let layout = layoutManager, let container = textContainer,
              let clip = enclosingScrollView?.contentView else { return }
        layout.ensureLayout(for: container)
        let length = (string as NSString).length
        let location = min(selectedRange().location, length)
        var rect: NSRect
        if length == 0 || location == length, !layout.extraLineFragmentRect.isEmpty {
            rect = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(0, min(location, length - 1)))
            rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let target = rect.midY + textContainerOrigin.y - clip.bounds.height / 2
        let maxY = max(0, frame.height - clip.bounds.height)
        let origin = NSPoint(x: 0, y: min(max(0, target), maxY))
        guard abs(origin.y - clip.bounds.origin.y) > 1 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        var attributes = typingAttributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }

    // MARK: Backspace lock

    private func allowDeletion() -> Bool {
        if backspaceLocked { NSSound.beep() }
        return !backspaceLocked
    }

    override func deleteBackward(_ sender: Any?) { if allowDeletion() { super.deleteBackward(sender) } }
    override func deleteWordBackward(_ sender: Any?) { if allowDeletion() { super.deleteWordBackward(sender) } }
    override func deleteToBeginningOfLine(_ sender: Any?) { if allowDeletion() { super.deleteToBeginningOfLine(sender) } }
    override func deleteForward(_ sender: Any?) { if allowDeletion() { super.deleteForward(sender) } }
    override func deleteWordForward(_ sender: Any?) { if allowDeletion() { super.deleteWordForward(sender) } }
    override func cut(_ sender: Any?) { if allowDeletion() { super.cut(sender) } }
}
