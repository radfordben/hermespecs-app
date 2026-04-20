/*
 * Hermes Chat View
 * Main interface for Hermes Agent voice interactions
 * Supports: voice commands, vision queries, text input, tool execution
 */

import SwiftUI
import Speech
import AVFoundation

struct HermesChatMessage: Identifiable {
    let id = UUID()
    let role: String  // "user", "assistant", "system", "tool"
    let text: String
    let image: UIImage?
    let toolCalls: [HermesToolCall]?
    let timestamp = Date()
}

struct HermesChatView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject private var aiService = HermesAIService.shared
    @ObservedObject private var router = HermesCommandRouter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [HermesChatMessage] = []
    @State private var inputText = ""
    @State private var pendingResponse = ""
    @State private var isSending = false
    @State private var isListening = false
    @State private var showTextInput = false
    @State private var showSettings = false

    // ASR Service for voice input
    @State private var asrText = ""
    @State private var asrPartial = ""

    // Speech recognition
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?
    @State private var hasSpeechPermission = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection status banner
                connectionStatusBanner

                // Messages list
                messagesList

                Divider()

                // Input area
                inputArea
            }
            .navigationTitle("HermeSpecs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        ConnectionStatusIndicator(state: aiService.connectionState)
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
        }
        .onAppear {
            setupCallbacks()
            router.setStreamViewModel(streamViewModel)
            if !aiService.hasAPIKeyConfigured && aiService.selectedProvider.requiresAPIKey {
                // Prompt user to configure API key
            }
            aiService.connect()
        }
        .onDisappear {
            cleanupCallbacks()
        }
        .sheet(isPresented: $showSettings) {
            HermesSettingsView()
        }
    }

    // MARK: - Connection Status Banner

    private var connectionStatusBanner: some View {
        Group {
            if !aiService.hasAPIKeyConfigured && aiService.selectedProvider.requiresAPIKey {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No API key — configure in Settings")
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
            } else if case .error(let message) = aiService.connectionState {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
            }
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Welcome message
                    if messages.isEmpty {
                        welcomeView
                    }

                    ForEach(messages) { msg in
                        HermesChatBubble(message: msg).id(msg.id)
                    }

                    // Pending response (streaming)
                    if !pendingResponse.isEmpty {
                        HermesChatBubble(message: HermesChatMessage(
                            role: "assistant",
                            text: pendingResponse,
                            image: nil,
                            toolCalls: nil
                        ))
                    }

                    // Tool execution indicator
                    if router.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: pendingResponse) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Welcome to HermeSpecs")
                .font(.title2)
                .fontWeight(.bold)

            Text("Voice-controlled AI for your Meta Ray-Ban Glasses")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                WelcomeRow(icon: "mic.fill", text: "Tap the mic and speak naturally")
                WelcomeRow(icon: "camera.fill", text: "Use camera for visual queries")
                WelcomeRow(icon: "hammer.fill", text: "Execute tools via voice")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 12) {
            // ASR transcription preview
            if isListening || !asrText.isEmpty {
                asrPreview
            }

            // Main action buttons
            HStack(spacing: 20) {
                // Camera button
                Button {
                    Task { await captureAndSend() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                        Text("Snap")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isSending || !aiService.hasAPIKeyConfigured ? .gray : .purple)
                    .frame(width: 60, height: 60)
                }
                .disabled(isSending || !aiService.hasAPIKeyConfigured)

                // Voice button
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
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 3)
                                .frame(width: 88, height: 88)
                                .scaleEffect(1.1)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isListening)
                        }

                        Image(systemName: isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: isListening ? 24 : 28))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!aiService.hasAPIKeyConfigured)

                // Text input toggle
                Button {
                    showTextInput.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 22))
                        Text("Type")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.purple)
                    .frame(width: 60, height: 60)
                }
            }
            .padding(.vertical, 4)

            // Text input bar
            if showTextInput {
                HStack(spacing: 10) {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { sendText() }

                    Button {
                        sendText()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(inputText.isEmpty || !aiService.hasAPIKeyConfigured ? .gray : .purple)
                    }
                    .disabled(inputText.isEmpty || !aiService.hasAPIKeyConfigured)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var asrPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayASRText)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)

            if !isListening && !asrText.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        asrText = ""
                        asrPartial = ""
                    } label: {
                        Text("Cancel")
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
                        Text("Send")
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

    private var displayASRText: String {
        if asrText.isEmpty && asrPartial.isEmpty {
            return isListening ? "Listening..." : ""
        }
        return asrText + (asrPartial.isEmpty ? "" : " \(asrPartial)")
    }

    // MARK: - Actions

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage(role: "user", text: text, image: nil)
        flushPendingResponse()
        inputText = ""

        Task {
            _ = await router.handleCommand(text, image: nil)
        }
    }

    private func captureAndSend() async {
        guard aiService.hasAPIKeyConfigured else { return }

        isSending = true
        defer { isSending = false }

        // Start streaming if needed
        let needsStreamStop = !streamViewModel.isStreaming
        if needsStreamStop {
            await streamViewModel.handleStartStreaming()

            // Wait for frame
            let deadline = Date().addingTimeInterval(5.0)
            while streamViewModel.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        guard let frame = streamViewModel.currentVideoFrame else {
            addMessage(role: "assistant", text: "Could not capture image from camera.", image: nil)
            if needsStreamStop { await streamViewModel.stopSession() }
            return
        }

        let text = inputText.isEmpty ? "What do you see?" : inputText
        addMessage(role: "user", text: text, image: frame)
        flushPendingResponse()
        inputText = ""

        _ = await router.handleCommand(text, image: frame)

        if needsStreamStop { await streamViewModel.stopSession() }
    }

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.asrText = "Speech recognition not authorized. Please enable in Settings."
                    self.isListening = false
                }
                return
            }
            DispatchQueue.main.async {
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        isListening = true
        asrText = ""
        asrPartial = ""

        // Stop any existing recording
        stopRecordingEngine()

        audioEngine = AVAudioEngine()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        guard let audioEngine = audioEngine,
              let speechRecognizer = speechRecognizer else {
            isListening = false
            return
        }

        let inputNode = audioEngine.inputNode
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            isListening = false
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                self.asrText = result.bestTranscription.formattedString
                if result.isFinal {
                    self.stopListening()
                }
            }
            if error != nil {
                self.stopListening()
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        // Auto-stop after 60 seconds
        Task {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            if self.isListening {
                self.stopListening()
            }
        }
    }

    private func stopListening() {
        isListening = false
        asrPartial = ""
        stopRecordingEngine()
    }

    private func stopRecordingEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
    }

    private func sendASRText() {
        let text = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage(role: "user", text: text, image: nil)
        flushPendingResponse()

        Task {
            _ = await router.handleCommand(text, image: nil)
        }

        asrText = ""
    }

    private func addMessage(role: String, text: String, image: UIImage?, toolCalls: [HermesToolCall]? = nil) {
        let message = HermesChatMessage(
            role: role,
            text: text,
            image: image,
            toolCalls: toolCalls
        )
        messages.append(message)
    }

    private func flushPendingResponse() {
        if !pendingResponse.isEmpty {
            addMessage(role: "assistant", text: pendingResponse, image: nil)
            pendingResponse = ""
        }
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        router.onResponseReady = { result in
            DispatchQueue.main.async {
                self.pendingResponse = ""
                self.addMessage(
                    role: "assistant",
                    text: result.message,
                    image: nil,
                    toolCalls: result.toolCalls
                )
            }
        }

        router.onToolExecuted = { toolCall, toolResult in
            print("[HermesChat] Tool executed: \(toolCall.tool) - \(toolResult.success)")
        }

        router.onError = { error in
            DispatchQueue.main.async {
                self.addMessage(
                    role: "assistant",
                    text: "Sorry, an error occurred: \(error.localizedDescription)",
                    image: nil
                )
            }
        }
    }

    private func cleanupCallbacks() {
        router.onResponseReady = nil
        router.onToolExecuted = nil
        router.onError = nil
    }
}

