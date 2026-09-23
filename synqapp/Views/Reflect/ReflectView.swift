//  ReflectView.swift
//  SynqApp — talk an entry (or a week, or a month) through with Claude or OpenAI, by text or voice

import SwiftUI
import SynqCore
import Combine

// MARK: - Session

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatTurn.Role
    var text: String
    var isStreaming = false
}

final class ReflectSession: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var isReplying = false
    @Published var error: String?
    @Published private(set) var hasStarted = false
    @Published private(set) var usesVoice = false

    let voice = VoiceSession()

    private var context = ""
    private let prefs = PreferencesService.shared
    private let client = AIClient()
    private var replyTask: Task<Void, Never>?
    private var spokenUpTo: String.Index?

    init() {
        voice.onUtterance = { [weak self] text in self?.send(text) }
    }

    /// The journal context opens the conversation; every exchange after it is sent as real turns.
    private var turns: [ChatTurn] {
        [ChatTurn(.user, context)] + messages.filter { !$0.text.isEmpty }.map { ChatTurn($0.role, $0.text) }
    }

    func start(context: String, voice useVoice: Bool) {
        self.context = context
        messages = []
        error = nil
        hasStarted = true
        usesVoice = false
        if useVoice { startVoice(thenReply: true) } else { requestReply() }
    }

    func send(_ text: String? = nil) {
        let text = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }
        if text == input.trimmingCharacters(in: .whitespacesAndNewlines) { input = "" }
        messages.append(ChatMessage(role: .user, text: text))
        requestReply()
    }

    func retry() {
        error = nil
        requestReply()
    }

    func setVoice(_ on: Bool) {
        guard on != usesVoice else { return }
        if on { startVoice(thenReply: false) } else { usesVoice = false; voice.end() }
    }

    private func startVoice(thenReply: Bool) {
        Task { [weak self] in
            if let problem = await VoiceSession.requestPermissions() {
                self?.error = problem
                self?.usesVoice = false
                if thenReply { self?.requestReply() }
                return
            }
            self?.usesVoice = true
            self?.voice.begin()
            if thenReply { self?.requestReply() }
        }
    }

    private func requestReply() {
        let system = usesVoice ? Reflection.voiceSystemPrompt : Reflection.systemPrompt
        guard let request = prefs.aiRequest(system: system, turns: turns) else {
            error = AIError.missingKey(prefs.aiProvider).localizedDescription
            return
        }
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        isReplying = true
        error = nil
        spokenUpTo = nil
        if usesVoice { voice.replyWillStart() }

        replyTask = Task { [weak self, client] in
            do {
                for try await chunk in client.stream(request) {
                    self?.append(chunk, to: reply.id)
                }
            } catch {
                self?.error = error.localizedDescription
            }
            self?.finish(reply.id)
        }
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += chunk
        if usesVoice { speakCompletedSentences(in: messages[index].text, final: false) }
    }

    private func finish(_ id: UUID) {
        isReplying = false
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isStreaming = false
        if usesVoice {
            speakCompletedSentences(in: messages[index].text, final: true)
            voice.replyDidFinish()
        }
        if messages[index].text.isEmpty { messages.remove(at: index) }
    }

    /// Speaks each sentence as soon as it has streamed in, so voice replies start without waiting for the whole answer.
    private func speakCompletedSentences(in text: String, final: Bool) {
        let start = spokenUpTo ?? text.startIndex
        guard start < text.endIndex else { return }
        let pending = text[start...]
        let end: String.Index
        if final {
            end = text.endIndex
        } else if let boundary = pending.lastIndex(where: { ".!?\n".contains($0) }) {
            end = text.index(after: boundary)
        } else {
            return
        }
        voice.speak(String(text[start..<end]))
        spokenUpTo = end
    }

    func end() {
        replyTask?.cancel()
        replyTask = nil
        voice.end()
        isReplying = false
        usesVoice = false
        hasStarted = false
        messages = []
        input = ""
        error = nil
    }
}

// MARK: - View

struct ReflectView: View {

    @ObservedObject var vm: AppViewModel
    @StateObject private var session = ReflectSession()
    @ObservedObject private var prefs = PreferencesService.shared
    @State private var scope: ReflectionScope = .session

