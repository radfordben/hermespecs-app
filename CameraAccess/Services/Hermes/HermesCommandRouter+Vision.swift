/*
 * Hermes Command Router - Vision Extension
 * Handles vision-specific commands and context injection
 */

import Foundation
import UIKit

// MARK: - Vision Command Extension

extension HermesCommandRouter {
    
    // MARK: - Vision Command Patterns
    
    /// Vision-specific command patterns
    struct VisionCommands {
        static let whatAmILookingAt = [
            "what am i looking at",
            "what is this",
            "what do you see",
            "describe this",
            "describe what you see",
            "tell me what this is"
        ]
        
        static let readText = [
            "read this",
            "read the text",
            "what does this say",
            "read this sign",
            "read this for me",
            "tell me what this says"
        ]
        
        static let identifyObject = [
            "what is this object",
            "identify this",
            "what object is this",
            "name this object",
            "tell me what this object is"
        ]
        
        static let rememberScene = [
            "remember this",
            "save this",
            "remember this place",
            "remember this for later",
            "save this to memory"
        ]
        
        static let findSimilar = [
            "find similar",
            "show me similar",
            "what looks like this",
            "find things like this"
        ]
        
        /// Checks if command is vision-related
        static func isVisionCommand(_ command: String) -> Bool {
            let lowercased = command.lowercased()
            return whatAmILookingAt.contains { lowercased.contains($0) } ||
                   readText.contains { lowercased.contains($0) } ||
                   identifyObject.contains { lowercased.contains($0) } ||
                   rememberScene.contains { lowercased.contains($0) } ||
                   findSimilar.contains { lowercased.contains($0) }
        }
        
        /// Gets the vision command type
        static func visionCommandType(_ command: String) -> VisionCommandType? {
            let lowercased = command.lowercased()
            
            if whatAmILookingAt.contains(where: { lowercased.contains($0) }) {
                return .describeScene
            } else if readText.contains(where: { lowercased.contains($0) }) {
                return .readText
            } else if identifyObject.contains(where: { lowercased.contains($0) }) {
                return .identifyObject
            } else if rememberScene.contains(where: { lowercased.contains($0) }) {
                return .rememberScene
            } else if findSimilar.contains(where: { lowercased.contains($0) }) {
                return .findSimilar
            }
            
            return nil
        }
    }
    
    enum VisionCommandType {
        case describeScene
        case readText
        case identifyObject
        case rememberScene
        case findSimilar
    }
    
    // MARK: - Vision Context Methods
    
    /// Handles a command with automatic vision context capture
    func handleCommandWithVisionContext(
        _ command: String,
        frameBuffer: VisionFrameBuffer? = nil
    ) async -> HermesRouterResult {
        
        // Check if this is a vision command
        let isVisionCommand = VisionCommands.isVisionCommand(command)
        let commandType = VisionCommands.visionCommandType(command)
        
        // For vision commands, we MUST have a frame
        if isVisionCommand {
            guard let frameBuffer = frameBuffer,
                  let frame = frameBuffer.captureFrameForCommand() else {
                return HermesRouterResult(
                    success: false,
                    message: "I need to see what you're looking at. Please make sure your glasses camera is active and try again.",
                    toolCalls: [],
                    shouldSpeak: true,
                    audioData: nil,
                    visualFeedback: HermesVisualFeedback(
                        type: "error",
                        content: "Camera frame not available",
                        image: nil,
                        actions: nil
                    )
                )
            }
            
            // Send vision command with frame
            return await sendVisionCommand(command, frame: frame, type: commandType)
        }
        
        // For regular commands, optionally include frame if available
        if let frameBuffer = frameBuffer,
           let frame = frameBuffer.getLatestFrame(),
           shouldIncludeVisionContext(command) {
            return await sendVisionCommand(command, frame: frame, type: nil)
        }
        
        // Regular command without vision
        return await handleCommand(command, image: nil)
    }
    
    /// Sends a vision command with image data to the AI service
    private func sendVisionCommand(
        _ command: String,
        frame: ProcessedFrame,
        type: VisionCommandType?
    ) async -> HermesRouterResult {

        isProcessing = true
        defer { isProcessing = false }

        let image = processFrameToImage(frame)

        do {
            let responseResult: Result<HermesResponse, Error> = await withCheckedContinuation { continuation in
                aiService.sendVisionCommand(command, image: image) { result in
                    continuation.resume(returning: result)
                }
            }

            switch responseResult {
            case .success(let response):
                let result = await processVisionResponse(response, command: command)
                lastResponse = result.message

                if result.shouldSpeak {
                    await speakResponse(result.message)
                }

                return result

            case .failure(let error):
                onError?(error)
                return HermesRouterResult(
                    success: false,
                    message: "Sorry, I had trouble analyzing what you're looking at. Please try again.",
                    toolCalls: [],
                    shouldSpeak: true,
                    audioData: nil,
                    visualFeedback: HermesVisualFeedback(
                        type: "error",
                        content: error.localizedDescription,
                        image: nil,
                        actions: nil
                    )
                )
            }
        }
    }

