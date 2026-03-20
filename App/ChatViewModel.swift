import Foundation
import LocalLLMClient
import LocalLLMClientLlama

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isModelReady: Bool = false
    @Published var isGenerating: Bool = false
    @Published var statusText: String = "Preparing model..."
    @Published var downloadInProgress: Bool = false
    @Published var voiceModeEnabled: Bool = false
    @Published var isListening: Bool = false
    @Published var voiceStatusText: String = "Voice mode is off"

    private let memoryStore = MemoryStore()
    private let voiceIO = VoiceIOManager()
    private let silenceDetectionInterval: TimeInterval = 1.2
    private let memoryToolsEnabled = false
    private var session: LLMSession?
    private var lastSpeechAt: Date?
    private var silenceDetectionTask: Task<Void, Never>?

    init() {
        Task {
            await prepareModel()
        }
    }

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isModelReady, !isGenerating else { return }
        if isListening {
            stopListening()
        }

        inputText = ""
        messages.append(ChatMessage(role: .user, text: trimmed))

        Task {
            await generateResponse(for: trimmed)
        }
    }

    func toggleVoiceMode() {
        Task {
            if voiceModeEnabled {
                disableVoiceMode()
            } else {
                await enableVoiceMode()
                if voiceModeEnabled {
                    startListeningIfPossible()
                }
            }
        }
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            Task {
                if !voiceModeEnabled {
                    await enableVoiceMode()
                }
                startListeningIfPossible()
            }
        }
    }

    func shutdownVoice() {
        disableVoiceMode()
    }

    private func prepareModel() async {
        do {
            downloadInProgress = true
            statusText = "Downloading model from Hugging Face..."

            let model = LLMSession.DownloadModel.llama(
                id: "unsloth/gemma-3-1b-it-GGUF",
                model: "gemma-3-1b-it-Q4_K_M.gguf",
                parameter: .init(
                    temperature: 0.7,
                    topK: 40,
                    topP: 0.9
                )
            )

            try await model.downloadModel { _ in }

            let session: LLMSession
            if memoryToolsEnabled {
                let rememberTool = RememberUserFactTool(store: memoryStore)
                let recallTool = RecallUserFactTool(store: memoryStore)
                let searchTool = SearchUserMemoryTool(store: memoryStore)
                session = LLMSession(model: model, tools: [rememberTool, recallTool, searchTool])
                session.messages = [.system("""
                あなたは親切で正確なアシスタントです。ユーザーには自然な日本語で回答してください。
                ユーザーに関する長期的な情報はツールを使って管理してください。
                - 安定した好み、プロフィール、習慣、制約は remember_user_fact を使って保存する。
                - キーが明確なときは recall_user_fact で参照する。
                - キーが不明なときは search_user_memory で検索する。
                キー名は短く分かりやすくする（例: favorite_food, timezone, coding_style）。
                """)]
            } else {
                session = LLMSession(model: model)
                session.messages = [.system("あなたは親切で正確なアシスタントです。ユーザーには自然な日本語で簡潔に回答してください。")]
            }
            self.session = session

            isModelReady = true
            statusText = "Ready"
        } catch {
            statusText = "Model download failed: \(error.localizedDescription)"
        }

        downloadInProgress = false
    }

    private func generateResponse(for prompt: String) async {
        guard let session else { return }

        isGenerating = true
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        do {
            for try await chunk in session.streamResponse(to: prompt) {
                if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[index].text += chunk
                }
            }
        } catch {
            messages.append(ChatMessage(role: .system, text: "Error: \(error.localizedDescription)"))
        }

        isGenerating = false

        if voiceModeEnabled, let responseText = messages.first(where: { $0.id == assistantID })?.text {
            voiceStatusText = "Speaking..."
            voiceIO.speak(responseText) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.voiceModeEnabled, !self.isGenerating else { return }
                    self.startListeningIfPossible()
                }
            }
        } else if voiceModeEnabled {
            startListeningIfPossible()
        }
    }

    private func enableVoiceMode() async {
        voiceStatusText = "Requesting microphone and speech permissions..."
        let granted = await voiceIO.requestPermissions()
        if granted {
            voiceModeEnabled = true
            voiceStatusText = "Voice mode is on"
        } else {
            voiceModeEnabled = false
            isListening = false
            voiceStatusText = "Voice permission denied"
        }
    }

    private func disableVoiceMode() {
        stopListening()
        voiceIO.stopSpeaking()
        voiceModeEnabled = false
        voiceStatusText = "Voice mode is off"
    }

    private func startListeningIfPossible() {
        guard voiceModeEnabled else { return }
        silenceDetectionTask?.cancel()
        silenceDetectionTask = nil
        lastSpeechAt = nil

        do {
            try voiceIO.startListening { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.inputText = text
                    self?.handlePartialSpeechResult(text)
                }
            }
            isListening = true
            voiceStatusText = "Listening... (auto-send on silence)"
        } catch {
            isListening = false
            voiceStatusText = "Voice input error: \(error.localizedDescription)"
        }
    }

    private func stopListening() {
        silenceDetectionTask?.cancel()
        silenceDetectionTask = nil
        voiceIO.stopListening()
        isListening = false
        if voiceModeEnabled {
            voiceStatusText = "Voice mode is on"
        } else {
            voiceStatusText = "Voice mode is off"
        }
    }

    private func handlePartialSpeechResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastSpeechAt = Date()
        scheduleSilenceDetection()
    }

    private func scheduleSilenceDetection() {
        silenceDetectionTask?.cancel()
        let baseline = lastSpeechAt
        silenceDetectionTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(self.silenceDetectionInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard self.isListening, self.voiceModeEnabled else { return }
                guard let baseline, self.lastSpeechAt == baseline else { return }
                let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.voiceStatusText = "Silence detected. Sending..."
                self.stopListening()
                self.send()
            }
        }
    }
}
