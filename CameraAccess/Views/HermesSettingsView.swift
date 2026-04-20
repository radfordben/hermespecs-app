/*
 * Hermes Settings View
 * Configure AI provider settings for HerMeSpecs
 */

import SwiftUI

struct HermesSettingsView: View {
    @ObservedObject private var aiService = HermesAIService.shared
    @ObservedObject private var router = HermesCommandRouter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: HermesAIProvider = .ollama
    @State private var selectedModel: String = ""
    @State private var serverHost: String = "localhost"
    @State private var serverPort: String = "11434"
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    @State private var availableModels: [String] = []

    var body: some View {
        NavigationView {
            Form {
                // MARK: - AI Provider
                Section(header: Text("AI Provider")) {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(HermesAIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) { _ in
                        updateProviderDefaults()
                    }
                }

                // MARK: - Model Selection
                Section(header: Text("Model")) {
                    if availableModels.count > 1 {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        TextField("Model name", text: $selectedModel)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    if selectedProvider == .ollama {
                        Button("Refresh Models") {
                            Task { await refreshModels() }
                        }
                    }
                }

                // MARK: - Ollama Host (only for Ollama)
                if selectedProvider == .ollama {
                    Section(header: Text("Ollama Server")) {
                        TextField("Host", text: $serverHost)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)

                        TextField("Port", text: $serverPort)
                            .keyboardType(.numberPad)
                    }
                }

                // MARK: - API Key (for cloud providers)
                if selectedProvider.requiresAPIKey {
                    Section(header: Text("API Key")) {
                        HStack {
                            if showAPIKey {
                                TextField("API Key", text: $apiKey)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("API Key", text: $apiKey)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }

                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }

                        if !apiKey.isEmpty {
                            Button("Clear API Key") {
                                apiKey = ""
                            }
                            .foregroundColor(.red)
                        }

                        Link(destination: URL(string: selectedProvider.apiKeyHelpURL)!) {
                            HStack {
                                Text("Get API Key")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }

                // MARK: - Test Connection
                Section {
                    Button(action: testConnection) {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isTestingConnection)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(testSuccess ? .green : .red)
                    }
                }

                // MARK: - Device Info
                Section(header: Text("Device")) {
                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(aiService.deviceId)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("Provider URL")
                        Spacer()
                        Text(aiService.baseURL)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                // MARK: - Recent Activity
                if !router.recentToolCalls.isEmpty {
                    Section(header: Text("Recent Activity")) {
                        ForEach(router.recentToolCalls.prefix(5), id: \.tool) { toolCall in
                            HStack {
                                Image(systemName: "hammer.fill")
                                    .foregroundColor(.purple)
                                Text(toolCall.tool)
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                }

                // MARK: - About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundColor(.gray)
                    }

                    Link(destination: URL(string: "https://github.com/radfordben/hermespecs-app")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("HerMeSpecs Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    // MARK: - Private Methods

    private func loadSettings() {
        selectedProvider = aiService.selectedProvider
        selectedModel = aiService.selectedModel
        serverHost = aiService.serverHost
        serverPort = String(aiService.serverPort)

        switch selectedProvider {
        case .openai:
            apiKey = APIKeyManager.shared.getOpenAIAPIKey() ?? ""
        case .anthropic:
            apiKey = APIKeyManager.shared.getAnthropicAPIKey() ?? ""
        case .alibaba:
            apiKey = APIKeyManager.shared.getAPIKey(for: .alibaba, endpoint: .beijing) ?? ""
        case .ollama:
            apiKey = ""
        }

        Task { await refreshModels() }
    }

    private func updateProviderDefaults() {
        selectedModel = selectedProvider.defaultChatModel
        apiKey = ""
        if selectedProvider == .ollama {
            serverHost = "localhost"
            serverPort = "11434"
        }
        Task { await refreshModels() }
    }

    private func refreshModels() async {
        if selectedProvider == .ollama {
            availableModels = await aiService.fetchAvailableModels()
            if !availableModels.contains(selectedModel) && !availableModels.isEmpty {
                selectedModel = availableModels[0]
            }
        } else {
            availableModels = [selectedProvider.defaultChatModel, selectedProvider.defaultVisionModel]
        }
    }

    private func saveSettings() {
        aiService.selectedProvider = selectedProvider
        aiService.selectedModel = selectedModel
        aiService.serverHost = serverHost
        aiService.serverPort = Int(serverPort) ?? 11434

        switch selectedProvider {
        case .openai:
            if !apiKey.isEmpty { _ = APIKeyManager.shared.saveOpenAIAPIKey(apiKey) }
        case .anthropic:
            if !apiKey.isEmpty { _ = APIKeyManager.shared.saveAnthropicAPIKey(apiKey) }
        case .alibaba:
            if !apiKey.isEmpty { _ = APIKeyManager.shared.saveAPIKey(apiKey, for: .alibaba, endpoint: .beijing) }
        case .ollama:
            break
        }

        aiService.saveSettings()
        aiService.connect()
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        // Temporarily apply settings
        let origProvider = aiService.selectedProvider
        let origModel = aiService.selectedModel
        aiService.selectedProvider = selectedProvider
        aiService.selectedModel = selectedModel
        aiService.serverHost = serverHost
        aiService.serverPort = Int(serverPort) ?? 11434

        Task {
            let success = await aiService.testConnection()

            await MainActor.run {
                isTestingConnection = false
                testSuccess = success
                testResult = success ? "Connection successful!" : "Connection failed. Check that Ollama is running."

                if !success {
                    // Restore original settings
                    aiService.selectedProvider = origProvider
                    aiService.selectedModel = origModel
                }
            }
        }
    }
}

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    let state: HermesConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .authenticating:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "Ready"
        case .connecting:
            return "Connecting"
        case .authenticating:
            return "Authenticating"
        case .disconnected:
            return "Not configured"
        case .error:
            return "Error"
        }
    }
}

// MARK: - Preview

struct HermesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HermesSettingsView()
    }
}