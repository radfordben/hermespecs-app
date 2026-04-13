/*
 * Hermes Command Router
 * Routes voice commands and tool executions between glasses and Hermes Agent
 * Handles: camera capture, tool execution, response formatting
 */

import Foundation
import UIKit
import Combine

// MARK: - Router Protocol

protocol HermesCommandRouterProtocol: AnyObject {
    func handleCommand(_ command: String, image: UIImage?) async -> HermesRouterResult
    func handleToolExecution(_ toolCall: HermesToolCall) async -> HermesToolResult
    func executeLocalTool(_ tool: String, parameters: [String: AnyCodableValue]) async -> Result<Any, Error>
}

// MARK: - Router Result Types

struct HermesRouterResult {
    let success: Bool
    let message: String
    let toolCalls: [HermesToolCall]
    let shouldSpeak: Bool
    let audioData: Data?
    let visualFeedback: HermesVisualFeedback?
}

struct HermesVisualFeedback {
    let type: String  // "text", "image", "card", "list"
    let content: String
    let image: UIImage?
    let actions: [HermesAction]?
}

struct HermesAction {
    let label: String
    let action: String
    let parameters: [String: AnyCodableValue]?
}

// MARK: - Hermes Command Router

@MainActor
class HermesCommandRouter: NSObject, ObservableObject, HermesCommandRouterProtocol {
    static let shared = HermesCommandRouter()

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var lastCommand: String?
    @Published var lastResponse: String?
    @Published var recentToolCalls: [HermesToolCall] = []

    // MARK: - Dependencies

    private let hermesService: HermesService
    private let ttsService: TTSService
    private weak var streamViewModel: StreamSessionViewModel?

    // MARK: - Callbacks

