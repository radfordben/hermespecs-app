/*
 * Hermes Tool Executors
 * Local execution implementations for on-device tools
 */

import Foundation
import UIKit
import EventKit
import MessageUI

// MARK: - Tool Execution Error

enum ToolExecutionError: Error {
    case permissionDenied
    case invalidParameters
    case notAvailable
    case executionFailed(String)
    case cancelled
}

// MARK: - Base Executor

class BaseToolExecutor: ToolExecutor {
    func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        fatalError("Subclasses must override")
    }
    
    func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        return [:]
    }
    
    func requireParameter(_ name: String, from parameters: [String: Any], prompt: String) -> [String: String] {
        if parameters[name] == nil {
            return [name: prompt]
        }
        return [:]
    }
}

// MARK: - Reminders Executor

class RemindersExecutor: BaseToolExecutor {
    private let eventStore = EKEventStore()
    
    override func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        missing.merge(requireParameter("title", from: parameters, prompt: "What should I remind you about?")) { _, new in new }
        return missing
    }
    
    override func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        // Request permission
        let authorized = await requestAuthorization()
        guard authorized else {
            throw ToolExecutionError.permissionDenied
        }
        
        // Create reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = parameters["title"] as? String ?? "Reminder"
        
        // Set calendar
        if let calendar = eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = calendar
        }
        
        // Set due date if provided
        if let dueDateString = parameters["due_date"] as? String {
            let date = parseDate(dueDateString)
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        
        // Save
        do {
            try eventStore.save(reminder, commit: true)
            return ToolExecutionResult(
                success: true,
                message: "Reminder set: \(reminder.title)",
                detailedMessage: "Added to your reminders",
                data: ["reminder_id": reminder.calendarItemIdentifier],
                error: nil,
                followUpActions: [
                    ToolExecutionResult.FollowUpAction(label: "View Reminders", command: "open reminders", icon: "checkmark.circle")
                ]
            )
        } catch {
            throw ToolExecutionError.executionFailed(error.localizedDescription)
        }
    }
    
    private func requestAuthorization() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        default:
            return false
        }
    }
    
    private func parseDate(_ string: String) -> Date {
        // Simple natural language date parsing
        let lowercased = string.lowercased()
        let now = Date()
        let calendar = Calendar.current
        
        if lowercased.contains("minute") {
            let minutes = Int(lowercased.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 5
            return calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        } else if lowercased.contains("hour") {
            let hours = Int(lowercased.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            return calendar.date(byAdding: .hour, value: hours, to: now) ?? now
        } else if lowercased.contains("day") {
            let days = Int(lowercased.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            return calendar.date(byAdding: .day, value: days, to: now) ?? now
        } else if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        
        // Try date formatter
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.date(from: string) ?? now
    }
}

// MARK: - Notes Executor

class NotesExecutor: BaseToolExecutor {
    override func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        missing.merge(requireParameter("content", from: parameters, prompt: "What should the note say?")) { _, new in new }
        return missing
    }
    
    override func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        // Apple Notes doesn't have a public API, so we use share sheet or Notes URL scheme
        let title = parameters["title"] as? String ?? "Note from HermeSpecs"
        let content = parameters["content"] as? String ?? ""
        let fullContent = "\(title)\n\n\(content)"
        
        // Create a notes URL
        let notesURL = "mobilenotes://"
        
        // For now, return success with instructions
        // In production, this would use the share sheet
        return ToolExecutionResult(
            success: true,
            message: "Note created: \(title)",
            detailedMessage: fullContent,
            data: ["title": title, "content": content],
            error: nil,
            followUpActions: [
                ToolExecutionResult.FollowUpAction(label: "Open Notes", command: "open notes", icon: "note.text")
            ]
        )
    }
}

// MARK: - iMessage Executor

class iMessageExecutor: BaseToolExecutor {
    override func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        missing.merge(requireParameter("recipient", from: parameters, prompt: "Who would you like to message?")) { _, new in new }
        missing.merge(requireParameter("message", from: parameters, prompt: "What would you like to say?")) { _, new in new }
        return missing
    }
    
    override func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        guard let recipient = parameters["recipient"] as? String,
              let message = parameters["message"] as? String else {
            throw ToolExecutionError.invalidParameters
        }
        
        // Create SMS URL scheme
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let smsURL = "sms:\(recipient)&body=\(encodedMessage)"
        
        return ToolExecutionResult(
            success: true,
            message: "Opening iMessage to \(recipient)",
            detailedMessage: message,
            data: [
                "recipient": recipient,
                "message": message,
                "sms_url": smsURL
            ],
            error: nil,
            followUpActions: [
                ToolExecutionResult.FollowUpAction(label: "Send", command: "send message", icon: "arrow.up.message")
            ]
        )
    }
}

// MARK: - Timer Executor

