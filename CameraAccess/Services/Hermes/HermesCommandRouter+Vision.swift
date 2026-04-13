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
    
    /// Sends a vision command with image data to Hermes
    private func sendVisionCommand(
        _ command: String,
        frame: ProcessedFrame,
        type: VisionCommandType?
    ) async -> HermesRouterResult {
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Build vision request
        let visionContext = VisionContext(
            cameraSource: "rayban_meta",
            lighting: nil,  // Could be detected from image analysis
            location: nil,  // Could include GPS if available
            previousContext: lastCommand
        )
        
        let request = HermesVisionRequest(
            command: command,
            imageData: frame.base64Data,
            imageMimeType: frame.mimeType,
            imageDimensions: ImageDimensions(width: frame.width, height: frame.height),
            context: visionContext,
            timestamp: Date()
        )
        
        // Send to Hermes
        do {
            let result = try await hermesService.sendVisionCommand(request)
            
            // Process response
            lastResponse = result.message
            
            // Speak response if TTS enabled
            if result.shouldSpeak, let message = result.message {
                await speakResponse(message)
            }
            
            return result
            
        } catch {
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
        // This would call Hermes vision API for object identification
        // For now, return a placeholder result
        return HermesToolResult(
            success: true,
            data: .dictionary([
                "object": .string("object_name"),
                "confidence": .double(0.95),
                "frame": .string(frame.base64Data.prefix(100) + "...")
            ]),
            message: "Object identified successfully",
            error: nil
        )
    }
    
    private func executeReadText(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        // This would call OCR service via Hermes
        return HermesToolResult(
            success: true,
            data: .dictionary([
                "text": .string("Sample text from image"),
                "confidence": .double(0.98)
            ]),
            message: "Text read successfully",
            error: nil
        )
    }
    
    private func executeRememberScene(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        // Store in memory via Hermes
        let memoryId = UUID().uuidString
        let description = parameters["description"]?.stringValue ?? "Remembered scene"
        
        return HermesToolResult(
            success: true,
            data: .dictionary([
                "memory_id": .string(memoryId),
                "description": .string(description),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
            ]),
            message: "Scene remembered: \(description)",
            error: nil
        )
    }
    
    private func executeDescribeScene(
        _ parameters: [String: AnyCodableValue],
        frame: ProcessedFrame
    ) async -> HermesToolResult {
        // This would call Hermes vision API for scene description
        return HermesToolResult(
            success: true,
            data: .dictionary([
                "description": .string("A scene description would appear here"),
                "scene_type": .string("indoor"),
                "objects": .array([.string("object1"), .string("object2")])
            ]),
            message: "Scene described",
            error: nil
        )
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

// MARK: - HermesService Vision Extension

extension HermesService {
    
    /// Sends a vision command to Hermes Agent
    func sendVisionCommand(_ request: HermesVisionRequest) async throws -> HermesRouterResult {
        // This would send the request via WebSocket and wait for response
        // Placeholder implementation
        
        return HermesRouterResult(
            success: true,
            message: "I can see you're looking at something. Let me analyze it...",
            toolCalls: [],
            shouldSpeak: true,
            audioData: nil,
            visualFeedback: nil
        )
    }
}
