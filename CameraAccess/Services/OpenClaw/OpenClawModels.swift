/*
 * OpenClaw Gateway Protocol Models
 * 定义与 OpenClaw Gateway 通信的消息格式
 */

import Foundation

// MARK: - Gateway Protocol Frames

enum OpenClawFrameType: String, Codable {
    case req
    case res
    case evt
}

struct OpenClawRequestFrame: Codable {
    let type: String // "req"
    let id: String
    let method: String
    let params: [String: AnyCodableValue]?
}

struct OpenClawResponseFrame: Codable {
    let type: String // "res"
    let id: String
    let ok: Bool
    let payload: [String: AnyCodableValue]?
    let error: OpenClawError?
}

struct OpenClawEventFrame: Codable {
    let type: String // "evt"
    let method: String
    let params: [String: AnyCodableValue]?
}

struct OpenClawError: Codable {
    let code: String?
    let message: String?
}

// MARK: - Connect Handshake

struct OpenClawConnectChallenge: Codable {
    let nonce: String?
}

struct OpenClawConnectParams: Codable {
    let minprotocol: Int
    let maxprotocol: Int
    let client: [String: AnyCodableValue]
    let role: String
    let scopes: [String]
    let caps: [String]
    let commands: [String]
    let auth: [String: AnyCodableValue]?
}

struct OpenClawHelloOk: Codable {
    let `protocol`: Int?
}

// MARK: - Node Invoke

struct OpenClawNodeInvokeRequest {
    let id: String
    let command: String
    let params: [String: Any]?
    let timeoutMs: Int?
}

struct OpenClawNodeInvokeResult: Codable {
    let id: String
    let nodeId: String
    let ok: Bool
    let payload: [String: AnyCodableValue]?
    let error: OpenClawError?
}

// MARK: - Camera Command Params

struct CameraSnapParams {
    let maxWidth: Int
    let quality: Double
    let format: String

    init(from dict: [String: Any]?) {
        self.maxWidth = dict?["maxWidth"] as? Int ?? 1600
        self.quality = dict?["quality"] as? Double ?? 0.8
        self.format = dict?["format"] as? String ?? "jpg"
    }
}

// MARK: - AnyCodableValue (lightweight JSON wrapper)

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
