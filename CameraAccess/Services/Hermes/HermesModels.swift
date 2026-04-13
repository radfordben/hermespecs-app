/*
 * Hermes Models
 * Shared data models for Hermes Agent communication
 * Compatible with OpenClaw pattern using AnyCodableValue
 */

import Foundation

// MARK: - AnyCodableValue (Shared with OpenClaw pattern)

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .dictionary(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }

    static func from(_ value: Any) -> AnyCodableValue {
        switch value {
        case let v as String: return .string(v)
        case let v as Int: return .int(v)
        case let v as Double: return .double(v)
        case let v as Bool: return .bool(v)
        case let v as [Any]: return .array(v.map { from($0) })
        case let v as [String: Any]: return .dictionary(v.mapValues { from($0) })
        default: return .null
        }
    }

    func toAny() -> Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .dictionary(let v): return v.mapValues { $0.toAny() }
        case .null: return NSNull()
        }
    }
}

// MARK: - Hermes Event Types

enum HermesEventType: String, Codable {
    case command
    case visionCommand = "vision_command"
    case audioCommand = "audio_command"
    case response
    case toolExecution = "tool_execution"
    case ping
    case pong
    case error
    case connected
}

// MARK: - Hermes Capabilities

struct HermesCapabilities: Codable {
    let version: String
    let supportsVision: Bool
    let supportsAudio: Bool
    let supportsTTS: Bool
    let availableTools: [String]

    static let current = HermesCapabilities(
        version: "1.0",
        supportsVision: true,
        supportsAudio: true,
        supportsTTS: true,
        availableTools: [
            "web_search",
            "image_analysis",
            "text_to_speech",
            "code_execution",
            "file_operations",
            "calendar",
            "reminders",
            "messaging",
            "email",
            "notes"
        ]
    )
}

// MARK: - Tool Parameter Definitions

struct HermesToolParameter: Codable {
    let name: String
    let type: String
    let description: String
    let required: Bool
    let defaultValue: AnyCodableValue?
}

// MARK: - Conversation History

struct HermesConversationMessage: Codable, Identifiable {
    let id: String
    let role: String  // "user", "assistant", "system", "tool"
    let content: String
    let timestamp: Date
    let toolCalls: [HermesToolCall]?
    let attachments: [HermesAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case toolCalls = "tool_calls"
        case attachments
    }
}

// MARK: - Session Configuration

struct HermesSessionConfig: Codable {
    let sessionId: String
    let language: String
    let enableTTS: Bool
    let enableVision: Bool
    let maxTokens: Int
    let temperature: Double
    let systemPrompt: String?

    static let `default` = HermesSessionConfig(
        sessionId: UUID().uuidString,
        language: "en",
        enableTTS: true,
        enableVision: true,
        maxTokens: 2048,
        temperature: 0.7,
        systemPrompt: nil
    )
}

// MARK: - Device Info

struct HermesDeviceInfo: Codable {
    let deviceId: String
    let deviceType: String
    let appVersion: String
    let osVersion: String
    let capabilities: HermesCapabilities

    static var current: HermesDeviceInfo {
        HermesDeviceInfo(
            deviceId: HermesService.shared.deviceId,
            deviceType: "Ray-Ban Meta",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            osVersion: UIDevice.current.systemVersion,
            capabilities: HermesCapabilities.current
        )
    }
}

// MARK: - Status/Health Check

struct HermesHealthStatus: Codable {
    let status: String
    let uptime: Double?
    let version: String?
    let activeConnections: Int?
}
