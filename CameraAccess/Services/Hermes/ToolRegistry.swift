/*
 * Hermes Tool Registry
 * Central registry for tools available in HerMeSpecs
 * Manages tool metadata, execution, and voice-optimized responses
 */

import Foundation

// MARK: - Tool Definition

struct HermesTool: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let category: ToolCategory
    let parameters: [ToolParameter]
    let requiresConfirmation: Bool
    let voiceOptimized: Bool
    let localExecution: Bool  // true = execute on device, false = via Hermes API
    let shortcuts: [String]  // Voice command shortcuts
    
    enum ToolCategory: String, Codable, CaseIterable {
        case messaging = "Messaging"
        case productivity = "Productivity"
        case smartHome = "Smart Home"
        case search = "Search"
        case development = "Development"
        case media = "Media"
        case utilities = "Utilities"
        case vision = "Vision"
    }
}

struct ToolParameter: Codable {
    let name: String
    let type: ParameterType
    let description: String
    let required: Bool
    let defaultValue: String?
    let voicePrompt: String?  // Prompt spoken to user if parameter missing
    
    enum ParameterType: String, Codable {
        case string
        case number
        case boolean
        case array
        case object
        case contact  // Special type for contact lookup
        case date
        case time
    }
}

// MARK: - Tool Execution Result

struct ToolExecutionResult {
    let success: Bool
    let message: String  // Voice-friendly response
    let detailedMessage: String?  // For visual display
    let data: [String: Any]?
    let error: String?
    let followUpActions: [FollowUpAction]?
    
    struct FollowUpAction {
        let label: String
        let command: String
        let icon: String?
    }
}

// MARK: - Tool Registry

class ToolRegistry {
    static let shared = ToolRegistry()
    
    private var tools: [String: HermesTool] = [:]
    private var executors: [String: ToolExecutor] = [:]
    
    private init() {
        registerAllTools()
    }
    
    // MARK: - Tool Registration
    
    private func registerAllTools() {
        // MESSAGING TOOLS
        registerMessagingTools()
        
        // PRODUCTIVITY TOOLS
        registerProductivityTools()
        
        // SMART HOME TOOLS
        registerSmartHomeTools()
        
        // SEARCH TOOLS
        registerSearchTools()
        
        // DEVELOPMENT TOOLS
        registerDevelopmentTools()
        
        // VISION TOOLS
        registerVisionTools()
        
        // MEDIA TOOLS
        registerMediaTools()
        
        // UTILITY TOOLS
        registerUtilityTools()
    }
    
    // MARK: - Messaging Tools
    
