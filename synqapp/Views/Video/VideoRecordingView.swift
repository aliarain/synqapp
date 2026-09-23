
//  VideoRecordingView.swift
//  SynqApp — camera recording with on-device speech transcription afterwards

import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var permissionGranted = false
    @Published var microphonePermissionGranted = false

    var onReadyToRecord: (() -> Void)?
    var onCannotRecord: (() -> Void)?
    var onFinished: ((URL, String?) -> Void)?

    // Use a dedicated serial queue for all session work
    private let sessionQueue = DispatchQueue(label: "com.synqapp.camera.session")
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingURL: URL?

    // MARK: - Permissions

    func checkPermissions() {
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        let group = DispatchGroup()

        if camStatus == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.permissionGranted = granted
                group.leave()
            }
        } else {
            permissionGranted = (camStatus == .authorized)
        }

        if micStatus == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                self?.microphonePermissionGranted = granted
                group.leave()
            }
        } else {
            microphonePermissionGranted = (micStatus == .authorized)
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            group.enter()
            SFSpeechRecognizer.requestAuthorization { _ in group.leave() }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if self.permissionGranted && self.microphonePermissionGranted {
                self.setupSession()
            } else {
                self.onCannotRecord?()
            }
        }
    }

    // MARK: - Session setup (runs entirely on sessionQueue)

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Video input
            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video),
                let videoInput = try? AVCaptureDeviceInput(device: camera),
                self.session.canAddInput(videoInput)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.onCannotRecord?() }
                return
            }
            self.session.addInput(videoInput)

            // Audio input — let AVCaptureSession own the audio hardware exclusively
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }

            // Movie output
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            // Preview layer must be created after session starts
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.previewLayer = layer
                self.onReadyToRecord?()
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        recordingURL = url
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
        DispatchQueue.main.async { self.isRecording = false }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Post-recording transcription
    // Transcribes the saved .mov file — avoids any conflict with AVCaptureSession audio

    private func transcribe(url: URL, completion: @escaping (String?) -> Void) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            completion(nil)
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            completion(nil)
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal {
                completion(result.bestTranscription.formattedString)
            } else if error != nil {
                completion(nil)
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Transcribe the saved file afterwards so recognition never competes with the capture session for audio.
        DispatchQueue.main.async { [weak self] in
            self?.transcribe(url: outputFileURL) { transcript in
                DispatchQueue.main.async { self?.onFinished?(outputFileURL, transcript) }
            }
        }
    }
}

// MARK: - VideoRecordingView

struct VideoRecordingView: View {

    @ObservedObject var manager: CameraManager
    var onFinish: (URL?, String?) -> Void

    @State private var countdown: Int? = nil
    @State private var countdownTimer: Timer?
    @State private var isTranscribing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live preview
            if let layer = manager.previewLayer {
                CameraPreviewView(layer: layer)
                    .ignoresSafeArea()
            } else {
                // While camera is initialising
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Countdown
            if let c = countdown {
                Text("\(c)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }

            // Controls overlay
            VStack {
                // Top bar
                HStack {
                    Button {
                        countdownTimer?.invalidate()
                        manager.stopSession()
                        onFinish(nil, nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()

                    Spacer()

                    if manager.isRecording {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("REC")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding()
                    }
                }

                Spacer()

                // Record / stop button
                Button {
                    if manager.isRecording {
                        isTranscribing = true
                        manager.stopRecording()
                    } else {
                        startCountdown()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 72, height: 72)
                        if manager.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 56, height: 56)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
                .disabled(countdown != nil)
            }
        }
        .overlay {
            if isTranscribing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Transcribing…").foregroundStyle(.white)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear {
            manager.onFinished = { [weak manager] url, transcript in
                manager?.stopSession()
                onFinish(url, transcript)
            }
        }
    }

    private func startCountdown() {
        countdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            guard let c = countdown else { t.invalidate(); return }
            if c > 1 {
                withAnimation { countdown = c - 1 }
            } else {
                t.invalidate()
                withAnimation { countdown = nil }
                manager.startRecording()
            }
        }
    }
}

// MARK: - Camera preview layer host

struct CameraPreviewView: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = nsView.bounds
        CATransaction.commit()
    }
}