    var onCommandReceived: ((String) -> Void)?
    var onResponseReady: ((HermesRouterResult) -> Void)?
    var onToolExecuted: ((HermesToolCall, HermesToolResult) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Init

    init(hermesService: HermesService = .shared,
         ttsService: TTSService = .shared) {
        self.hermesService = hermesService
        self.ttsService = ttsService
        super.init()

        setupServiceCallbacks()
    }

    func setStreamViewModel(_ viewModel: StreamSessionViewModel) {
        self.streamViewModel = viewModel
    }

    // MARK: - Public Methods

    /// Handle a voice/text command with optional vision context
    func handleCommand(_ command: String, image: UIImage? = nil) async -> HermesRouterResult {
        DispatchQueue.main.async { self.isProcessing = true }
        defer { DispatchQueue.main.async { self.isProcessing = false } }

        lastCommand = command
        onCommandReceived?(command)

        // Check connection
        guard hermesService.connectionState.isConnected else {
            let result = HermesRouterResult(
                success: false,
                message: "Not connected to Hermes. Please check your connection.",
                toolCalls: [],
                shouldSpeak: true,
                audioData: nil,
                visualFeedback: nil
            )
            await speakResult(result)
            return result
        }

        // Send to Hermes
        let responseResult: Result<HermesResponse, Error>
        if let image = image {
            responseResult = await withCheckedContinuation { continuation in
                hermesService.sendVisionCommand(command, image: image) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            responseResult = await withCheckedContinuation { continuation in
                hermesService.sendCommand(command) { result in
                    continuation.resume(returning: result)
                }
            }
        }

        // Process response
        switch responseResult {
        case .success(let response):
            let result = await processResponse(response, originalCommand: command)
            lastResponse = result.message
            onResponseReady?(result)
            await speakResult(result)
            return result

        case .failure(let error):
            let errorMessage = "Sorry, I encountered an error: \(error.localizedDescription)"
            let result = HermesRouterResult(
                success: false,
                message: errorMessage,
                toolCalls: [],
                shouldSpeak: true,
                audioData: nil,
                visualFeedback: nil
            )
            onError?(error)
            await speakResult(result)
            return result
        }
    }

    /// Execute a quick camera capture command
    func handleCameraCommand(_ command: String = "What do you see?") async -> HermesRouterResult {
        guard let viewModel = streamViewModel else {
            return HermesRouterResult(
                success: false,
                message: "Camera not available",
                toolCalls: [],
                shouldSpeak: true,
                audioData: nil,
                visualFeedback: nil
            )
        }

        // Start streaming if needed
        let needsStreamStop = !viewModel.isStreaming
        if needsStreamStop {
            await viewModel.handleStartStreaming()

            // Wait for frame
            let deadline = Date().addingTimeInterval(5.0)
            while viewModel.currentVideoFrame == nil && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        guard let frame = viewModel.currentVideoFrame else {
            if needsStreamStop { await viewModel.stopSession() }
            return HermesRouterResult(
                success: false,
                message: "Could not capture image from camera",
                toolCalls: [],
                shouldSpeak: true,
                audioData: nil,
                visualFeedback: nil
            )
        }

        let result = await handleCommand(command, image: frame)

        if needsStreamStop { await viewModel.stopSession() }

        return result
    }

    /// Handle tool execution from Hermes
    func handleToolExecution(_ toolCall: HermesToolCall) async -> HermesToolResult {
        print("[HermesRouter] Executing tool: \(toolCall.tool)")

        // Track recent tool calls
        DispatchQueue.main.async {
            self.recentToolCalls.append(toolCall)
            if self.recentToolCalls.count > 10 {
                self.recentToolCalls.removeFirst()
            }
        }

        // Execute local tool if applicable
        let localResult = await executeLocalTool(toolCall.tool, parameters: toolCall.parameters)

        let toolResult: HermesToolResult
        switch localResult {
        case .success(let data):
            toolResult = HermesToolResult(
                success: true,
                message: "Tool executed successfully",
                data: ["result": AnyCodableValue.from(data)]
            )
        case .failure(let error):
            toolResult = HermesToolResult(
                success: false,
                message: error.localizedDescription,
                data: nil
            )
        }

        onToolExecuted?(toolCall, toolResult)
        return toolResult
    }

    /// Execute a tool locally on the device
    func executeLocalTool(_ tool: String, parameters: [String: AnyCodableValue]) async -> Result<Any, Error> {
        switch tool {
        case "camera.capture":
            return await executeCameraCapture(parameters)

        case "device.info":
            return .success(HermesDeviceInfo.current)

        case "device.status":
            return await executeDeviceStatus(parameters)

        case "settings.get":
            return executeSettingsGet(parameters)

        case "settings.set":
            return executeSettingsSet(parameters)

        default:
            return .failure(HermesRouterError.unsupportedTool(tool))
        }
    }

    /// Cancel current operation
    func cancel() {
        isProcessing = false
        ttsService.stop()
    }

    // MARK: - Private Methods

    private func setupServiceCallbacks() {
        hermesService.onToolExecution = { [weak self] toolCall in
            Task { @MainActor [weak self] in
                _ = await self?.handleToolExecution(toolCall)
            }
        }

        hermesService.onError = { [weak self] error in
            self?.onError?(error)
        }
    }

    private func processResponse(_ response: HermesResponse, originalCommand: String) async -> HermesRouterResult {
        // Process tool calls if any
        var toolResults: [HermesToolCall] = []
        if let toolCalls = response.toolCalls {
            for toolCall in toolCalls {
                let result = await handleToolExecution(toolCall)
                toolResults.append(toolCall)
                print("[HermesRouter] Tool \(toolCall.tool) executed: \(result.success)")
            }
        }

        // Build visual feedback
        var visualFeedback: HermesVisualFeedback?
        if let visionAnalysis = response.visionAnalysis {
            visualFeedback = HermesVisualFeedback(
                type: "vision_analysis",
                content: visionAnalysis.description,
                image: nil,
                actions: nil
            )
        }

        return HermesRouterResult(
            success: true,
            message: response.message,
            toolCalls: toolResults,
            shouldSpeak: true,
            audioData: nil,  // TODO: Handle audio URL if provided
            visualFeedback: visualFeedback
        )
    }

    private func speakResult(_ result: HermesRouterResult) async {
        guard result.shouldSpeak && !result.message.isEmpty else { return }

        // Use TTSService for voice output
        ttsService.speak(result.message)
    }

    // MARK: - Local Tool Handlers

    private func executeCameraCapture(_ parameters: [String: AnyCodableValue]) async -> Result<Any, Error> {
        guard let viewModel = streamViewModel else {
            return .failure(HermesRouterError.cameraNotAvailable)
        }

        // Capture current frame
        guard let frame = viewModel.currentVideoFrame else {
            return .failure(HermesRouterError.noVideoFrame)
        }

        // Compress image
        guard let jpegData = frame.jpegData(compressionQuality: 0.8) else {
            return .failure(HermesRouterError.imageEncodingFailed)
        }

        return .success([
            "format": "jpeg",
            "data": jpegData.base64EncodedString(),
            "width": Int(frame.size.width),
            "height": Int(frame.size.height)
        ])
    }

    private func executeDeviceStatus(_ parameters: [String: AnyCodableValue]) async -> Result<Any, Error> {
        guard let viewModel = streamViewModel else {
            return .failure(HermesRouterError.cameraNotAvailable)
        }

        let status: [String: Any] = [
            "deviceConnected": viewModel.hasActiveDevice,
            "isStreaming": viewModel.isStreaming,
            "hasVideoFrame": viewModel.currentVideoFrame != nil,
            "connectionState": "\(hermesService.connectionState)"
        ]

        return .success(status)
    }

    private func executeSettingsGet(_ parameters: [String: AnyCodableValue]) -> Result<Any, Error> {
        guard let key = parameters["key"]?.stringValue else {
            return .failure(HermesRouterError.missingParameter("key"))
        }

        let value = UserDefaults.standard.object(forKey: key)
        return .success(value ?? NSNull())
    }

    private func executeSettingsSet(_ parameters: [String: AnyCodableValue]) -> Result<Any, Error> {
        guard let key = parameters["key"]?.stringValue else {
            return .failure(HermesRouterError.missingParameter("key"))
        }

        guard let value = parameters["value"] else {
            return .failure(HermesRouterError.missingParameter("value"))
        }

        // Store based on type
        switch value {
        case .string(let v):
            UserDefaults.standard.set(v, forKey: key)
        case .int(let v):
            UserDefaults.standard.set(v, forKey: key)
        case .double(let v):
            UserDefaults.standard.set(v, forKey: key)
        case .bool(let v):
            UserDefaults.standard.set(v, forKey: key)
        default:
            return .failure(HermesRouterError.invalidParameterType("value"))
        }

        return .success(true)
    }
}

// MARK: - Router Errors

enum HermesRouterError: LocalizedError {
    case unsupportedTool(String)
    case cameraNotAvailable
    case noVideoFrame
    case imageEncodingFailed
    case missingParameter(String)
    case invalidParameterType(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let tool):
            return "Tool not supported: \(tool)"
        case .cameraNotAvailable:
            return "Camera is not available"
        case .noVideoFrame:
            return "No video frame available"
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .invalidParameterType(let param):
            return "Invalid parameter type for: \(param)"
        case .notConnected:
            return "Not connected to Hermes"
        }
    }
}