    private var hasKey: Bool { KeychainService.shared.hasKey(for: prefs.aiProvider) }

    var body: some View {
        Group {
            if session.hasStarted {
                ConversationView(session: session)
            } else {
                startScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    session.end()
                    vm.backToWriting()
                } label: {
                    Label("Back to Writing", systemImage: "chevron.backward")
                }
                .help("Back to writing")
            }
            if session.hasStarted {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: Binding(get: { session.usesVoice }, set: { session.setVoice($0) })) {
                        Label("Voice", systemImage: session.usesVoice ? "waveform" : "mic")
                    }
                    .help(session.usesVoice ? "Turn voice off" : "Talk instead of typing")

                    Button {
                        session.end()
                    } label: {
                        Label("New Conversation", systemImage: "arrow.counterclockwise")
                    }
                    .help("Start over")
                }
            }
        }
        .onDisappear { session.end() }
    }

    private var startScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Reflect").font(.largeTitle.weight(.semibold))
                Text("Talk it through with an AI that has read what you wrote.")
                    .foregroundStyle(.secondary)
            }

            Picker("Reflect on", selection: $scope) {
                ForEach(ReflectionScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)

            Text(scope.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            if hasKey {
                HStack(spacing: 10) {
                    Button {
                        session.start(context: vm.reflectionContext(for: scope), voice: false)
                    } label: {
                        Label("Start Writing", systemImage: "text.bubble")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        session.start(context: vm.reflectionContext(for: scope), voice: true)
                    } label: {
                        Label("Start Talking", systemImage: "mic")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                Text("\(prefs.aiProvider.displayName) · \(modelName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 8) {
                    Text("Add your \(prefs.aiProvider.displayName) API key to start.")
                        .foregroundStyle(.secondary)
                    SettingsLink { Text("Open Settings…") }
                        .controlSize(.large)
                }
            }

            Divider().frame(width: 340).padding(.vertical, 6)

            Button {
                vm.writeWeeklyRecap()
            } label: {
                Label("Write This Week's Recap", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.link)
            .disabled(!hasKey || vm.isWritingRecap)
            .help("Saves an AI summary of your week as a new entry")
        }
        .padding(40)
    }

    private var modelName: String {
        let id = prefs.aiModel(for: prefs.aiProvider)
        return prefs.aiProvider.suggestedModels.first { $0.id == id }?.name ?? id
    }
}

// MARK: - Conversation

struct ConversationView: View {
    @ObservedObject var session: ReflectSession
    @ObservedObject var voice: VoiceSession
    @FocusState private var inputFocused: Bool

    init(session: ReflectSession) {
        self.session = session
        self.voice = session.voice
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(session.messages) { MessageRow(message: $0).id($0.id) }
                        if let error = session.error {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                Button("Try Again", action: session.retry)
                                    .controlSize(.small)
                            }
                            .id("error")
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: session.messages.last?.text) { _, _ in
                    if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()
            if session.usesVoice { voiceBar } else { inputBar }
        }
        .onAppear { inputFocused = true }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply", text: $session.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { session.send() }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            Button {
                session.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            .disabled(!canSend)
            .help("Send (Return)")
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var canSend: Bool {
        !session.isReplying && !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var voiceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: voiceIcon)
                .symbolEffect(.pulse, isActive: voice.phase == .listening || voice.phase == .speaking)
                .foregroundStyle(voice.phase == .listening ? Color.red : Color.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(voiceTitle).font(.callout.weight(.medium))
                if voice.phase == .listening, !voice.heard.isEmpty {
                    Text(voice.heard).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if voice.phase == .idle {
                Button("Listen") { voice.listen() }
            }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var voiceIcon: String {
        switch voice.phase {
        case .idle:      return "mic.slash"
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "speaker.wave.2.fill"
        }
    }

    private var voiceTitle: String {
        switch voice.phase {
        case .idle:      return "Voice paused"
        case .listening: return voice.heard.isEmpty ? "Listening… just start talking" : "Listening…"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Speaking…"
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if message.text.isEmpty && message.isStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message.text + (message.isStreaming ? " ▍" : ""))
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
