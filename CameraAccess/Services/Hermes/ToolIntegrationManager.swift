/*
 * Tool Integration Manager
 * Orchestrates tool discovery, execution, and voice interaction
 */

import Foundation
import Combine

@MainActor
class ToolIntegrationManager: ObservableObject {
    static let shared = ToolIntegrationManager()
    
    // MARK: - Published State
    
    @Published var availableTools: [HermesTool] = []
    @Published var recentTools: [HermesTool] = []
    @Published var favoriteTools: [HermesTool] = []
    @Published var isExecuting = false
    @Published var lastResult: ToolExecutionResult?
    @Published var pendingConfirmation: PendingConfirmation?
    
    struct PendingConfirmation {
        let tool: HermesTool
        let parameters: [String: Any]
        let message: String
    }
    
    // MARK: - Dependencies
    
    private let registry = ToolRegistry.shared
    private let confirmationManager = VoiceConfirmationManager.shared
    private let aiService: HermesAIService
    
    // MARK: - Callbacks
    
    var onToolExecuted: ((HermesTool, ToolExecutionResult) -> Void)?
    var onConfirmationRequired: ((String, @escaping (Bool) -> Void) -> Void)?
    var onVoiceResponse: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init(aiService: HermesAIService = .shared) {
        self.aiService = aiService
        loadTools()
        registerLocalExecutors()
    }
    
    // MARK: - Tool Loading
    
    private func loadTools() {
        availableTools = registry.getAllTools()
        loadFavorites()
    }
    
    private func loadFavorites() {
        // Load from UserDefaults
        let favoriteIds = UserDefaults.standard.stringArray(forKey: "hermespecs.favorite_tools") ?? []
        favoriteTools = favoriteIds.compactMap { registry.getTool($0) }
    }
    
    private func saveFavorites() {
        let favoriteIds = favoriteTools.map { $0.id }
        UserDefaults.standard.set(favoriteIds, forKey: "hermespecs.favorite_tools")
    }
    
    // MARK: - Executor Registration
    
    private func registerLocalExecutors() {
        // Register local tool executors
        registry.registerExecutor(for: "reminders_add", executor: RemindersExecutor())
        registry.registerExecutor(for: "notes_create", executor: NotesExecutor())
        registry.registerExecutor(for: "imessage_send", executor: iMessageExecutor())
        registry.registerExecutor(for: "timer_set", executor: TimerExecutor())
        registry.registerExecutor(for: "music_control", executor: MusicControlExecutor())
    }
    
    // MARK: - Tool Discovery
    
    func searchTools(query: String) -> [HermesTool] {
        return registry.searchTools(query: query)
    }
    
    func getToolsByCategory(_ category: HermesTool.ToolCategory) -> [HermesTool] {
        return registry.getToolsByCategory(category)
    }
    
    func toggleFavorite(_ tool: HermesTool) {
        if favoriteTools.contains(where: { $0.id == tool.id }) {
            favoriteTools.removeAll { $0.id == tool.id }
        } else {
            favoriteTools.append(tool)
        }
        saveFavorites()
    }
    
    // MARK: - Command Parsing
    
    /// Parses a natural language command to find matching tool and extract parameters
    func parseCommand(_ command: String) -> (tool: HermesTool, parameters: [String: Any])? {
        let lowercased = command.lowercased()
        
        // Check each tool's shortcuts
        for tool in availableTools {
            for shortcut in tool.shortcuts {
                if lowercased.contains(shortcut.lowercased()) {
                    let parameters = extractParameters(from: command, for: tool)
                    return (tool, parameters)
                }
            }
        }
        
        // Try semantic matching via Hermes
        return nil
    }
    
