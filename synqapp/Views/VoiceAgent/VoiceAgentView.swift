//  VoiceAgentView.swift
//  SynqApp — AI Reflect: stream a conversation about your entries with Claude or OpenAI

import SwiftUI
import Combine
import SynqCore

// MARK: - Chat message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatTurn.Role
    var text: String
    var isStreaming: Bool = false

    var isUser: Bool { role == .user }
}

// MARK: - ViewModel

final class VoiceAgentViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isMuted = false
    @Published var isTextMode = true
    @Published var errorMessage: String? = nil
    @Published var inputText = ""
    @Published var isAITyping = false

    private let context: String
    private let prefs = PreferencesService.shared
    private let client = AIClient()
    private var replyTask: Task<Void, Never>?

    init(context: String) {
        self.context = context
    }

    /// The journal context opens the conversation; every exchange after it is sent as real turns.
    private var turns: [ChatTurn] {
        [ChatTurn(.user, context)] + messages
            .filter { !$0.text.isEmpty }
            .map { ChatTurn($0.role, $0.text) }
    }

    // MARK: - Connect

    func connect() {
        guard !isConnected else { return }
        guard KeychainService.shared.hasKey(for: prefs.aiProvider) else {
            errorMessage = AIError.missingKey(prefs.aiProvider).localizedDescription
            return
        }
        isConnected = true
        requestReply()
    }

    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAITyping else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, text: text))
        requestReply()
    }

    private func requestReply() {
        guard let request = prefs.aiRequest(system: Reflection.systemPrompt, turns: turns) else {
            errorMessage = AIError.missingKey(prefs.aiProvider).localizedDescription
            return
        }
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        isAITyping = true
        errorMessage = nil

        replyTask = Task { [weak self, client] in
            do {
                for try await chunk in client.stream(request) {
                    self?.update(reply.id) { $0.text += chunk }
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.finishReply(reply.id)
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func finishReply(_ id: UUID) {
        isAITyping = false
        update(id) { $0.isStreaming = false }
        messages.removeAll { $0.id == id && $0.text.isEmpty }
    }

    // MARK: - Controls

    func toggleMute() {
        isMuted.toggle()
    }

    func disconnect() {
        replyTask?.cancel()
        replyTask = nil
        isConnected = false
        isConnecting = false
        isAITyping = false
    }

    func cleanup() {
        disconnect()
        messages = []
        inputText = ""
        errorMessage = nil
    }
}

// MARK: - Main view

struct VoiceAgentView: View {

    @ObservedObject var vm: AppViewModel
    let context: String
    let colorScheme: ColorScheme

    @StateObject private var agentVM: VoiceAgentViewModel
    @State private var showSettings = false

    private let g: CGFloat = 4

    init(vm: AppViewModel, context: String, colorScheme: ColorScheme) {
        self.vm = vm
        self.context = context
        self.colorScheme = colorScheme
        _agentVM = StateObject(wrappedValue: VoiceAgentViewModel(context: context))
    }

    private var bg1: Color {
        colorScheme == .dark
            ? Color(red: 0.027, green: 0.027, blue: 0.027)
            : Color(red: 0.976, green: 0.976, blue: 0.965)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bg1.ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    Button {
                        agentVM.disconnect()
                        vm.backToWriting()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                    Spacer()

                    // Settings gear
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }

            // Content
            if !agentVM.isConnected && !agentVM.isConnecting {
                StartView(agentVM: agentVM, colorScheme: colorScheme, g: g)
            } else if agentVM.isConnecting {
                ConnectingView(colorScheme: colorScheme, g: g)
            } else {
                ChatView(agentVM: agentVM, colorScheme: colorScheme, g: g)
                    .padding(.bottom, 15 * g + 8 * g)
                    .padding(.top, 48)

                ControlBarView(
                    agentVM: agentVM,
                    colorScheme: colorScheme,
                    g: g,
                    onDisconnect: {
                        agentVM.disconnect()
                        vm.backToWriting()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error
            if let err = agentVM.errorMessage {
                ErrorView(message: err, colorScheme: colorScheme, g: g) {
                    agentVM.errorMessage = nil
                }
                .padding(.horizontal, 3 * g)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(colorScheme: colorScheme)
        }
        .onAppear { agentVM.connect() }
        .onDisappear { agentVM.cleanup() }
    }
}

// MARK: - Start view

struct StartView: View {
    @ObservedObject var agentVM: VoiceAgentViewModel
    let colorScheme: ColorScheme
    let g: CGFloat

    private var fg3: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.39)
    }

    var body: some View {
        VStack(spacing: 8 * g) {
            HStack(spacing: g) {
                ForEach([2, 8, 12, 8, 2], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 2 * g, height: CGFloat(h))
                }
            }

            Button("Start Reflecting") { agentVM.connect() }
                .buttonStyle(ProminentButtonStyle())
                .frame(width: 58 * g, height: 11 * g)

            Text(KeychainService.shared.hasKey(for: PreferencesService.shared.aiProvider)
                 ? "Powered by your \(PreferencesService.shared.aiProvider.displayName) key"
                 : "Add your \(PreferencesService.shared.aiProvider.displayName) API key in Settings to begin")
                .font(.system(size: 12))
                .foregroundColor(fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32 * g)
    }
}

// MARK: - Connecting view

struct ConnectingView: View {
    let colorScheme: ColorScheme
    let g: CGFloat
    @State private var animating = false

    var body: some View {
        VStack(spacing: 8 * g) {
            HStack(spacing: g) {
                ForEach(Array([2, 8, 12, 8, 2].enumerated()), id: \.offset) { idx, h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 2 * g, height: CGFloat(h))
                        .scaleEffect(y: animating ? 1.5 : 0.5, anchor: .center)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(idx) * 0.1),
                            value: animating
                        )
                }
            }
            Text("Preparing your reflection…")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { animating = true }
    }
}

// MARK: - Chat view

struct ChatView: View {
    @ObservedObject var agentVM: VoiceAgentViewModel
    let colorScheme: ColorScheme
    let g: CGFloat

    private let typingIndicatorID = UUID()

    private var bg2: Color {
        colorScheme == .dark ? Color(white: 0.075) : Color(white: 0.953)
    }
    private var fg1: Color {
        colorScheme == .dark ? Color(white: 0.8) : Color(white: 0.23)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(agentVM.messages) { msg in
                            ChatBubble(
                                message: msg,
                                colorScheme: colorScheme,
                                bg2: bg2,
                                fg1: fg1,
                                g: g
                            )
                            .id(msg.id)
                        }

                        if agentVM.isAITyping && agentVM.messages.last?.isStreaming != true {
                            TypingIndicator(colorScheme: colorScheme, g: g)
                                .id(typingIndicatorID)
                        }
                    }
                    .padding(.horizontal, 4 * g)
                    .padding(.vertical, 2 * g)
                }
                .onChange(of: agentVM.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(agentVM.messages.last?.id ?? typingIndicatorID, anchor: .bottom)
                    }
                }
                .onChange(of: agentVM.messages.last?.text) { _ in
                    withAnimation {
                        proxy.scrollTo(agentVM.messages.last?.id ?? typingIndicatorID, anchor: .bottom)
                    }
                }
            }

            // Text input
            if agentVM.isTextMode {
                HStack(spacing: 2 * g) {
                    TextField("Reply…", text: $agentVM.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bg2, in: RoundedRectangle(cornerRadius: 10))
                        .onSubmit { agentVM.sendText() }

                    Button {
                        agentVM.sendText()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(agentVM.inputText.isEmpty || agentVM.isAITyping
                                             ? .secondary : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(agentVM.inputText.isEmpty || agentVM.isAITyping)
                }
                .padding(.horizontal, 4 * g)
                .padding(.vertical, 2 * g)
                .background(
                    colorScheme == .dark
                        ? Color(red: 0.027, green: 0.027, blue: 0.027)
                        : Color(red: 0.976, green: 0.976, blue: 0.965)
                )
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let colorScheme: ColorScheme
    let bg2: Color
    let fg1: Color
    let g: CGFloat

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 4 * g) }

            if message.isUser {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(fg1)
                    .padding(.horizontal, 4 * g)
                    .padding(.vertical, 2 * g)
                    .background(bg2, in: RoundedRectangle(cornerRadius: 4 * g))
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundColor(fg1)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if message.isStreaming {
                        // Blinking cursor
                        BlinkingCursor(colorScheme: colorScheme)
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 4 * g) }
        }
    }
}

