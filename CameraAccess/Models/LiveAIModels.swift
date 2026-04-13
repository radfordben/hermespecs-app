/*
 * Live AI Models
 * 实时对话数据模型 - 对话模式定义
 */

import Foundation

// MARK: - Live AI Mode

enum LiveAIMode: String, CaseIterable, Codable, Identifiable {
    case standard = "standard"          // 默认模式 - 自由对话
    case museum = "museum"              // 博物馆模式
    case blind = "blind"                // 盲人模式
    case reading = "reading"            // 阅读模式
    case translate = "translate"        // 翻译模式
    case custom = "custom"              // 自定义提示词

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "liveai.mode.standard".localized
        case .museum:
            return "liveai.mode.museum".localized
        case .blind:
            return "liveai.mode.blind".localized
        case .reading:
            return "liveai.mode.reading".localized
        case .translate:
            return "liveai.mode.translate".localized
        case .custom:
            return "liveai.mode.custom".localized
        }
    }

    var icon: String {
        switch self {
        case .standard:
            return "brain.head.profile"
        case .museum:
            return "building.columns.circle"
        case .blind:
            return "figure.walk.circle"
        case .reading:
            return "text.viewfinder"
        case .translate:
            return "character.bubble"
        case .custom:
            return "pencil.circle"
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "liveai.mode.standard.desc".localized
        case .museum:
            return "liveai.mode.museum.desc".localized
        case .blind:
            return "liveai.mode.blind.desc".localized
        case .reading:
            return "liveai.mode.reading.desc".localized
        case .translate:
            return "liveai.mode.translate.desc".localized
        case .custom:
            return "liveai.mode.custom.desc".localized
        }
    }

    /// 获取模式对应的系统提示词
    var systemPrompt: String {
        switch self {
        case .standard:
            return "prompt.liveai.standard".localized
        case .museum:
            return "prompt.liveai.museum".localized
        case .blind:
            return "prompt.liveai.blind".localized
        case .reading:
            return "prompt.liveai.reading".localized
        case .translate:
            // 翻译模式需要从 Manager 获取目标语言
            return "prompt.liveai.translate".localized
        case .custom:
            // 自定义模式需要从 Manager 获取
            return ""
        }
    }

    /// 是否在用户说话时自动发送图片
    var autoSendImageOnSpeech: Bool {
        switch self {
        case .standard:
            return true  // 默认模式：语音触发时发送图片
        case .museum, .blind, .reading, .translate:
            return true  // 这些模式都需要看图
        case .custom:
            return true  // 自定义模式也支持图片
        }
    }
}
