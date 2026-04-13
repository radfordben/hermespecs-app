/*
 * OpenClaw Chat View
 * 与 OpenClaw AI 聊天
 * 支持: 语音转录、眼镜拍照、文字输入
 */

import SwiftUI

struct OpenClawChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    let image: UIImage?
    let timestamp = Date()
}

struct OpenClawChatView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var openClawService = OpenClawNodeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [OpenClawChatMessage] = []
    @State private var inputText = ""
    @State private var pendingResponse = ""
    @State private var isSending = false

    // ASR states
    @State private var isListening = false
    @State private var asrText = ""           // accumulated final sentences
    @State private var asrPartial = ""        // current partial
    @State private var asrService: OpenClawASRService?
    @State private var showTextInput = false  // toggle between voice/text mode

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection status
                if openClawService.connectionState != .connected {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("openclaw.status.connecting".localized)
                            .font(.system(size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15))
                }

                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg).id(msg.id)
                            }
                            if !pendingResponse.isEmpty {
                                ChatBubble(message: OpenClawChatMessage(
                                    role: "assistant", text: pendingResponse, image: nil
                                ))
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // Bottom control area
                VStack(spacing: 12) {
                    // ASR transcription preview (when listening or has text to send)
                    if isListening || !asrText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            // Transcribed text
                            Text(displayASRText)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)

                            // Send / Cancel buttons after stopping
                            if !isListening && !asrText.isEmpty {
                                HStack(spacing: 12) {
                                    Button {
                                        asrText = ""
                                        asrPartial = ""
                                    } label: {
                                        Text("cancel".localized)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(10)
                                    }

                                    Button {
                                        sendASRText()
                                    } label: {
                                        Text("openclaw.chat.sendvoice".localized)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.purple)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Main action buttons
                    HStack(spacing: 16) {
                        // Camera snap
                        Button {
                            Task { await snapAndSend() }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22))
                                Text("openclaw.chat.snap".localized)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(isSending ? .gray : .purple)
                            .frame(width: 60, height: 60)
                        }
                        .disabled(isSending || openClawService.connectionState != .connected)

                        // Big mic button
                        Button {
                            toggleListening()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        isListening
                                            ? LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                                            : LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                                    )
                                    .frame(width: 72, height: 72)
                                    .shadow(color: isListening ? .red.opacity(0.4) : .purple.opacity(0.3), radius: 10)

                                if isListening {
                                    // Pulsing animation
                                    Circle()
                                        .stroke(Color.red.opacity(0.3), lineWidth: 3)
                                        .frame(width: 88, height: 88)
                                        .scaleEffect(isListening ? 1.1 : 1.0)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isListening)
                                }

                                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                                    .font(.system(size: isListening ? 24 : 28))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(openClawService.connectionState != .connected)

                        // Text input toggle
                        Button {
                            showTextInput.toggle()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 22))
                                Text("openclaw.chat.text".localized)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.purple)
                            .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.vertical, 4)

                    // Text input bar (toggleable)
                    if showTextInput {
                        HStack(spacing: 10) {
                            TextField("openclaw.chat.placeholder".localized, text: $inputText)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.send)
                                .onSubmit { sendText() }

                            Button {
                                sendText()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(inputText.isEmpty ? .gray : .purple)
                            }
                            .disabled(inputText.isEmpty || openClawService.connectionState != .connected)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
            }
            .navigationTitle("OpenClaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(openClawService.connectionState == .connected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        NavigationLink {
                            OpenClawSettingsView()
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
        }
        .onAppear {
            setupChatEventHandler()
            if openClawService.connectionState != .connected,
               openClawService.loadGatewayToken() != nil {
                openClawService.connect()
            }
        }
        .onDisappear {
            stopListening()
            if !pendingResponse.isEmpty {
                messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
                pendingResponse = ""
            }
            openClawService.onChatEvent = nil
        }
    }

    // MARK: - Computed

    private var displayASRText: String {
        if asrText.isEmpty && asrPartial.isEmpty {
            return isListening ? "openclaw.chat.listening".localized : ""
        }
        return asrText + (asrPartial.isEmpty ? "" : asrPartial)
    }

    // MARK: - Chat Events

    private func setupChatEventHandler() {
        openClawService.onChatEvent = { (text: String) in
            if text.hasPrefix("[[FINAL]]") {
                let fullText = String(text.dropFirst(9))
                pendingResponse = ""
                if !fullText.isEmpty {
                    messages.append(OpenClawChatMessage(role: "assistant", text: fullText, image: nil))
                }
            } else {
                pendingResponse = text
            }
        }
    }

    // MARK: - Text

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        flushPendingResponse()
        inputText = ""
        openClawService.sendChatMessage(text)
    }

    // MARK: - Camera

    private func snapAndSend() async {
        isSending = true
        defer { isSending = false }

        let needsStreamStop = !streamViewModel.isStreaming
        if needsStreamStop {
            await streamViewModel.handleStartStreaming()
            let deadline = Date().addingTimeInterval(5.0)
            while streamViewModel.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        guard let frame = streamViewModel.currentVideoFrame else {
            messages.append(OpenClawChatMessage(role: "assistant", text: "openclaw.chat.noframe".localized, image: nil))
            if needsStreamStop { await streamViewModel.stopSession() }
            return
        }

        let text = inputText.isEmpty ? "openclaw.chat.photoprompt".localized : inputText
        messages.append(OpenClawChatMessage(role: "user", text: text, image: frame))
        flushPendingResponse()
        inputText = ""
        openClawService.sendChatMessage(text, image: frame)

        if needsStreamStop { await streamViewModel.stopSession() }
    }

    // MARK: - Voice (ASR)

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        guard let apiKey = APIKeyManager.shared.getAPIKey(for: .alibaba), !apiKey.isEmpty else {
            messages.append(OpenClawChatMessage(role: "assistant", text: "openclaw.chat.noapikey".localized, image: nil))
            return
        }

        asrText = ""
        asrPartial = ""
        let service = OpenClawASRService(apiKey: apiKey)
        self.asrService = service

        service.onPartialResult = { text in
            asrPartial = text
        }

        service.onFinalResult = { text in
            asrText += text
            asrPartial = ""
        }

        service.onError = { error in
            isListening = false
            print("[ASR] Error: \(error)")
        }

        service.start()
        isListening = true
    }

    private func stopListening() {
        asrService?.stop()
        asrService = nil
        isListening = false
        asrPartial = ""
        // Keep asrText for user to review & send
    }

    private func sendASRText() {
        let text = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(OpenClawChatMessage(role: "user", text: text, image: nil))
        flushPendingResponse()
        openClawService.sendChatMessage(text)
        asrText = ""
    }

    private func flushPendingResponse() {
        if !pendingResponse.isEmpty {
            messages.append(OpenClawChatMessage(role: "assistant", text: pendingResponse, image: nil))
            pendingResponse = ""
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: OpenClawChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 200, maxHeight: 150)
                        .cornerRadius(12)
                        .clipped()
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == "user"
                            ? AnyShapeStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color(.systemGray5))
                    )
                    .cornerRadius(18)
            }

            if message.role == "assistant" { Spacer(minLength: 60) }
        }
    }
}