    private func extractParameters(from command: String, for tool: HermesTool) -> [String: Any] {
        var parameters: [String: Any] = [:]
        let lowercased = command.lowercased()
        
        switch tool.id {
        case "reminders_add":
            // Extract reminder text after "remind me to" or similar
            let patterns = [
                "remind me to ",
                "remind me ",
                "reminder ",
                "add reminder "
            ]
            for pattern in patterns {
                if lowercased.contains(pattern) {
                    let start = lowercased.range(of: pattern)!.upperBound
                    let text = String(command[start...])
                    parameters["title"] = text.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
        case "imessage_send", "telegram_send":
            // Extract recipient and message
            // Pattern: "text [recipient] [message]"
            let words = command.components(separatedBy: .whitespaces)
            if words.count >= 3 {
                parameters["recipient"] = words[1]
                parameters["message"] = words[2...].joined(separator: " ")
            }
            
        case "timer_set":
            // Extract duration
            let patterns = [
                "set timer for ",
                "timer for ",
                "countdown "
            ]
            for pattern in patterns {
                if lowercased.contains(pattern) {
                    let start = lowercased.range(of: pattern)!.upperBound
                    let text = String(command[start...])
                    parameters["duration"] = text.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
        case "hue_control":
            // Extract action and room
            if lowercased.contains("on") {
                parameters["action"] = "on"
            } else if lowercased.contains("off") {
                parameters["action"] = "off"
            } else if lowercased.contains("dim") {
                parameters["action"] = "dim"
            }
            
            // Extract room
            let roomPatterns = [
                "in the ",
                "living room",
                "bedroom",
                "kitchen",
                "office"
            ]
            for pattern in roomPatterns {
                if lowercased.contains(pattern) {
                    if pattern == "in the " {
                        if let range = lowercased.range(of: pattern) {
                            let start = range.upperBound
                            parameters["room"] = String(command[start...]).trimmingCharacters(in: .whitespaces)
                        }
                    } else {
                        parameters["room"] = pattern
                    }
                    break
                }
            }
            
        default:
            break
        }
        
        return parameters
    }
    
    // MARK: - Tool Execution
    
    /// Execute a tool with the given parameters
    func executeTool(_ tool: HermesTool, parameters: [String: Any]) async {
        isExecuting = true
        defer { isExecuting = false }
        
        // Check for missing required parameters
        let missingParams = validateParameters(tool, parameters: parameters)
        if !missingParams.isEmpty {
            // Ask user for missing parameters
            var updatedParams = parameters
            for (param, prompt) in missingParams {
                // In real implementation, this would use voice to ask user
                onVoiceResponse?(prompt)
                // For now, return with error
                let result = ToolExecutionResult(
                    success: false,
                    message: "I need more information",
                    detailedMessage: prompt,
                    data: nil,
                    error: "Missing parameter: \(param)",
                    followUpActions: nil
                )
                lastResult = result
                onToolExecuted?(tool, result)
                return
            }
        }
        
        // Check if confirmation required
        if confirmationManager.requiresConfirmation(for: tool, parameters: parameters) {
            let confirmMessage = confirmationManager.generateConfirmationMessage(for: tool, parameters: parameters)
            pendingConfirmation = PendingConfirmation(
                tool: tool,
                parameters: parameters,
                message: confirmMessage
            )
            
            onConfirmationRequired?(confirmMessage) { [weak self] confirmed in
                if confirmed {
                    self?.pendingConfirmation = nil
                    Task {
                        await self?.executeToolConfirmed(tool, parameters: parameters)
                    }
                } else {
                    self?.pendingConfirmation = nil
                    let result = ToolExecutionResult(
                        success: false,
                        message: "Cancelled",
                        detailedMessage: nil,
                        data: nil,
                        error: "User cancelled",
                        followUpActions: nil
                    )
                    self?.lastResult = result
                    self?.onToolExecuted?(tool, result)
                }
            }
            return
        }
        
        // Execute directly
        await executeToolConfirmed(tool, parameters: parameters)
    }
    
    private func executeToolConfirmed(_ tool: HermesTool, parameters: [String: Any]) async {
        var result: ToolExecutionResult
        
        if tool.localExecution {
            // Execute locally
            result = await executeLocalTool(tool, parameters: parameters)
        } else {
            // Execute via Hermes API
            result = await executeRemoteTool(tool, parameters: parameters)
        }
        
        lastResult = result
        onToolExecuted?(tool, result)
        
        // Speak success message
        if result.success {
            let voiceMessage = confirmationManager.generateSuccessMessage(for: tool, parameters: parameters)
            onVoiceResponse?(voiceMessage)
        } else {
            onVoiceResponse?(result.message)
        }
    }
    
    private func executeLocalTool(_ tool: HermesTool, parameters: [String: Any]) async -> ToolExecutionResult {
        guard let executor = registry.getExecutor(for: tool.id) else {
            return ToolExecutionResult(
                success: false,
                message: "Tool executor not found",
                detailedMessage: nil,
                data: nil,
                error: "Executor not registered",
                followUpActions: nil
            )
        }
        
        do {
            return try await executor.execute(parameters: parameters)
        } catch {
            return ToolExecutionResult(
                success: false,
                message: "Failed to execute \(tool.name)",
                detailedMessage: error.localizedDescription,
                data: nil,
                error: error.localizedDescription,
                followUpActions: [
                    ToolExecutionResult.FollowUpAction(label: "Try Again", command: "retry \(tool.id)", icon: "arrow.clockwise")
                ]
            )
        }
    }
    
    private func executeRemoteTool(_ tool: HermesTool, parameters: [String: Any]) async -> ToolExecutionResult {
        // Remote tools are handled by the AI provider through tool calls in the response
        // The AI model will return structured tool calls that are executed locally
        return ToolExecutionResult(
            success: false,
            message: "Remote tool '\(tool.name)' requires AI provider support. Configure your AI provider in Settings.",
            detailedMessage: nil,
            data: nil,
            error: "Remote tools not yet supported via direct AI API",
            followUpActions: nil
        )
    }
    
    private func validateParameters(_ tool: HermesTool, parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        
        for param in tool.parameters where param.required {
            if parameters[param.name] == nil {
                missing[param.name] = param.voicePrompt ?? "What's the \(param.name)?"
            }
        }
        
        return missing
    }
    
    // MARK: - Quick Actions
    
    func executeQuickAction(_ action: String) async {
        switch action {
        case "lights_on":
            if let tool = registry.getTool("hue_control") {
                await executeTool(tool, parameters: ["action": "on"])
            }
            
        case "lights_off":
            if let tool = registry.getTool("hue_control") {
                await executeTool(tool, parameters: ["action": "off"])
            }
            
        case "timer_5min":
            if let tool = registry.getTool("timer_set") {
                await executeTool(tool, parameters: ["duration": "5 minutes"])
            }
            
        case "pause_music":
            if let tool = registry.getTool("music_control") {
                await executeTool(tool, parameters: ["action": "pause"])
            }
            
        default:
            break
        }
    }
    
    // MARK: - Statistics
    
    func getToolStatistics() -> ToolStatistics {
        return ToolStatistics(
            totalTools: registry.totalToolCount,
            byCategory: registry.toolCountByCategory(),
            favorites: favoriteTools.count,
            localTools: availableTools.filter { $0.localExecution }.count,
            remoteTools: availableTools.filter { !$0.localExecution }.count
        )
    }
    
    struct ToolStatistics {
        let totalTools: Int
        let byCategory: [HermesTool.ToolCategory: Int]
        let favorites: Int
        let localTools: Int
        let remoteTools: Int
    }
}

// MARK: - End of ToolIntegrationManager

