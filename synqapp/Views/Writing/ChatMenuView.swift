
//  ChatMenuView.swift
//  SynqApp — ChatGPT / Claude / Copy prompt popover

import SwiftUI
import AppKit

struct ChatMenuView: View {

    let sourceText: String
    let colorScheme: ColorScheme
    @Binding var isPresented: Bool

    @State private var didCopy = false

    private let minChars = 350

    private let gptPrompt = """
below is my journal entry. wyt? talk through it with me like a friend. \
don't therapize me and give me a whole breakdown, don't repeat my thoughts with headings. \
really take all of this, and tell me back stuff truly as if you're an old homie.

Keep it casual, help me make new connections i don't see, comfort, validate, challenge, all of it. \
don't be afraid to say a lot.

do not just go through every single thing i say and repeat it back. \
process everything, make connections i don't see, and deliver it back as a story.

start by saying: "hey, thanks for showing me this. my thoughts:"

my entry:
"""

    private let claudePrompt = """
Take a look at my journal entry below. Respond with deep insight that feels personal, not clinical. \
Imagine you're a mentor who truly gets both my background and my psychological patterns. \
Uncover the deeper meaning behind my scattered thoughts.

Keep it casual, help me make new connections i don't see, comfort, validate, challenge, all of it.

Be willing to be profound without sounding like therapy. \
See the patterns I can't see and articulate them so it feels like an epiphany.

Start with: "hey, thanks for showing me this. my thoughts:"

Here's my journal entry:
"""

    private var bgColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var fgColor: Color { .primary }

    /// `.urlQueryAllowed` leaves `&`, `=` and `+` unescaped, which cut prompts short at the first ampersand.
    private func encoded(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))
    }

    private var gptURL: URL? {
        let full = gptPrompt + "\n\n" + sourceText
        guard let encoded = encoded(full) else { return nil }
        return URL(string: "https://chat.openai.com/?prompt=" + encoded)
    }

    private var claudeURL: URL? {
        let full = claudePrompt + "\n\n" + sourceText
        guard let encoded = encoded(full) else { return nil }
        return URL(string: "https://claude.ai/new?q=" + encoded)
    }

    private var urlTooLong: Bool {
        let gptLen = "https://chat.openai.com/?prompt=".count + (gptPrompt + sourceText).count
        let claudeLen = "https://claude.ai/new?q=".count + (claudePrompt + sourceText).count
        return gptLen > 6000 || claudeLen > 6000
    }

    var body: some View {
        VStack(spacing: 0) {
            if sourceText.count < minChars {
                Text("Write for at least 5 minutes first. Trust.")
                    .font(.system(size: 14))
                    .foregroundColor(fgColor)
                    .frame(width: 240)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else if urlTooLong {
                Text("Your entry is long — copy the prompt and paste it into ChatGPT or Claude manually.")
                    .font(.system(size: 13))
                    .foregroundColor(fgColor)
                    .frame(width: 240)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                Divider()
                menuRow(label: didCopy ? "Copied!" : "Copy Prompt") { copyPrompt() }
            } else {
                menuRow(label: "ChatGPT") {
                    isPresented = false
                    if let url = gptURL { NSWorkspace.shared.open(url) }
                }
                Divider()
                menuRow(label: "Claude") {
                    isPresented = false
                    if let url = claudeURL { NSWorkspace.shared.open(url) }
                }
                Divider()
                menuRow(label: didCopy ? "Copied!" : "Copy Prompt") { copyPrompt() }
            }
        }
        .frame(minWidth: 140, maxWidth: 260)
        .background(bgColor)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    @ViewBuilder
    private func menuRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundColor(fgColor)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func copyPrompt() {
        let full = gptPrompt + "\n\n" + sourceText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }
}
