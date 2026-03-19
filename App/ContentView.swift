import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 12) {
            header

            if viewModel.downloadInProgress {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(viewModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages) { _, newValue in
                    guard let last = newValue.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            inputBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onDisappear {
            viewModel.shutdownVoice()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AstroPotatoChatPhone")
                .font(.title2).bold()
            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.voiceStatusText)
                .font(.caption)
                .foregroundStyle(viewModel.voiceModeEnabled ? .green : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(!viewModel.isModelReady || viewModel.isGenerating)

            Button(action: viewModel.toggleVoiceMode) {
                Image(systemName: viewModel.voiceModeEnabled ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title3)
            }
            .buttonStyle(.bordered)

            Button(action: viewModel.toggleListening) {
                Image(systemName: viewModel.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.voiceModeEnabled || viewModel.isGenerating)

            Button(action: viewModel.send) {
                Text(viewModel.isGenerating ? "Thinking" : "Send")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isModelReady || viewModel.isGenerating)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.text.isEmpty ? "..." : message.text)
            .font(.body)
            .foregroundStyle(message.role == .user ? .white : .primary)
            .padding(12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(white: 0.92)
        case .system:
            return Color(white: 0.85)
        }
    }
}

#Preview {
    ContentView()
}
