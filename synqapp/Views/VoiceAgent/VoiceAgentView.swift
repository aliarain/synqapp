
//  VoiceAgentView.swift
//  Spill — LiveKit voice session UI shell
//  Wire up LiveKit SDK here when ready (livekit-client-sdk-swift)

import SwiftUI
import Combine

// MARK: - Chat message model

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date = Date()
}

// MARK: - ViewModel (stub — replace internals with LiveKit SDK)

final class VoiceAgentViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var isMuted: Bool = false
    @Published var isTextMode: Bool = false
    @Published var errorMessage: String? = nil
    @Published var inputText: String = ""

    private let context: String

    init(context: String) {
        self.context = context
    }

    func connect() {
        isConnecting = true
        errorMessage = nil

        // TODO: Replace with real LiveKit token fetch + room connect
        // 1. GET /getToken from your backend
        // 2. room.connect(url, token)
        // 3. On connected: isConnecting = false, isConnected = true
        // 4. Send context as first message

        // Stub: simulate connection after 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.isConnecting = false
            self.isConnected = true
            // Send context as first message (agent receives this)
            self.messages.append(ChatMessage(text: "[Context sent to agent]", isUser: true))
            self.messages.append(ChatMessage(text: "Hey! I've read through what you wrote. What's on your mind?", isUser: false))
        }
    }

    func disconnect() {
        // TODO: room.disconnect()
        isConnected = false
        isConnecting = false
        cleanup()
    }

    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(text: text, isUser: true))
        inputText = ""
        // TODO: send via LiveKit data channel or text track
    }

    func toggleMute() {
        isMuted.toggle()
        // TODO: room.localParticipant.setMicrophone(enabled: !isMuted)
    }

    func cleanup() {
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

    // Grid unit
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

            if !agentVM.isConnected && !agentVM.isConnecting {
                StartView(agentVM: agentVM, colorScheme: colorScheme, g: g)
            } else if agentVM.isConnecting {
                ConnectingView(colorScheme: colorScheme, g: g)
            } else {
                // Chat
                ChatView(agentVM: agentVM, colorScheme: colorScheme, g: g)
                    .padding(.bottom, 60 + 8 * g)

                // Control bar
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

            // Error overlay
            if let err = agentVM.errorMessage {
                ErrorView(message: err, colorScheme: colorScheme, g: g) {
                    agentVM.errorMessage = nil
                }
                .padding(.horizontal, 3 * g)
                .padding(.bottom, 80)
            }
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
            // Animated bars
            HStack(spacing: g) {
                ForEach([2, 8, 12, 8, 2], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 2 * g, height: CGFloat(h))
                }
            }

            Button("Connect") {
                agentVM.connect()
            }
            .buttonStyle(ProminentButtonStyle())
            .frame(width: 58 * g, height: 11 * g)

            Text("Tap to start your reflection session")
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
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(idx) * 0.1),
                            value: animating
                        )
                }
            }
            Text("Preparing your reflection session…")
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

    private var bg2: Color {
        colorScheme == .dark ? Color(white: 0.075) : Color(white: 0.953)
    }
    private var fg1: Color {
        colorScheme == .dark ? Color(white: 0.8) : Color(white: 0.23)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages (inverted scroll so newest is at bottom)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(agentVM.messages) { msg in
                            ChatBubble(message: msg, colorScheme: colorScheme, bg2: bg2, fg1: fg1, g: g)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 4 * g)
                    .padding(.vertical, 2 * g)
                }
                .onChange(of: agentVM.messages.count) { _ in
                    if let last = agentVM.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Text input (shown when text mode active)
            if agentVM.isTextMode {
                HStack(spacing: 2 * g) {
                    TextField("Type a message…", text: $agentVM.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit { agentVM.sendText() }
                    Button("Send") { agentVM.sendText() }
                        .buttonStyle(ProminentButtonStyle())
                }
                .padding(.horizontal, 4 * g)
                .padding(.vertical, 2 * g)
                .background(bg2)
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
        HStack {
            if message.isUser { Spacer(minLength: 4 * g) }

            if message.isUser {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(fg1)
                    .padding(.horizontal, 4 * g)
                    .padding(.vertical, 2 * g)
                    .background(bg2, in: RoundedRectangle(cornerRadius: 4 * g))
            } else {
                Text(message.text)
                    .font(.system(size: 17))
                    .foregroundColor(fg1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !message.isUser { Spacer(minLength: 4 * g) }
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
        colorScheme == .dark ? Color(red: 0.027, green: 0.027, blue: 0.027) : Color(red: 0.976, green: 0.976, blue: 0.965)
    }
    private var separator1: Color {
        colorScheme == .dark ? Color(white: 0.125) : Color(white: 0.859)
    }
    private var fgSerious: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.459, blue: 0.4) : Color(red: 0.863, green: 0.106, blue: 0.024)
    }
    private var bgSerious: Color {
        colorScheme == .dark ? Color(red: 0.122, green: 0.055, blue: 0.043) : Color(red: 0.980, green: 0.902, blue: 0.902)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                // Mute
                ControlBarButton(
                    icon: agentVM.isMuted ? "mic.slash.fill" : "mic.fill",
                    isActive: !agentVM.isMuted,
                    colorScheme: colorScheme,
                    g: g
                ) {
                    agentVM.toggleMute()
                }

                Divider().frame(height: 11 * g)

                // Text mode
                ControlBarButton(
                    icon: "ellipsis.message.fill",
                    isActive: agentVM.isTextMode,
                    colorScheme: colorScheme,
                    g: g
                ) {
                    agentVM.isTextMode.toggle()
                }

                Divider().frame(height: 11 * g)

                // Disconnect
                Button {
                    onDisconnect()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 17, weight: .medium))
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
            .overlay(
                RoundedRectangle(cornerRadius: 7.5 * g)
                    .stroke(separator1, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 10)

            Spacer(minLength: 0)
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
                .background(
                    isActive ? bg2 : Color.clear,
                    in: RoundedRectangle(cornerRadius: 2 * g)
                )
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
        colorScheme == .dark ? Color(red: 0.122, green: 0.055, blue: 0.043) : Color(red: 0.980, green: 0.902, blue: 0.902)
    }
    private var fgSerious: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.459, blue: 0.4) : Color(red: 0.863, green: 0.106, blue: 0.024)
    }
    private var separatorSerious: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.1, blue: 0.08) : Color(red: 0.9, green: 0.7, blue: 0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(fgSerious)
                Text("Connection Error")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(fgSerious)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .foregroundColor(fgSerious)
                }
                .buttonStyle(.plain)
            }
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(fgSerious)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(3 * g)
        .background(bgSerious, in: RoundedRectangle(cornerRadius: 2 * g))
        .overlay(
            RoundedRectangle(cornerRadius: 2 * g)
                .stroke(separatorSerious, lineWidth: 1)
        )
    }
}

// MARK: - Button styles

struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Color(red: 0.0, green: 0.173, blue: 0.949)
                    .opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}
