/*
 * Hermes AI Service
 * Direct AI API integration replacing WebSocket-based Hermes Agent
 * Uses Ollama (OpenAI-compatible API) for text and vision commands
 */

import Foundation
import UIKit
import Combine

// MARK: - AI Provider Enum

enum HermesAIProvider: String, CaseIterable, Codable {
    case ollama = "ollama"
    case openai = "openai"
    case anthropic = "anthropic"
    case alibaba = "alibaba"

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .alibaba: return "Alibaba Dashscope"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .alibaba: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    var defaultChatModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .alibaba: return "qwen3-vl-plus"
        }
    }

    var defaultVisionModel: String {
        switch self {
        case .ollama: return "llava"
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .alibaba: return "qwen3-vl-plus"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        case .openai, .anthropic, .alibaba: return true
        }
    }

    var apiKeyHelpURL: String {
        switch self {
        case .ollama: return "https://ollama.ai"
        case .openai: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .alibaba: return "https://help.aliyun.com/zh/model-studio/get-api-key"
        }
    }
}

// MARK: - Hermes AI Service

@MainActor
class HermesAIService: ObservableObject, HermesServiceProtocol {
    static let shared = HermesAIService()

    // MARK: - Published State

    @Published var connectionState: HermesConnectionState = .disconnected
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "hermes_enabled")
    @Published var selectedProvider: HermesAIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "hermes_ai_provider")
            if oldValue != selectedProvider {
                selectedModel = selectedProvider.defaultChatModel
                updateConnectionState()
            }
        }
    }
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "hermes_ai_model")
        }
    }
    @Published var serverHost: String {
        didSet {
            UserDefaults.standard.set(serverHost, forKey: "hermes_host")
        }
    }
    @Published var serverPort: Int {
        didSet {
            UserDefaults.standard.set(serverPort, forKey: "hermes_port")
        }
    }

    let deviceId: String

    // MARK: - Callbacks

    var onResponse: ((HermesResponse) -> Void)?
    var onError: ((Error) -> Void)?
    var onToolExecution: ((HermesToolCall) -> Void)?
    var onConnectionStateChange: ((HermesConnectionState) -> Void)?

    // MARK: - Private

    private var urlSession: URLSession
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - System Prompt

    private let systemPrompt = """
    You are HermeSpecs, an AI assistant running on Meta Ray-Ban smart glasses. You help the user with:
    - Visual queries (describing scenes, reading text, identifying objects)
    - On-device tools (reminders, notes, timers, messages, music control)
    - General questions and conversation

    Keep responses concise and voice-friendly. When the user asks you to use a tool, respond with a JSON tool call if applicable. Otherwise, respond naturally.
    """

    // MARK: - Init

    private override init() {
        let savedProvider = HermesAIProvider(rawValue: UserDefaults.standard.string(forKey: "hermes_ai_provider") ?? "") ?? .ollama
        self.selectedProvider = savedProvider
        self.selectedModel = UserDefaults.standard.string(forKey: "hermes_ai_model") ?? savedProvider.defaultChatModel
        self.serverHost = UserDefaults.standard.string(forKey: "hermes_host") ?? "localhost"
        self.serverPort = UserDefaults.standard.integer(forKey: "hermes_port") != 0 ? UserDefaults.standard.integer(forKey: "hermes_port") : 11434
        self.deviceId = "hermespecs-\(UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "unknown")".lowercased()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.urlSession = URLSession(configuration: config)

        super.init()

        updateConnectionState()
    }

    // MARK: - Connection State

    private func updateConnectionState() {
        if hasAPIKeyConfigured {
            connectionState = .connected
        } else if selectedProvider.requiresAPIKey {
            connectionState = .error("No API key configured for \(selectedProvider.displayName)")
        } else {
            // Ollama doesn't need a key, check if server is reachable later
            connectionState = .connected
        }
    }

    var hasAPIKeyConfigured: Bool {
        if !selectedProvider.requiresAPIKey {
            return true
        }
        return getAPIKey() != nil
    }

    private func getAPIKey() -> String? {
        switch selectedProvider {
        case .ollama:
            return nil
        case .openai:
            return APIKeyManager.shared.getOpenAIAPIKey()
        case .anthropic:
            return APIKeyManager.shared.getAnthropicAPIKey()
        case .alibaba:
            return APIKeyManager.shared.getAPIKey(for: .alibaba, endpoint: .beijing)
        }
    }

    var baseURL: String {
        switch selectedProvider {
        case .ollama:
            let port = serverPort != 0 ? serverPort : 11434
            return "http://\(serverHost):\(port)/v1"
        case .openai:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .alibaba:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    // MARK: - HermesServiceProtocol

    func connect() {
        updateConnectionState()
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func sendCommand(_ command: String, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        guard hasAPIKeyConfigured else {
            completion(.failure(HermesError.authenticationFailed))
            return
        }

        Task {
            do {
                let response = try await sendChatCommand(command, image: nil)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func sendVisionCommand(_ command: String, image: UIImage, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        guard hasAPIKeyConfigured else {
            completion(.failure(HermesError.authenticationFailed))
            return
        }

        Task {
            do {
                let response = try await sendChatCommand(command, image: image)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func sendAudioCommand(_ audioData: Data, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        // Audio commands are not directly supported by Ollama/OpenAI chat APIs.
        // For now, return an error suggesting text input instead.
        completion(.failure(HermesError.serverError("Audio commands require a speech-to-text service. Please use text or voice input instead.")))
    }

    // MARK: - Settings

    func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "hermes_enabled")
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "hermes_ai_provider")
        UserDefaults.standard.set(selectedModel, forKey: "hermes_ai_model")
        UserDefaults.standard.set(serverHost, forKey: "hermes_host")
        UserDefaults.standard.set(serverPort, forKey: "hermes_port")
    }

    // MARK: - Chat API Call

    private func sendChatCommand(_ command: String, image: UIImage?) async throws -> HermesResponse {
        let url = URL(string: "\(baseURL)/chat/completions")!

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        if let image = image {
            let visionContent = buildVisionContent(command, image: image)
            messages.append(["role": "user", "content": visionContent])
        } else {
            messages.append(["role": "user", "content": command])
        }

        var requestBody: [String: Any] = [
            "model": selectedModel,
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.7
        ]

        // Ollama doesn't support stream:false in the same way, but the OpenAI-compatible endpoint does
        if selectedProvider == .ollama {
            requestBody["stream"] = false
        } else {
            requestBody["stream"] = false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set auth header based on provider
        switch selectedProvider {
        case .ollama:
            break // No auth needed
        case .openai:
            if let key = getAPIKey() {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            if let key = getAPIKey() {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        case .alibaba:
            if let key = getAPIKey() {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }

        // Anthropic uses a different endpoint format
        if selectedProvider == .anthropic {
            return try await sendAnthropicCommand(command: command, image: image)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HermesError.serverError("API error (\(httpResponse.statusCode)): \(body.prefix(200))")
        }

        return try parseChatResponse(data)
    }

    // MARK: - Anthropic-specific API Call

    private func sendAnthropicCommand(command: String, image: UIImage?) async throws -> HermesResponse {
        let url = URL(string: "\(baseURL)/messages")!

        var content: [[String: Any]] = []

        if let image = image {
            guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
                throw HermesError.imageEncodingFailed
            }
            let base64Image = jpegData.base64EncodedString()

            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
            content.append(["type": "text", "text": command])
        } else {
            content.append(["type": "text", "text": command])
        }

        var requestBody: [String: Any] = [
            "model": selectedModel,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = getAPIKey() {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HermesError.serverError("Anthropic API error (\(httpResponse.statusCode)): \(body.prefix(200))")
        }

        return try parseAnthropicResponse(data)
    }

    // MARK: - Vision Content Builder (OpenAI format)

    private func buildVisionContent(_ command: String, image: UIImage) -> [[String: Any]] {
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            return [["type": "text", "text": command]]
        }

        let base64Image = jpegData.base64EncodedString()
        let resized = resizeImage(image, maxDimension: 1920)
        let resizedData = resized.jpegData(compressionQuality: 0.85)?.base64EncodedString() ?? base64Image

        return [
            [
                "type": "text",
                "text": command
            ],
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(resizedData)"
                ]
            ]
        ]
    }

    // MARK: - Response Parsing

    private func parseChatResponse(_ data: Data) throws -> HermesResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw HermesError.invalidResponse
        }

        // Check for tool calls in the response
        var toolCalls: [HermesToolCall]?
        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            toolCalls = rawToolCalls.compactMap { tc -> HermesToolCall? in
                guard let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                let arguments = (function["arguments"] as? [String: Any])?.mapValues { AnyCodableValue.from($0) } ?? [:]
                return HermesToolCall(tool: name, parameters: arguments, result: nil)
            }
        }

        return HermesResponse(
            message: content,
            toolCalls: toolCalls,
            audioUrl: nil,
            visionAnalysis: nil,
            metadata: HermesResponseMetadata(
                requestId: json["id"] as? String ?? "",
                model: json["model"] as? String ?? selectedModel,
                processingTime: nil,
                tokensUsed: (json["usage"] as? [String: Any])?["total_tokens"] as? Int
            )
        )
    }

    private func parseAnthropicResponse(_ data: Data) throws -> HermesResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]] else {
            throw HermesError.invalidResponse
        }

        var messageText = ""
        var toolCalls: [HermesToolCall]?

        for block in contentArray {
            if let type = block["type"] as? String {
                if type == "text", let text = block["text"] as? String {
                    messageText += text
                } else if type == "tool_use",
                          let name = block["name"] as? String,
                          let input = block["input"] as? [String: Any] {
                    if toolCalls == nil { toolCalls = [] }
                    toolCalls!.append(HermesToolCall(
                        tool: name,
                        parameters: input.mapValues { AnyCodableValue.from($0) },
                        result: nil
                    ))
                }
            }
        }

        return HermesResponse(
            message: messageText,
            toolCalls: toolCalls,
            audioUrl: nil,
            visionAnalysis: nil,
            metadata: HermesResponseMetadata(
                requestId: json["id"] as? String ?? "",
                model: json["model"] as? String ?? selectedModel,
                processingTime: nil,
                tokensUsed: (json["usage"] as? [String: Any])?["output_tokens"] as? Int
            )
        )
    }

    // MARK: - Test Connection

    func testConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        switch selectedProvider {
        case .ollama:
            break
        case .openai, .alibaba:
            if let key = getAPIKey() {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            if let key = getAPIKey() {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }

        do {
            let (_, response) = try await urlSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Fetch Available Models (Ollama)

    func fetchAvailableModels() async -> [String] {
        guard selectedProvider == .ollama else {
            return [selectedProvider.defaultChatModel]
        }

        guard let url = URL(string: "\(baseURL)/models") else { return [selectedModel] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [selectedModel] }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                return [selectedModel]
            }

            return models.compactMap { $0["id"] as? String }.sorted()
        } catch {
            return [selectedModel]
        }
    }

    // MARK: - Image Processing

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}

// MARK: - APIKeyManager Extension for OpenAI/Anthropic

extension APIKeyManager {
    private var openaiAccount: String { "openai-api-key" }
    private var anthropicAccount: String { "anthropic-api-key" }

    func saveOpenAIAPIKey(_ key: String) -> Bool {
        return saveKey(key, for: openaiAccount)
    }

    func getOpenAIAPIKey() -> String? {
        return getKey(for: openaiAccount)
    }

    func deleteOpenAIAPIKey() -> Bool {
        return deleteKey(for: openaiAccount)
    }

    func hasOpenAIAPIKey() -> Bool {
        return getOpenAIAPIKey() != nil
    }

    func saveAnthropicAPIKey(_ key: String) -> Bool {
        return saveKey(key, for: anthropicAccount)
    }

    func getAnthropicAPIKey() -> String? {
        return getKey(for: anthropicAccount)
    }

    func deleteAnthropicAPIKey() -> Bool {
        return deleteKey(for: anthropicAccount)
    }

    func hasAnthropicAPIKey() -> Bool {
        return getAnthropicAPIKey() != nil
    }
}