/*
 * OpenClaw ASR Service
 * 阿里云 Fun-ASR 实时语音识别
 * 麦克风录音 → PCM 16kHz → WebSocket → 实时文字
 */

import Foundation
import AVFoundation

class OpenClawASRService: NSObject {

    // WebSocket
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let wsURL = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
    private let model = "fun-asr-realtime"

    // Audio
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private let targetSampleRate: Double = 16000
    private var isRecording = false

    // API Key
    private let apiKey: String

    // Task tracking
    private var taskId: String?
    private var isRunning = false

    // Callbacks
    var onPartialResult: ((String) -> Void)?  // 中间结果
    var onFinalResult: ((String) -> Void)?     // 最终结果（一句话说完）
    var onError: ((String) -> Void)?

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    // MARK: - Start/Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        taskId = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        connectWebSocket()
    }

    func stop() {
        isRunning = false
        stopRecording()

        // Send stop signal
        if webSocket != nil {
            sendStopTask()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.webSocket?.cancel(with: .goingAway, reason: nil)
            self?.webSocket = nil
            self?.urlSession?.invalidateAndCancel()
            self?.urlSession = nil
        }

        print("[ASR] Stopped")
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        guard let url = URL(string: wsURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        print("[ASR] Connecting to Fun-ASR...")
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                print("[ASR] Receive error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Protocol Messages

    private func sendRunTask() {
        guard let taskId else { return }

        let payload: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": [
                    "format": "pcm",
                    "sample_rate": 16000,
                    "vocabulary_id": "",
                    "disfluency_removal_enabled": false
                ] as [String: Any],
                "input": [:] as [String: Any]
            ] as [String: Any]
        ]

        sendJSON(payload)
        print("[ASR] Sent run-task")
    }

    private func sendStopTask() {
        guard let taskId else { return }

        let payload: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [:] as [String: Any]
            ]
        ]

        sendJSON(payload)
        print("[ASR] Sent finish-task")
    }

    private func sendAudioData(_ data: Data) {
        webSocket?.send(.data(data)) { error in
            if let error {
                print("[ASR] Send audio error: \(error.localizedDescription)")
            }
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { error in
            if let error {
                print("[ASR] Send JSON error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let header = json["header"] as? [String: Any]
        let event = header?["event"] as? String

        switch event {
        case "task-started":
            print("[ASR] Task started, beginning recording")
            startRecording()

        case "result-generated":
            if let payload = json["payload"] as? [String: Any],
               let output = payload["output"] as? [String: Any],
               let sentence = output["sentence"] as? [String: Any] {
                let text = sentence["text"] as? String ?? ""
                let endTime = sentence["end_time"] as? Int

                if endTime != nil && endTime! > 0 {
                    // Sentence complete
                    if !text.isEmpty {
                        print("[ASR] Final: \(text)")
                        DispatchQueue.main.async { self.onFinalResult?(text) }
                    }
                } else {
                    // Partial result
                    if !text.isEmpty {
                        DispatchQueue.main.async { self.onPartialResult?(text) }
                    }
                }
            }

        case "task-finished":
            print("[ASR] Task finished")

        case "task-failed":
            let message = header?["error_message"] as? String ?? "Unknown error"
            print("[ASR] Task failed: \(message)")
            DispatchQueue.main.async { self.onError?(message) }

        default:
            break
        }
    }

    // MARK: - Audio Recording

    private func startRecording() {
        guard !isRecording else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)

            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            print("[ASR] Input: \(inputFormat.sampleRate)Hz, target: \(targetSampleRate)Hz")

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            engine.prepare()
            try engine.start()
            isRecording = true
            print("[ASR] Recording started")
        } catch {
            print("[ASR] Recording failed: \(error)")
            DispatchQueue.main.async { self.onError?("Recording failed: \(error.localizedDescription)") }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false
        audioConverter = nil
        print("[ASR] Recording stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let inputFormat = buffer.format

        // Resample to 16kHz mono if needed
        let outputBuffer: AVAudioPCMBuffer
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            guard let resampled = resample(buffer) else { return }
            outputBuffer = resampled
        } else {
            outputBuffer = buffer
        }

        // Convert Float32 to PCM16
        guard let floatData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        var pcmData = Data(count: frameLength * 2)
        pcmData.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<frameLength {
                let sample = max(-1.0, min(1.0, floatData[0][i]))
                ptr[i] = Int16(sample * 32767.0)
            }
        }

        sendAudioData(pcmData)
    }

    private func resample(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) else { return nil }

        if audioConverter == nil || audioConverter?.inputFormat != input.format {
            audioConverter = AVAudioConverter(from: input.format, to: outputFormat)
        }
        guard let converter = audioConverter else { return nil }

        let ratio = targetSampleRate / input.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(input.frameLength) * ratio)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return nil }

        var hasProvidedInput = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            outStatus.pointee = .haveData
            return input
        }

        return error == nil ? output : nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension OpenClawASRService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[ASR] WebSocket connected")
        receiveMessage()
        sendRunTask()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[ASR] WebSocket closed: \(closeCode.rawValue)")
    }
}