// MARK: - Welcome Row

private struct WelcomeRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Chat Bubble

private struct HermesChatBubble: View {
    let message: HermesChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                // Image if present
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 200, maxHeight: 150)
                        .cornerRadius(12)
                        .clipped()
                }

                // Text
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

                // Tool indicators
                if let tools = message.toolCalls, !tools.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                        Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                            .font(.caption2)
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 4)
                }
            }

            if message.role == "assistant" { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Preview

struct HermesChatView_Previews: PreviewProvider {
    static var previews: some View {
        HermesChatView(
            streamViewModel: StreamSessionViewModel(wearables: MockWearables())
        )
    }
}

// Simple mock for previews
private class MockWearables: WearablesInterface {
    var devices: [DeviceIdentifier] = []
    var registrationState: RegistrationState = .registered

    func checkPermissionStatus(_ permission: Permission) async throws -> PermissionStatus { .granted }
    func requestPermission(_ permission: Permission) async throws -> PermissionStatus { .granted }
    func startDeviceScan() {}
    func stopDeviceScan() {}
    func startRegistration() async throws {}
    func startUnregistration() async throws {}
    func deviceForIdentifier(_ identifier: DeviceIdentifier) -> WearableDeviceProtocol? { nil }
    func registrationStateStream() -> AsyncStream<RegistrationState> { AsyncStream { _ in } }
    func devicesStream() -> AsyncStream<[DeviceIdentifier]> { AsyncStream { _ in } }
}
