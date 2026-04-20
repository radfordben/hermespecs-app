/*
 * Hermes Tool Executors
 * Local execution implementations for on-device tools
 */

import Foundation
import UIKit
import AVFoundation
import EventKit
import MessageUI
import UserNotifications
import MediaPlayer

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
        let title = parameters["title"] as? String ?? "Note from HermeSpecs"
        let content = parameters["content"] as? String ?? ""
        let fullContent = "\(title)\n\n\(content)"

        // Copy content to pasteboard and open Notes
        UIPasteboard.general.string = fullContent

        if let url = URL(string: "mobilenotes://") {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }

        return ToolExecutionResult(
            success: true,
            message: "Note created: \(title). Content copied to clipboard — paste in Notes.",
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

        // Create and open SMS URL scheme
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let smsURLString = "sms:\(recipient)?body=\(encodedMessage)"

        if let url = URL(string: smsURLString) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }

        return ToolExecutionResult(
            success: true,
            message: "Opening iMessage to \(recipient)",
            detailedMessage: message,
            data: [
                "recipient": recipient,
                "message": message,
                "sms_url": smsURLString
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

        // Open Clock app timer
        let timerURL = "clock-timer://"
        if let url = URL(string: timerURL) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }

        // Schedule a local notification as backup
        let content = UNMutableNotificationContent()
        content.title = "Timer"
        content.body = label.isEmpty ? "Your timer is done!" : "\(label) — timer is done!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "hermespecs-timer-\(UUID().uuidString)", content: content, trigger: trigger)

        await MainActor.run {
            UNUserNotificationCenter.current().add(request)
        }

        let timeString = formatDuration(seconds)

        return ToolExecutionResult(
            success: true,
            message: "Timer set for \(timeString). You'll be notified when it's done.",
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
        var message = ""

        let player = MPMusicPlayerController.applicationQueuePlayer

        switch lowercased {
        case "play":
            if let query = parameters["query"] as? String, !query.isEmpty {
                // Play specific song/artist via Music app URL
                let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "music://search?term=\(encodedQuery)") {
                    await MainActor.run { UIApplication.shared.open(url) }
                }
                message = "Searching for \(query) in Music"
            } else {
                player.play()
                message = "Playing music"
            }
        case "pause", "stop":
            player.pause()
            message = "Music paused"
        case "next", "skip", "forward":
            player.skipToNextItem()
            message = "Skipping to next track"
        case "previous", "back":
            player.skipToPreviousItem()
            message = "Going back to previous track"
        case "volume up", "louder":
            await MainActor.run {
                MPVolumeView.setVolume(to: min(1.0, MPVolumeView.currentVolume + 0.15))
            }
            message = "Volume increased"
        case "volume down", "quieter":
            await MainActor.run {
                MPVolumeView.setVolume(to: max(0.0, MPVolumeView.currentVolume - 0.15))
            }
            message = "Volume decreased"
        default:
            if let query = parameters["query"] as? String {
                let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "music://search?term=\(encodedQuery)") {
                    await MainActor.run { UIApplication.shared.open(url) }
                }
                message = "Searching for \(query) in Music"
            } else {
                player.play()
                message = "Playing music"
            }
        }

        return ToolExecutionResult(
            success: true,
            message: message,
            detailedMessage: nil,
            data: [
                "action": action,
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

// MARK: - MPVolumeView Volume Helper

extension MPVolumeView {
    static func currentVolume() -> Float {
        let audioSession = AVAudioSession.sharedInstance()
        return audioSession.outputVolume
    }

    static func setVolume(to volume: Float) {
        let volumeView = MPVolumeView()
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.value = volume
        }
        volumeView.removeFromSuperview()
    }
}
