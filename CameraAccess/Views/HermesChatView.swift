/*
 * Hermes Chat View
 * Main interface for Hermes Agent voice interactions
 * Supports: voice commands, vision queries, text input, tool execution
 */

import SwiftUI

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
    @ObservedObject private var hermesService = HermesService.shared
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
                        ConnectionStatusIndicator(state: hermesService.connectionState)
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
            if hermesService.connectionState != .connected,
               !hermesService.serverHost.isEmpty {
                hermesService.connect()
            }
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
            if hermesService.connectionState != .connected {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(connectionStatusText)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(statusBannerColor.opacity(0.15))
            }
        }
    }

    private var connectionStatusText: String {
        switch hermesService.connectionState {
        case .connecting:
            return "Connecting to Hermes..."
        case .authenticating:
            return "Authenticating..."
        case .error(let message):
            return "Error: \(message)"
        default:
            return "Disconnected"
        }
    }

    private var statusBannerColor: Color {
        switch hermesService.connectionState {
        case .error:
            return .red
        default:
            return .orange
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
                WelcomeRow(icon: "hammer.fill", text: "Execute 80+ tools via voice")
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
                    .foregroundColor(isSending || !hermesService.connectionState.isConnected ? .gray : .purple)
                    .frame(width: 60, height: 60)
                }
                .disabled(isSending || !hermesService.connectionState.isConnected)

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
                .disabled(!hermesService.connectionState.isConnected)

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
                            .foregroundColor(inputText.isEmpty || !hermesService.connectionState.isConnected ? .gray : .purple)
                    }
                    .disabled(inputText.isEmpty || !hermesService.connectionState.isConnected)
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
        guard hermesService.connectionState.isConnected else { return }

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
        // For now, simulate voice input
        // TODO: Integrate with actual ASR service
        isListening = true
        asrText = ""
        asrPartial = ""

        // Simulated listening - replace with actual ASR
        Task {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            if isListening {
                asrText = "What am I looking at?"
                stopListening()
            }
        }
    }

    private func stopListening() {
        isListening = false
        asrPartial = ""
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
    func checkPermissionStatus(_ permission: Permission) async throws -> PermissionStatus { .granted }
    func requestPermission(_ permission: Permission) async throws -> PermissionStatus { .granted }
    func startDeviceScan() {}
    func stopDeviceScan() {}
}
