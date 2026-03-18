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

    private var session: LLMSession?

    init() {
        Task {
            await prepareModel()
        }
    }

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isModelReady, !isGenerating else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, text: trimmed))

        Task {
            await generateResponse(for: trimmed)
        }
    }

    private func prepareModel() async {
        do {
            downloadInProgress = true
            statusText = "Downloading model from Hugging Face..."

            let model = LLMSession.DownloadModel.llama(
                id: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
                model: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
                parameter: .init(
                    temperature: 0.7,
                    topK: 40,
                    topP: 0.9
                )
            )

            try await model.downloadModel { _ in }

            let session = LLMSession(model: model)
            session.messages = [.system("You are a helpful assistant.")]
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
    }
}
