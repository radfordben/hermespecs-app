/*
 * OpenClaw Command Router
 * 将 Gateway 的 invoke 命令路由到 DAT SDK
 * 支持: camera.snap, camera.list, device.status, device.info
 */

import Foundation
import UIKit
import MWDATCore

@MainActor
class OpenClawCommandRouter {
    private weak var streamViewModel: StreamSessionViewModel?
    private let nodeId: String

    init(streamViewModel: StreamSessionViewModel, nodeId: String = "rayban-node") {
        self.streamViewModel = streamViewModel
        self.nodeId = nodeId
    }

    // MARK: - Command Dispatch

    func handleCommand(_ request: OpenClawNodeInvokeRequest) async -> OpenClawNodeInvokeResult {
        switch request.command {
        case "camera.snap":
            return await handleCameraSnap(request)
        case "camera.list":
            return handleCameraList(request)
        case "device.status":
            return handleDeviceStatus(request)
        case "device.info":
            return handleDeviceInfo(request)
        default:
            return makeError(id: request.id, code: "UNKNOWN_COMMAND",
                           message: "Unsupported command: \(request.command)")
        }
    }

    // MARK: - camera.snap

    private func handleCameraSnap(_ request: OpenClawNodeInvokeRequest) async -> OpenClawNodeInvokeResult {
        guard let vm = streamViewModel else {
            return makeError(id: request.id, code: "NOT_READY", message: "Stream not initialized")
        }

        // If not streaming, try to start
        if !vm.isStreaming {
            await vm.handleStartStreaming()

            // Wait for stream to become active (max 5s)
            let deadline = Date().addingTimeInterval(5.0)
            while !vm.isStreaming && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            if !vm.isStreaming {
                return makeError(id: request.id, code: "STREAM_FAILED",
                               message: "Could not start camera stream")
            }
        }

        // Grab current frame
        guard let frame = vm.currentVideoFrame else {
            return makeError(id: request.id, code: "NO_FRAME",
                           message: "No video frame available")
        }

        // Parse params
        let params = CameraSnapParams(from: request.params)

        // Resize if needed
        let image: UIImage
        if let maxWidth = Optional(params.maxWidth), maxWidth > 0,
           frame.size.width > CGFloat(maxWidth) {
            let scale = CGFloat(maxWidth) / frame.size.width
            let newSize = CGSize(width: frame.size.width * scale, height: frame.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            image = renderer.image { _ in frame.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            image = frame
        }

        // JPEG encode
        let quality = max(0.1, min(1.0, params.quality))
        guard let jpegData = image.jpegData(compressionQuality: quality) else {
            return makeError(id: request.id, code: "ENCODE_FAILED",
                           message: "Failed to encode JPEG")
        }

        let base64 = jpegData.base64EncodedString()

        print("[OpenClaw] camera.snap: \(Int(image.size.width))x\(Int(image.size.height)), \(jpegData.count) bytes")

        return OpenClawNodeInvokeResult(
            id: request.id,
            nodeId: nodeId,
            ok: true,
            payload: [
                "format": .string("jpg"),
                "base64": .string(base64),
                "width": .int(Int(image.size.width)),
                "height": .int(Int(image.size.height))
            ],
            error: nil
        )
    }

    // MARK: - camera.list

    private func handleCameraList(_ request: OpenClawNodeInvokeRequest) -> OpenClawNodeInvokeResult {
        let hasDevice = streamViewModel?.hasActiveDevice ?? false

        let cameras: [[String: AnyCodableValue]] = hasDevice ? [
            [
                "id": .string("rayban-main"),
                "name": .string("Ray-Ban Meta Camera"),
                "facing": .string("front"),
                "available": .bool(true)
            ]
        ] : []

        return OpenClawNodeInvokeResult(
            id: request.id,
            nodeId: nodeId,
            ok: true,
            payload: ["cameras": .array(cameras.map { .dictionary($0) })],
            error: nil
        )
    }

    // MARK: - device.status

    private func handleDeviceStatus(_ request: OpenClawNodeInvokeRequest) -> OpenClawNodeInvokeResult {
        let vm = streamViewModel

        var status: [String: AnyCodableValue] = [
            "deviceConnected": .bool(vm?.hasActiveDevice ?? false),
            "isStreaming": .bool(vm?.isStreaming ?? false),
            "streamStatus": .string("\(vm?.streamingStatus ?? .stopped)")
        ]

        if vm?.isStreaming == true {
            status["hasVideoFrame"] = .bool(vm?.currentVideoFrame != nil)
        }

        return OpenClawNodeInvokeResult(
            id: request.id,
            nodeId: nodeId,
            ok: true,
            payload: status,
            error: nil
        )
    }

    // MARK: - device.info

    private func handleDeviceInfo(_ request: OpenClawNodeInvokeRequest) -> OpenClawNodeInvokeResult {
        return OpenClawNodeInvokeResult(
            id: request.id,
            nodeId: nodeId,
            ok: true,
            payload: [
                "deviceType": .string("Ray-Ban Meta"),
                "appName": .string("HerMeSpecs"),
                "appVersion": .string("1.5.0"),
                "sdkVersion": .string("0.5.0"),
                "platform": .string("iOS"),
                "osVersion": .string(UIDevice.current.systemVersion)
            ],
            error: nil
        )
    }

    // MARK: - Helpers

    private func makeError(id: String, code: String, message: String) -> OpenClawNodeInvokeResult {
        return OpenClawNodeInvokeResult(
            id: id,
            nodeId: nodeId,
            ok: false,
            payload: nil,
            error: OpenClawError(code: code, message: message)
        )
    }
}