struct BlinkingCursor: View {
    let colorScheme: ColorScheme
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible = false
                }
            }
    }
}

struct TypingIndicator: View {
    let colorScheme: ColorScheme
    let g: CGFloat
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.4).delay(Double(i) * 0.15).repeatForever(), value: phase)
            }
        }
        .padding(.leading, 4 * g)
        .onAppear {
            withAnimation { phase = 0 }
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Control bar

struct ControlBarView: View {
    @ObservedObject var agentVM: VoiceAgentViewModel
    let colorScheme: ColorScheme
    let g: CGFloat
    let onDisconnect: () -> Void

    private var bg1: Color {
        colorScheme == .dark
            ? Color(red: 0.027, green: 0.027, blue: 0.027)
            : Color(red: 0.976, green: 0.976, blue: 0.965)
    }
    private var separator1: Color {
        colorScheme == .dark ? Color(white: 0.125) : Color(white: 0.859)
    }
    private var fgSerious: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.459, blue: 0.4)
            : Color(red: 0.863, green: 0.106, blue: 0.024)
    }
    private var bgSerious: Color {
        colorScheme == .dark
            ? Color(red: 0.122, green: 0.055, blue: 0.043)
            : Color(red: 0.980, green: 0.902, blue: 0.902)
    }

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 0) {
                // Mic (only relevant in voice mode)
                if !agentVM.isTextMode {
                    ControlBarButton(
                        icon: agentVM.isMuted ? "mic.slash.fill" : "mic.fill",
                        isActive: !agentVM.isMuted,
                        colorScheme: colorScheme,
                        g: g
                    ) { agentVM.toggleMute() }

                    Divider().frame(height: 11 * g)
                }

                // Text mode toggle
                ControlBarButton(
                    icon: "ellipsis.message.fill",
                    isActive: agentVM.isTextMode,
                    colorScheme: colorScheme,
                    g: g
                ) { agentVM.isTextMode.toggle() }

                Divider().frame(height: 11 * g)

                // End session
                Button { onDisconnect() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(fgSerious)
                        .frame(width: 16 * g, height: 11 * g)
                        .background(bgSerious, in: RoundedRectangle(cornerRadius: 7.5 * g))
                }
                .buttonStyle(.plain)
                .help("End session")
                .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            .frame(height: 15 * g)
            .background(bg1, in: RoundedRectangle(cornerRadius: 7.5 * g))
            .overlay(RoundedRectangle(cornerRadius: 7.5 * g).stroke(separator1, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
            Spacer()
        }
        .padding(.bottom, 8 * g)
        .padding(.horizontal, 16 * g)
    }
}

