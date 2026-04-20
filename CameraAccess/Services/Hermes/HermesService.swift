/*
 * Hermes Service
 * AI assistant integration for Meta Ray-Ban Glasses
 * Communicates with Hermes Agent via WebSocket for voice commands and tool execution
 */

import Foundation
import UIKit
import Combine

// MARK: - Connection State

enum HermesConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case authenticating
    case error(String)

    static func == (lhs: HermesConnectionState, rhs: HermesConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.authenticating, .authenticating):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Hermes Models

struct HermesResponse: Codable {
    let message: String
    let toolCalls: [HermesToolCall]?
    let audioUrl: String?
    let visionAnalysis: HermesVisionAnalysis?
    let metadata: HermesResponseMetadata?
}

struct HermesToolCall: Codable {
    let tool: String
    let parameters: [String: AnyCodableValue]
    let result: HermesToolResult?
}

struct HermesToolResult: Codable {
    let success: Bool
    let message: String
    let data: [String: AnyCodableValue]?
    let error: String?
}

struct HermesVisionAnalysis: Codable {
    let description: String
    let objects: [String]?
    let text: String?
    let confidence: Double?
}

struct HermesResponseMetadata: Codable {
    let requestId: String
    let model: String
    let processingTime: Double?
    let tokensUsed: Int?
}

struct HermesCommandRequest: Codable {
    let type: String
    let id: String
    let command: String
    let context: HermesContext?
    let attachments: [HermesAttachment]?
    let timestamp: Int64
}

struct HermesContext: Codable {
    let sessionId: String
    let deviceId: String
    let location: HermesLocation?
    let previousCommands: [String]?
}

struct HermesLocation: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
}

// HermesAttachment is defined in HermesModels.swift

// MARK: - Protocol

protocol HermesServiceProtocol: AnyObject {
    var connectionState: HermesConnectionState { get }

    func connect()
    func disconnect()
    func sendCommand(_ command: String, completion: @escaping (Result<HermesResponse, Error>) -> Void)
    func sendVisionCommand(_ command: String, image: UIImage, completion: @escaping (Result<HermesResponse, Error>) -> Void)
    func sendAudioCommand(_ audioData: Data, completion: @escaping (Result<HermesResponse, Error>) -> Void)
}

// MARK: - Hermes Service

@MainActor
class HermesService: NSObject, ObservableObject, HermesServiceProtocol {
    static let shared = HermesService()

    // MARK: - Published State

