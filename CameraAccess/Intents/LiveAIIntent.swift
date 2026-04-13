/*
 * Live AI Intent
 * App Intent - 支持 Siri 和快捷指令触发 Live AI（后台运行，无需解锁）
 */

import AppIntents
import UIKit

// MARK: - Live AI Intent (Background Mode)

@available(iOS 16.0, *)
struct LiveAIIntent: AppIntent {
    static var title: LocalizedStringResource = "实时对话"
    static var description = IntentDescription("启动实时多模态对话")
    // 必须打开 App，因为 iOS 后台录音有系统限制
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 发送通知让 App 自动打开 Live AI 界面
        NotificationCenter.default.post(name: .liveAITriggered, object: nil)
        return .result(dialog: "正在启动实时对话...")
    }
}

// MARK: - Stop Live AI Intent

@available(iOS 16.0, *)
struct StopLiveAIIntent: AppIntent {
    static var title: LocalizedStringResource = "停止实时对话"
    static var description = IntentDescription("停止正在运行的实时对话")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = LiveAIManager.shared

        if manager.isRunning {
            await manager.stopSession()
            return .result(dialog: "Live AI 已停止")
        } else {
            return .result(dialog: "Live AI 未在运行")
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let liveAITriggered = Notification.Name("liveAITriggered")
}