    private func processVisionResponse(_ response: HermesResponse, command: String) async -> HermesRouterResult {
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
            toolCalls: response.toolCalls ?? [],
            shouldSpeak: true,
            audioData: nil,
            visualFeedback: visualFeedback
        )
    }
    
    /// Determines if a regular command should include vision context
    private func shouldIncludeVisionContext(_ command: String) -> Bool {
        let contextualCommands = [
            "where",
            "what",
            "how does this",
            "what color",
            "what is this",
            "can you see",
            "do you see",
            "look at",
            "check this",
            "tell me about this"
        ]
        
        let lowercased = command.lowercased()
        return contextualCommands.contains { lowercased.contains($0) }
    }
    
    // MARK: - Vision Tool Execution
    
    /// Executes a vision-specific tool
    func executeVisionTool(
        _ tool: String,
        parameters: [String: AnyCodableValue],
        frameBuffer: VisionFrameBuffer
    ) async -> HermesToolResult {
        
        guard let frame = frameBuffer.captureFrameForCommand() else {
            return HermesToolResult(
                success: false,
                data: .null,
                message: "No camera frame available",
                error: "Camera not active"
            )
        }
        
        switch tool {
        case "identify_object":
            return await executeIdentifyObject(parameters, frame: frame)
            
        case "read_text":
            return await executeReadText(parameters, frame: frame)
            
        case "remember_scene":
            return await executeRememberScene(parameters, frame: frame)
            
        case "describe_scene":
            return await executeDescribeScene(parameters, frame: frame)
            
        default:
            return HermesToolResult(
                success: false,
                data: .null,
                message: "Unknown vision tool: \(tool)",
                error: "Unsupported tool"
            )
        }
    }
    
    // MARK: - Vision Tool Implementations

    private func executeIdentifyObject(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        let prompt = "Identify the main object in this image. Respond with the object name and a brief description."
        do {
            let image = processFrameToImage(frame)
            let response = try await sendVisionPrompt(prompt, image: image)
            return HermesToolResult(
                success: true,
                data: .dictionary([
                    "object": .string(response),
                    "confidence": .double(0.9)
                ]),
                message: response,
                error: nil
            )
        } catch {
            return HermesToolResult(
                success: false,
                data: .null,
                message: "Failed to identify object: \(error.localizedDescription)",
                error: error.localizedDescription
            )
        }
    }

    private func executeReadText(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        let prompt = "Read all visible text in this image. Transcribe the text exactly as it appears."
        do {
            let image = processFrameToImage(frame)
            let response = try await sendVisionPrompt(prompt, image: image)
            return HermesToolResult(
                success: true,
                data: .dictionary([
                    "text": .string(response),
                    "confidence": .double(0.95)
                ]),
                message: response,
                error: nil
            )
        } catch {
            return HermesToolResult(
                success: false,
                data: .null,
                message: "Failed to read text: \(error.localizedDescription)",
                error: error.localizedDescription
            )
        }
    }

    private func executeRememberScene(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        let prompt = "Describe this scene briefly. What is happening and what objects are present?"
        do {
            let image = processFrameToImage(frame)
            let description = try await sendVisionPrompt(prompt, image: image)
            let memoryId = UUID().uuidString
            let memoryTitle = parameters["description"]?.stringValue ?? parameters["note"]?.stringValue ?? description

            MultimodalMemoryManager.shared.rememberFromFrame(
                description: description,
                frame: frame,
                tags: ["vision", "remembered"]
            )

            return HermesToolResult(
                success: true,
                data: .dictionary([
                    "memory_id": .string(memoryId),
                    "description": .string(description),
                    "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
                ]),
                message: "Scene remembered: \(memoryTitle)",
                error: nil
            )
        } catch {
            return HermesToolResult(
                success: false,
                data: .null,
                message: "Failed to remember scene: \(error.localizedDescription)",
                error: error.localizedDescription
            )
        }
    }

    private func executeDescribeScene(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        let prompt = "Describe this scene in detail. What do you see? Include the type of scene and notable objects."
        do {
            let image = processFrameToImage(frame)
            let description = try await sendVisionPrompt(prompt, image: image)
            return HermesToolResult(
                success: true,
                data: .dictionary([
                    "description": .string(description),
                    "scene_type": .string("detected")
                ]),
                message: description,
                error: nil
            )
        } catch {
            return HermesToolResult(
                success: false,
                data: .null,
                message: "Failed to describe scene: \(error.localizedDescription)",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Vision Helper Methods

    private func sendVisionPrompt(_ prompt: String, image: UIImage) async throws -> String {
        let responseResult: Result<HermesResponse, Error> = await withCheckedContinuation { continuation in
            aiService.sendVisionCommand(prompt, image: image) { result in
                continuation.resume(returning: result)
            }
        }

        switch responseResult {
        case .success(let response):
            return response.message
        case .failure(let error):
            throw error
        }
    }

    private func processFrameToImage(_ frame: ProcessedFrame) -> UIImage {
        if let data = Data(base64Encoded: frame.base64Data),
           let image = UIImage(data: data) {
            return image
        }
        return UIImage()
    }

    // MARK: - Helper Methods

    private func speakResponse(_ message: String) async {
        do {
            try await ttsService.speak(message)
        } catch {
            print("TTS error: \(error)")
        }
    }
}
