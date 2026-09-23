//  VoiceSession.swift
//  SynqApp — hands-free voice loop for Reflect: listen (on-device speech recognition) → reply → speak aloud

import AVFoundation
import Speech
import Combine

final class VoiceSession: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle, listening, thinking, speaking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var heard = ""

    /// Called with what the person said once they pause.
    var onUtterance: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private var replyFinished = true
    private var isActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Permissions

    static func requestPermissions() async -> String? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "Voice reflection needs Speech Recognition. Allow SynqApp in System Settings → Privacy & Security → Speech Recognition."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Voice reflection needs the microphone. Allow SynqApp in System Settings → Privacy & Security → Microphone."
        }
        return nil
    }

    // MARK: - Listening

    func begin() {
        isActive = true
        listen()
    }

    func listen() {
        guard isActive else { return }
        stopListening()
        heard = ""
        guard let recognizer, recognizer.isAvailable else {
            phase = .idle
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { @Sendable buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            phase = .idle
            return
        }

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async { self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
        phase = .listening
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard phase == .listening else { return }
        if let text, !text.isEmpty {
            heard = text
            // A 1.4 s pause ends the turn.
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.finishUtterance() }
            }
        }
        if isFinal { finishUtterance() }
        else if failed && heard.isEmpty { listen() }
    }

    private func finishUtterance() {
        guard phase == .listening else { return }
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        guard !text.isEmpty else { listen(); return }
        phase = .thinking
        replyFinished = false
        onUtterance?(text)
    }

    private func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // MARK: - Speaking

    func speak(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        phase = .speaking
        synthesizer.speak(utterance)
    }

    /// Stops listening while a reply streams in, so the Mac never hears itself speak.
    func replyWillStart() {
        stopListening()
        replyFinished = false
        phase = .thinking
    }

    /// Call when the streamed reply is complete; listening resumes once speech finishes.
    func replyDidFinish() {
        replyFinished = true
        if !synthesizer.isSpeaking { listen() }
    }

    func end() {
        isActive = false
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        phase = .idle
        heard = ""
    }

    private static let bestVoice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }()
}

extension VoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.synthesizer.isSpeaking else { return }
            if self.replyFinished { self.listen() } else { self.phase = .thinking }
        }
    }
}