    @Published var connectionState: HermesConnectionState = .disconnected
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "hermes_enabled")
    @Published var serverHost = UserDefaults.standard.string(forKey: "hermes_host") ?? "localhost"
    @Published var serverPort = UserDefaults.standard.integer(forKey: "hermes_port").nonZeroOrDefault(8787)
    @Published var useSecureConnection = UserDefaults.standard.bool(forKey: "hermes_secure")
    @Published var currentSessionId = UserDefaults.standard.string(forKey: "hermes_session_id") ?? UUID().uuidString

    // MARK: - Callbacks

    var onResponse: ((HermesResponse) -> Void)?
    var onError: ((Error) -> Void)?
    var onToolExecution: ((HermesToolCall) -> Void)?
    var onConnectionStateChange: ((HermesConnectionState) -> Void)?

    // MARK: - Private Properties

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var pendingRequests: [String: (Result<HermesResponse, Error>) -> Void] = [:]

    let deviceId: String
    private var shouldReconnect = false
    private var reconnectAttempts = 0

    // Configuration
    private static let protocolVersion = "1.0"
    private static let pingInterval: TimeInterval = 30
    private static let maxReconnectAttempts = 5
    private static let reconnectDelayBase: TimeInterval = 2.0

    // Keychain
    private let keychainService = "com.hermespecs.app"
    private let keychainAccountToken = "api_token"
    private let keychainAccountRefreshToken = "refresh_token"

    // MARK: - Init

    private override init() {
        // Generate stable device ID
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.deviceId = "hermespecs-\(deviceId.prefix(8))".lowercased()
        super.init()

        // Save session ID if new
        UserDefaults.standard.set(currentSessionId, forKey: "hermes_session_id")
    }

    // MARK: - Public Methods

    func connect() {
        guard !connectionState.isConnected && connectionState != .connecting else {
            print("[Hermes] Already connected or connecting")
            return
        }

        shouldReconnect = true
        saveSettings()
        startConnection()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil

        // Cancel all pending requests
        pendingRequests.values.forEach { completion in
            completion(.failure(HermesError.connectionClosed))
        }
        pendingRequests.removeAll()

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        connectionState = .disconnected
        print("[Hermes] Disconnected")
    }

    func sendCommand(_ command: String, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        guard connectionState.isConnected else {
            completion(.failure(HermesError.notConnected))
            return
        }

        let requestId = UUID().uuidString
        let request = HermesCommandRequest(
            type: "command",
            id: requestId,
            command: command,
            context: createContext(),
            attachments: nil,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )

        pendingRequests[requestId] = completion
        sendRequest(request)

        // Set timeout
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
            if let _ = self?.pendingRequests.removeValue(forKey: requestId) {
                completion(.failure(HermesError.timeout))
            }
        }
    }

    func sendVisionCommand(_ command: String, image: UIImage, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        guard connectionState.isConnected else {
            completion(.failure(HermesError.notConnected))
            return
        }

        // Resize and compress image for transmission
        let resizedImage = resizeImage(image, maxDimension: 1920)
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.85) else {
            completion(.failure(HermesError.imageEncodingFailed))
            return
        }

        let attachment = HermesAttachment(
            type: "image",
            mimeType: "image/jpeg",
            data: jpegData.base64EncodedString(),
            filename: nil,
            dimensions: ImageDimensions(width: resizedImage.size.width, height: resizedImage.size.height)
        )

        let requestId = UUID().uuidString
        let request = HermesCommandRequest(
            type: "vision_command",
            id: requestId,
            command: command,
            context: createContext(),
            attachments: [attachment],
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )

        pendingRequests[requestId] = completion
        sendRequest(request)
        print("[Hermes] Sent vision command: \(command.prefix(50))... with image \(jpegData.count) bytes")

        // Set timeout
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45 * 1_000_000_000) // 45 seconds for vision
            if let _ = self?.pendingRequests.removeValue(forKey: requestId) {
                completion(.failure(HermesError.timeout))
            }
        }
    }

    func sendAudioCommand(_ audioData: Data, completion: @escaping (Result<HermesResponse, Error>) -> Void) {
        guard connectionState.isConnected else {
            completion(.failure(HermesError.notConnected))
            return
        }

        let attachment = HermesAttachment(
            type: "audio",
            mimeType: "audio/pcm",
            data: audioData.base64EncodedString(),
            filename: nil,
            dimensions: nil
        )

        let requestId = UUID().uuidString
        let request = HermesCommandRequest(
            type: "audio_command",
            id: requestId,
            command: "",  // Audio contains the command
            context: createContext(),
            attachments: [attachment],
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )

        pendingRequests[requestId] = completion
        sendRequest(request)

        // Set timeout
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            if let _ = self?.pendingRequests.removeValue(forKey: requestId) {
                completion(.failure(HermesError.timeout))
            }
        }
    }

    // MARK: - Settings Management

    func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "hermes_enabled")
        UserDefaults.standard.set(serverHost, forKey: "hermes_host")
        UserDefaults.standard.set(serverPort, forKey: "hermes_port")
        UserDefaults.standard.set(useSecureConnection, forKey: "hermes_secure")
    }

    func saveAPIToken(_ token: String) {
        let data = token.data(using: .utf8) ?? Data()
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccountToken
        ] as CFDictionary)

        guard !token.isEmpty else { return }
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccountToken,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as CFDictionary, nil)
    }

    func loadAPIToken() -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccountToken,
            kSecReturnData: true
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private Methods

    private func startConnection() {
        DispatchQueue.main.async { self.connectionState = .connecting }

        let scheme = useSecureConnection ? "wss" : "ws"
        var urlString = "\(scheme)://\(serverHost):\(serverPort)/v1/ws"

        // Add authentication token if available
        if let token = loadAPIToken(), !token.isEmpty {
            urlString += "?token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"
        }

        guard let url = URL(string: urlString) else {
            connectionState = .error("Invalid server URL")
            return
        }

        print("[Hermes] Connecting to \(scheme)://\(serverHost):\(serverPort)...")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.connectionProxyDictionary = [:]  // Bypass proxy for local connections

        let delegateQueue = OperationQueue()
        delegateQueue.name = "hermes-ws"

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.maximumMessageSize = 16 * 1024 * 1024  // 16MB max message
        webSocket?.resume()
    }

    private func createContext() -> HermesContext {
        return HermesContext(
            sessionId: currentSessionId,
            deviceId: deviceId,
            location: nil,  // TODO: Add location if user permits
            previousCommands: nil
        )
    }

    private func sendRequest(_ request: HermesCommandRequest) {
        guard let data = try? JSONEncoder().encode(request),
              let text = String(data: data, encoding: .utf8) else {
            print("[Hermes] Failed to encode request")
            return
        }

        webSocket?.send(.string(text)) { error in
            if let error {
                print("[Hermes] Send error: \(error.localizedDescription)")
            }
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()  // Continue receiving
            case .failure(let error):
                print("[Hermes] Receive error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[Hermes] Failed to parse message: \(text.prefix(200))")
            return
        }

        let type = json["type"] as? String

        switch type {
        case "connected":
            handleConnected(json: json)
        case "response":
            handleResponse(json: json)
        case "error":
            handleErrorResponse(json: json)
        case "tool_execution":
            handleToolExecution(json: json)
        case "ping":
            sendPong()
        default:
            print("[Hermes] Unknown message type: \(type ?? "nil")")
        }
    }

    private func handleConnected(json: [String: Any]) {
        print("[Hermes] Connected to server")
        DispatchQueue.main.async {
            self.connectionState = .connected
            self.reconnectAttempts = 0
        }
        startPingWatchdog()
    }

    private func handleResponse(json: [String: Any]) {
        guard let requestId = json["request_id"] as? String,
              let completion = pendingRequests.removeValue(forKey: requestId) else {
            // Response for unknown request or server-initiated message
            if let response = parseResponse(json) {
                DispatchQueue.main.async {
                    self.onResponse?(response)
                }
            }
            return
        }

        if let error = json["error"] as? [String: Any] {
            let errorMessage = error["message"] as? String ?? "Unknown error"
            completion(.failure(HermesError.serverError(errorMessage)))
            return
        }

        if let response = parseResponse(json) {
            completion(.success(response))
        } else {
            completion(.failure(HermesError.invalidResponse))
        }
    }

    private func handleErrorResponse(json: [String: Any]) {
        let errorMessage = json["message"] as? String ?? "Unknown error"
        let code = json["code"] as? String

        print("[Hermes] Server error: \(code ?? "unknown") - \(errorMessage)")

        DispatchQueue.main.async {
            self.onError?(HermesError.serverError(errorMessage))

            if code == "AUTHENTICATION_FAILED" {
                self.connectionState = .error("Authentication failed")
            }
        }
    }

    private func handleToolExecution(json: [String: Any]) {
        guard let tool = json["tool"] as? String else { return }

        let toolCall = HermesToolCall(
            tool: tool,
            parameters: (json["parameters"] as? [String: Any])?.mapValues { AnyCodableValue.from($0) } ?? [:],
            result: nil
        )

        DispatchQueue.main.async {
            self.onToolExecution?(toolCall)
        }
    }

    private func parseResponse(_ json: [String: Any]) -> HermesResponse? {
        guard let message = json["message"] as? String else { return nil }

        let toolCalls: [HermesToolCall]? = (json["tool_calls"] as? [[String: Any]])?.compactMap { toolJson in
            guard let tool = toolJson["tool"] as? String else { return nil }
            return HermesToolCall(
                tool: tool,
                parameters: (toolJson["parameters"] as? [String: Any])?.mapValues { AnyCodableValue.from($0) } ?? [:],
                result: nil
            )
        }

        let visionAnalysis: HermesVisionAnalysis? = (json["vision_analysis"] as? [String: Any]).flatMap { vaJson in
            HermesVisionAnalysis(
                description: vaJson["description"] as? String ?? "",
                objects: vaJson["objects"] as? [String],
                text: vaJson["text"] as? String,
                confidence: vaJson["confidence"] as? Double
            )
        }

        let metadata: HermesResponseMetadata? = (json["metadata"] as? [String: Any]).flatMap { meta in
            HermesResponseMetadata(
                requestId: meta["request_id"] as? String ?? "",
                model: meta["model"] as? String ?? "",
                processingTime: meta["processing_time"] as? Double,
                tokensUsed: meta["tokens_used"] as? Int
            )
        }

        return HermesResponse(
            message: message,
            toolCalls: toolCalls,
            audioUrl: json["audio_url"] as? String,
            visionAnalysis: visionAnalysis,
            metadata: metadata
        )
    }

    private func sendPong() {
        let pong: [String: Any] = [
            "type": "pong",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sendJSON(pong)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(text)) { error in
            if let error {
                print("[Hermes] Send JSON error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Keepalive

    private func startPingWatchdog() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Send ping
                self?.sendJSON([
                    "type": "ping",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        guard connectionState != .disconnected else { return }

        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        pingTask?.cancel()

        // Notify pending requests
        let error = HermesError.connectionClosed
        pendingRequests.values.forEach { $0(.failure(error)) }
        pendingRequests.removeAll()

        guard shouldReconnect else {
            connectionState = .disconnected
            return
        }

        reconnectAttempts += 1
        if reconnectAttempts > Self.maxReconnectAttempts {
            print("[Hermes] Max reconnect attempts reached")
            connectionState = .error("Connection lost. Max retries reached.")
            shouldReconnect = false
            return
        }

        let delay = min(Self.reconnectDelayBase * pow(2.0, Double(reconnectAttempts - 1)), 60.0)
        print("[Hermes] Reconnect attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts) in \(delay)s")
        connectionState = .disconnected
        scheduleReconnect(delay: delay)
    }

    private func scheduleReconnect(delay: TimeInterval) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            Task { @MainActor [weak self] in
                guard let self, self.shouldReconnect else { return }
                self.startConnection()
            }
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

// MARK: - URLSessionWebSocketDelegate

extension HermesService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[Hermes] WebSocket opened")
        // Start receiving
        Task { @MainActor [weak self] in
            self?.receiveMessage()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[Hermes] WebSocket closed: \(closeCode.rawValue)")
        Task { @MainActor [weak self] in
            self?.handleDisconnect()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            print("[Hermes] Connection error: \(error.localizedDescription)")
            Task { @MainActor [weak self] in
                self?.connectionState = .error(error.localizedDescription)
                self?.handleDisconnect()
            }
        }
    }
}

// MARK: - Errors

enum HermesError: LocalizedError {
    case notConnected
    case connectionClosed
    case timeout
    case serverError(String)
    case invalidResponse
    case imageEncodingFailed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Hermes server"
        case .connectionClosed:
            return "Connection to Hermes server closed"
        case .timeout:
            return "Request timed out"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ defaultValue: Int) -> Int {
        return self != 0 ? self : defaultValue
    }
}