struct ControlBarButton: View {
    let icon: String
    let isActive: Bool
    let colorScheme: ColorScheme
    let g: CGFloat
    let action: () -> Void

    private var bg2: Color {
        colorScheme == .dark ? Color(white: 0.075) : Color(white: 0.953)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 16 * g, height: 11 * g)
                .background(isActive ? bg2 : Color.clear, in: RoundedRectangle(cornerRadius: 2 * g))
        }
        .buttonStyle(.plain)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}

// MARK: - Error view

struct ErrorView: View {
    let message: String
    let colorScheme: ColorScheme
    let g: CGFloat
    let onDismiss: () -> Void

    private var bgSerious: Color {
        colorScheme == .dark
            ? Color(red: 0.122, green: 0.055, blue: 0.043)
            : Color(red: 0.980, green: 0.902, blue: 0.902)
    }
    private var fgSerious: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.459, blue: 0.4)
            : Color(red: 0.863, green: 0.106, blue: 0.024)
    }
    private var separatorSerious: Color {
        colorScheme == .dark
            ? Color(red: 0.4, green: 0.1, blue: 0.08)
            : Color(red: 0.9, green: 0.7, blue: 0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(fgSerious)
                Text("Error").font(.system(size: 15, weight: .semibold)).foregroundColor(fgSerious)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundColor(fgSerious)
                }
                .buttonStyle(.plain)
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(fgSerious)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(3 * g)
        .background(bgSerious, in: RoundedRectangle(cornerRadius: 2 * g))
        .overlay(RoundedRectangle(cornerRadius: 2 * g).stroke(separatorSerious, lineWidth: 1))
    }
}

// MARK: - Button style

struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}