class TimerExecutor: BaseToolExecutor {
    override func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        missing.merge(requireParameter("duration", from: parameters, prompt: "How long should I set the timer for?")) { _, new in new }
        return missing
    }
    
    override func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        guard let durationString = parameters["duration"] as? String else {
            throw ToolExecutionError.invalidParameters
        }
        
        let seconds = parseDuration(durationString)
        let label = parameters["label"] as? String ?? "Timer"
        
        // Create timer URL scheme for Clock app
        let timerURL = "clock-timer://?duration=\(seconds)&label=\(label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        let timeString = formatDuration(seconds)
        
        return ToolExecutionResult(
            success: true,
            message: "Timer set for \(timeString)",
            detailedMessage: label,
            data: [
                "duration": seconds,
                "label": label,
                "timer_url": timerURL
            ],
            error: nil,
            followUpActions: [
                ToolExecutionResult.FollowUpAction(label: "View Timer", command: "open clock", icon: "timer")
            ]
        )
    }
    
    private func parseDuration(_ string: String) -> Int {
        let lowercased = string.lowercased()
        let numbers = lowercased.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let value = Int(numbers.joined()) ?? 5
        
        if lowercased.contains("hour") {
            return value * 3600
        } else if lowercased.contains("minute") {
            return value * 60
        } else if lowercased.contains("second") {
            return value
        }
        
        // Default to minutes
        return value * 60
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            return "\(secs) second\(secs == 1 ? "" : "s")"
        }
    }
}

// MARK: - Music Control Executor

class MusicControlExecutor: BaseToolExecutor {
    override func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        var missing: [String: String] = [:]
        missing.merge(requireParameter("action", from: parameters, prompt: "What would you like to do? Play, pause, skip?")) { _, new in new }
        return missing
    }
    
    override func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        guard let action = parameters["action"] as? String else {
            throw ToolExecutionError.invalidParameters
        }
        
        let lowercased = action.lowercased()
        var command = ""
        var message = ""
        
        switch lowercased {
        case "play":
            command = "play"
            message = "Playing music"
        case "pause", "stop":
            command = "pause"
            message = "Music paused"
        case "next", "skip", "forward":
            command = "next"
            message = "Skipping to next track"
        case "previous", "back":
            command = "previous"
            message = "Going back to previous track"
        case "volume up", "louder":
            command = "volume_up"
            message = "Volume increased"
        case "volume down", "quieter":
            command = "volume_down"
            message = "Volume decreased"
        default:
            if let query = parameters["query"] as? String {
                command = "play_\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                message = "Playing \(query)"
            } else {
                command = "play"
                message = "Playing music"
            }
        }
        
        return ToolExecutionResult(
            success: true,
            message: message,
            detailedMessage: nil,
            data: [
                "action": command,
                "query": parameters["query"] as? String
            ],
            error: nil,
            followUpActions: [
                ToolExecutionResult.FollowUpAction(label: "Open Music", command: "open music", icon: "music.note")
            ]
        )
    }
}

// MARK: - Voice Confirmation Manager

class VoiceConfirmationManager {
    static let shared = VoiceConfirmationManager()
    
    /// Determines if a tool requires voice confirmation based on risk level
    func requiresConfirmation(for tool: HermesTool, parameters: [String: Any]) -> Bool {
        // Always confirm high-risk actions
        if tool.requiresConfirmation {
            return true
        }
        
        // Check for destructive actions
        if let action = parameters["action"] as? String {
            let destructiveActions = ["delete", "remove", "cancel", "stop", "turn off"]
            if destructiveActions.contains(action.lowercased()) {
                return true
            }
        }
        
        // Check for external communication
        let communicationTools = ["imessage_send", "telegram_send", "slack_send", "gmail_send"]
        if communicationTools.contains(tool.id) {
            // Confirm if sending to new contact or with sensitive keywords
            if let message = parameters["message"] as? String {
                let sensitiveWords = ["password", "secret", "ssn", "credit card", "delete"]
                if sensitiveWords.contains(where: { message.lowercased().contains($0) }) {
                    return true
                }
            }
            return true  // Conservative: confirm all messages
        }
        
        return false
    }
    
    /// Generates a voice-friendly confirmation message
    func generateConfirmationMessage(for tool: HermesTool, parameters: [String: Any]) -> String {
        switch tool.id {
        case "imessage_send", "telegram_send":
            if let recipient = parameters["recipient"], let message = parameters["message"] {
                return "Send message to \(recipient): \(message)"
            }
            
        case "reminders_add":
            if let title = parameters["title"] {
                let when = parameters["due_date"] as? String ?? ""
                return when.isEmpty ? "Remind you: \(title)" : "Remind you to \(title) \(when)"
            }
            
        case "calendar_add":
            if let title = parameters["title"] {
                return "Schedule \(title)?"
            }
            
        case "gmail_send":
            if let to = parameters["to"] {
                return "Send email to \(to)?"
            }
            
        case "github_issues":
            if let action = parameters["action"] as? String, action == "create" {
                return "Create GitHub issue?"
            }
            
        default:
            return "Confirm \(tool.name)?"
        }
        
        return "Confirm this action?"
    }
    
    /// Generates success message optimized for voice
    func generateSuccessMessage(for tool: HermesTool, parameters: [String: Any]) -> String {
        switch tool.id {
        case "imessage_send":
            return "Message sent"
            
        case "reminders_add":
            if let title = parameters["title"] {
                return "Reminder set: \(title)"
            }
            return "Reminder added"
            
        case "notes_create":
            return "Note created"
            
        case "calendar_add":
            return "Event scheduled"
            
        case "hue_control":
            if let action = parameters["action"] {
                return "Lights \(action)"
            }
            return "Lights updated"
            
        case "timer_set":
            if let duration = parameters["duration"] {
                return "Timer set for \(duration)"
            }
            return "Timer started"
            
        case "music_control":
            return "Done"
            
        default:
            return "\(tool.name) completed"
        }
    }
}