    private func registerMessagingTools() {
        // iMessage
        registerTool(HermesTool(
            id: "imessage_send",
            name: "Send iMessage",
            description: "Send a message via iMessage to a contact",
            category: .messaging,
            parameters: [
                ToolParameter(name: "recipient", type: .contact, description: "Contact name or phone number", required: true, defaultValue: nil, voicePrompt: "Who would you like to message?"),
                ToolParameter(name: "message", type: .string, description: "Message content", required: true, defaultValue: nil, voicePrompt: "What would you like to say?")
            ],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["text", "message", "send message", "imessage"]
        ))
        
        // Telegram
        registerTool(HermesTool(
            id: "telegram_send",
            name: "Send Telegram",
            description: "Send a message via Telegram",
            category: .messaging,
            parameters: [
                ToolParameter(name: "recipient", type: .string, description: "Telegram username or chat", required: true, defaultValue: nil, voicePrompt: "Who on Telegram?"),
                ToolParameter(name: "message", type: .string, description: "Message content", required: true, defaultValue: nil, voicePrompt: "What should I send?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["telegram", "telegram message"]
        ))
        
        // Slack
        registerTool(HermesTool(
            id: "slack_send",
            name: "Send Slack Message",
            description: "Send a message to a Slack channel or user",
            category: .messaging,
            parameters: [
                ToolParameter(name: "channel", type: .string, description: "Channel or user", required: true, defaultValue: nil, voicePrompt: "Which channel or person?"),
                ToolParameter(name: "message", type: .string, description: "Message content", required: true, defaultValue: nil, voicePrompt: "What's the message?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["slack", "slack message"]
        ))
    }
    
    // MARK: - Productivity Tools
    
    private func registerProductivityTools() {
        // Reminders
        registerTool(HermesTool(
            id: "reminders_add",
            name: "Add Reminder",
            description: "Create a new reminder",
            category: .productivity,
            parameters: [
                ToolParameter(name: "title", type: .string, description: "Reminder title", required: true, defaultValue: nil, voicePrompt: "What should I remind you about?"),
                ToolParameter(name: "due_date", type: .date, description: "When to remind", required: false, defaultValue: nil, voicePrompt: "When should I remind you?"),
                ToolParameter(name: "list", type: .string, description: "Reminder list", required: false, defaultValue: "Reminders", voicePrompt: nil)
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["remind me", "reminder", "add reminder"]
        ))
        
        // Notes
        registerTool(HermesTool(
            id: "notes_create",
            name: "Create Note",
            description: "Create a new note in Apple Notes",
            category: .productivity,
            parameters: [
                ToolParameter(name: "title", type: .string, description: "Note title", required: false, defaultValue: nil, voicePrompt: "What should I title this note?"),
                ToolParameter(name: "content", type: .string, description: "Note content", required: true, defaultValue: nil, voicePrompt: "What should the note say?"),
                ToolParameter(name: "folder", type: .string, description: "Notes folder", required: false, defaultValue: "Notes", voicePrompt: nil)
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["note", "create note", "take note"]
        ))
        
        // Calendar
        registerTool(HermesTool(
            id: "calendar_add",
            name: "Add Calendar Event",
            description: "Create a calendar event",
            category: .productivity,
            parameters: [
                ToolParameter(name: "title", type: .string, description: "Event title", required: true, defaultValue: nil, voicePrompt: "What's the event called?"),
                ToolParameter(name: "start_time", type: .time, description: "Start time", required: true, defaultValue: nil, voicePrompt: "When does it start?"),
                ToolParameter(name: "end_time", type: .time, description: "End time", required: false, defaultValue: nil, voicePrompt: "When does it end?"),
                ToolParameter(name: "calendar", type: .string, description: "Calendar name", required: false, defaultValue: "Calendar", voicePrompt: nil)
            ],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["schedule", "add event", "calendar", "meeting"]
        ))
        
        // Gmail
        registerTool(HermesTool(
            id: "gmail_send",
            name: "Send Email",
            description: "Send an email via Gmail",
            category: .productivity,
            parameters: [
                ToolParameter(name: "to", type: .string, description: "Recipient email", required: true, defaultValue: nil, voicePrompt: "Who should I email?"),
                ToolParameter(name: "subject", type: .string, description: "Email subject", required: false, defaultValue: nil, voicePrompt: "What's the subject?"),
                ToolParameter(name: "body", type: .string, description: "Email body", required: true, defaultValue: nil, voicePrompt: "What should the email say?")
            ],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["email", "send email", "gmail"]
        ))
    }
    
    // MARK: - Smart Home Tools
    
    private func registerSmartHomeTools() {
        // Philips Hue
        registerTool(HermesTool(
            id: "hue_control",
            name: "Control Lights",
            description: "Control Philips Hue lights",
            category: .smartHome,
            parameters: [
                ToolParameter(name: "room", type: .string, description: "Room or light name", required: false, defaultValue: "all", voicePrompt: "Which room?"),
                ToolParameter(name: "action", type: .string, description: "on, off, dim, bright, color", required: true, defaultValue: nil, voicePrompt: "Should I turn them on or off?"),
                ToolParameter(name: "brightness", type: .number, description: "Brightness 0-100", required: false, defaultValue: nil, voicePrompt: nil),
                ToolParameter(name: "color", type: .string, description: "Color name or hex", required: false, defaultValue: nil, voicePrompt: "What color?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["lights", "turn on", "turn off", "dim", "hue"]
        ))
    }
    
    // MARK: - Search Tools
    
    private func registerSearchTools() {
        // Web Search
        registerTool(HermesTool(
            id: "web_search",
            name: "Web Search",
            description: "Search the web for information",
            category: .search,
            parameters: [
                ToolParameter(name: "query", type: .string, description: "Search query", required: true, defaultValue: nil, voicePrompt: "What should I search for?"),
                ToolParameter(name: "num_results", type: .number, description: "Number of results", required: false, defaultValue: "5", voicePrompt: nil)
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["search", "look up", "find", "google", "grok"]
        ))
        
        // arXiv
        registerTool(HermesTool(
            id: "arxiv_search",
            name: "Search arXiv",
            description: "Search academic papers on arXiv",
            category: .search,
            parameters: [
                ToolParameter(name: "query", type: .string, description: "Search query", required: true, defaultValue: nil, voicePrompt: "What topic should I search?"),
                ToolParameter(name: "category", type: .string, description: "Paper category", required: false, defaultValue: nil, voicePrompt: nil)
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["arxiv", "papers", "research"]
        ))
    }
    
    // MARK: - Development Tools
    
    private func registerDevelopmentTools() {
        // GitHub
        registerTool(HermesTool(
            id: "github_issues",
            name: "GitHub Issues",
            description: "Create or search GitHub issues",
            category: .development,
            parameters: [
                ToolParameter(name: "repo", type: .string, description: "Repository name", required: true, defaultValue: nil, voicePrompt: "Which repository?"),
                ToolParameter(name: "action", type: .string, description: "create, list, search", required: true, defaultValue: "list", voicePrompt: nil),
                ToolParameter(name: "title", type: .string, description: "Issue title", required: false, defaultValue: nil, voicePrompt: "What's the issue title?"),
                ToolParameter(name: "body", type: .string, description: "Issue body", required: false, defaultValue: nil, voicePrompt: "Describe the issue")
            ],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["github", "create issue", "file bug"]
        ))
        
        // Linear
        registerTool(HermesTool(
            id: "linear_issues",
            name: "Linear Issues",
            description: "Create or search Linear issues",
            category: .development,
            parameters: [
                ToolParameter(name: "team", type: .string, description: "Team key", required: false, defaultValue: nil, voicePrompt: "Which team?"),
                ToolParameter(name: "action", type: .string, description: "create, list, search", required: true, defaultValue: "list", voicePrompt: nil),
                ToolParameter(name: "title", type: .string, description: "Issue title", required: false, defaultValue: nil, voicePrompt: "What's the issue title?")
            ],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["linear", "create ticket", "new issue"]
        ))
    }
    
    // MARK: - Vision Tools
    
    private func registerVisionTools() {
        registerTool(HermesTool(
            id: "vision_describe",
            name: "Describe Scene",
            description: "Describe what the camera sees",
            category: .vision,
            parameters: [
                ToolParameter(name: "detail_level", type: .string, description: "brief or detailed", required: false, defaultValue: "brief", voicePrompt: nil)
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["what do you see", "describe", "look at"]
        ))
        
        registerTool(HermesTool(
            id: "vision_read_text",
            name: "Read Text",
            description: "Read text visible in camera",
            category: .vision,
            parameters: [],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["read this", "read text", "what does this say"]
        ))
        
        registerTool(HermesTool(
            id: "vision_remember",
            name: "Remember Scene",
            description: "Save current view to memory",
            category: .vision,
            parameters: [
                ToolParameter(name: "note", type: .string, description: "Optional note", required: false, defaultValue: nil, voicePrompt: "Any notes about this?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["remember this", "save this", "remember"]
        ))
    }
    
    // MARK: - Media Tools
    
    private func registerMediaTools() {
        registerTool(HermesTool(
            id: "music_control",
            name: "Music Control",
            description: "Control music playback",
            category: .media,
            parameters: [
                ToolParameter(name: "action", type: .string, description: "play, pause, next, previous, volume", required: true, defaultValue: nil, voicePrompt: nil),
                ToolParameter(name: "query", type: .string, description: "Song or artist", required: false, defaultValue: nil, voicePrompt: "What should I play?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["play", "pause", "next song", "music"]
        ))
    }
    
    // MARK: - Utility Tools
    
    private func registerUtilityTools() {
        registerTool(HermesTool(
            id: "timer_set",
            name: "Set Timer",
            description: "Set a timer",
            category: .utilities,
            parameters: [
                ToolParameter(name: "duration", type: .string, description: "Duration (e.g., 5 minutes)", required: true, defaultValue: nil, voicePrompt: "How long?"),
                ToolParameter(name: "label", type: .string, description: "Timer label", required: false, defaultValue: nil, voicePrompt: "What should I call this timer?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: ["timer", "set timer", "countdown"]
        ))
        
        registerTool(HermesTool(
            id: "weather_get",
            name: "Get Weather",
            description: "Get current weather",
            category: .utilities,
            parameters: [
                ToolParameter(name: "location", type: .string, description: "Location", required: false, defaultValue: "current", voicePrompt: "Where?")
            ],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: false,
            shortcuts: ["weather", "temperature", "forecast"]
        ))
    }
    
    // MARK: - Registration Helper
    
    private func registerTool(_ tool: HermesTool) {
        tools[tool.id] = tool
    }
    
    func registerExecutor(for toolId: String, executor: ToolExecutor) {
        executors[toolId] = executor
    }
    
    // MARK: - Public Access
    
    func getTool(_ id: String) -> HermesTool? {
        return tools[id]
    }
    
    func getAllTools() -> [HermesTool] {
        return Array(tools.values)
    }
    
    func getToolsByCategory(_ category: HermesTool.ToolCategory) -> [HermesTool] {
        return tools.values.filter { $0.category == category }
    }
    
    func searchTools(query: String) -> [HermesTool] {
        let lowercased = query.lowercased()
        return tools.values.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.shortcuts.contains { $0.lowercased().contains(lowercased) }
        }
    }
    
    func getExecutor(for toolId: String) -> ToolExecutor? {
        return executors[toolId]
    }
    
    // MARK: - Tool Statistics
    
    var totalToolCount: Int {
        return tools.count
    }
    
    func toolCountByCategory() -> [HermesTool.ToolCategory: Int] {
        var counts: [HermesTool.ToolCategory: Int] = [:]
        for category in HermesTool.ToolCategory.allCases {
            counts[category] = getToolsByCategory(category).count
        }
        return counts
    }
}

// MARK: - Tool Executor Protocol

protocol ToolExecutor {
    func execute(parameters: [String: Any]) async throws -> ToolExecutionResult
    func validateParameters(_ parameters: [String: Any]) -> [String: String]  // Returns missing params with prompts
}
