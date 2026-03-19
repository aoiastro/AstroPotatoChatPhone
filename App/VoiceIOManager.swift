import AVFoundation
import Foundation
import Speech

enum VoiceIOError: LocalizedError {
    case recognizerUnavailable
    case missingInputNode

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable on this device."
        case .missingInputNode:
            return "Microphone input node is unavailable."
        }
    }
}

@MainActor
final class VoiceIOManager: NSObject, AVSpeechSynthesizerDelegate {
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()
    private let synthesizer = AVSpeechSynthesizer()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onSpeechFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func requestPermissions() async -> Bool {
        let speechPermission = await requestSpeechPermission()
        let microphonePermission = await requestMicrophonePermission()
        return speechPermission && microphonePermission
    }

    func startListening(onPartialResult: @escaping @Sendable (String) -> Void) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceIOError.recognizerUnavailable
        }

        stopListening()
        stopSpeaking()

        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let result {
                onPartialResult(result.bestTranscription.formattedString)
            }

            if error != nil {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String, onFinished: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stopListening()
        onSpeechFinished = nil
        synthesizer.stopSpeaking(at: .immediate)
        onSpeechFinished = onFinished

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            onSpeechFinished = nil
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let callback = onSpeechFinished
        onSpeechFinished = nil
        callback?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onSpeechFinished = nil
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
