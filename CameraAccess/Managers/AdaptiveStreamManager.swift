/*
 * Adaptive Stream Manager
 * Manages HEVC streaming with adaptive bitrate and frame rate
 * Integrates with PerformanceMonitor for optimal streaming
 */

import Foundation
import AVFoundation
import VideoToolbox
import Combine

// MARK: - VTCompression Output Callback (must be a free function for C interop)

private func hermesCompressionOutputCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _ status: OSStatus,
    _ infoFlags: VTEncodeInfoFlags,
    _ sampleBuffer: CMSampleBuffer?
) -> Void {
    guard status == noErr, let sampleBuffer = sampleBuffer else { return }

    let manager = Unmanaged<AdaptiveStreamManager>.fromOpaque(refcon!).takeUnretainedValue()

    if let data = manager.sampleBufferToData(sampleBuffer) {
        manager.updateBitrate(Int64(data.count))

        DispatchQueue.main.async {
            manager.onFrameCompressed?(data, Date().timeIntervalSince1970)
        }
    }
}

@MainActor
class AdaptiveStreamManager: ObservableObject {
    static let shared = AdaptiveStreamManager()
    
    // MARK: - Published State
    
    @Published var isStreaming = false
    @Published var currentFrameRate: Double = 1.0
    @Published var currentQuality: PerformanceMonitor.StreamQuality = .medium
    @Published var compressionRatio: Double = 0.75
    @Published var estimatedBitrate: Double = 0
    @Published var streamHealth: StreamHealth = .good
    
    enum StreamHealth: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        
        var icon: String {
            switch self {
            case .excellent: return "wifi"
            case .good: return "wifi"
            case .fair: return "exclamationmark.triangle"
            case .poor: return "wifi.slash"
            }
        }
    }
    
    // MARK: - Configuration
    
    struct StreamConfiguration {
        var codec: VideoCodec = .hevc
        var enableAdaptiveBitrate: Bool = true
        var enableBackgroundStreaming: Bool = true
        var targetFileSizeKB: Int = 100
        var minFrameRate: Double = 0.2  // 1 frame per 5 seconds minimum
        var maxFrameRate: Double = 2.0  // 2 fps maximum
        var keyFrameInterval: Int = 30
        
        enum VideoCodec {
            case h264
            case hevc  // H.265 - better compression, background capable
            case jpeg  // Fallback
        }
    }
    
    var configuration = StreamConfiguration()
    
    // MARK: - Private Properties
    
    private let performanceMonitor = PerformanceMonitor.shared
    private var frameCaptureTimer: Timer?
    private var compressionSession: VTCompressionSession?
    private var videoFormatDescription: CMVideoFormatDescription?
    
    private var frameBuffer = VisionFrameBuffer()
    private var frameProcessor = VisionFrameProcessor()
    
    private var lastFrameTime: Date?
    private var frameTimestamps: [Date] = []
    private var bytesTransmitted: Int64 = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    
    var onFrameCompressed: ((Data, Double) -> Void)?  // Compressed data, timestamp
    var onStreamError: ((Error) -> Void)?
    var onBitrateChanged: ((Double) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        setupPerformanceMonitoring()
    }
    
    // MARK: - Setup
    
    private func setupPerformanceMonitoring() {
        // Listen to performance monitor changes
        performanceMonitor.$recommendedFrameRate
            .dropFirst()
            .sink { [weak self] newRate in
                self?.adaptFrameRate(newRate)
            }
            .store(in: &cancellables)
        
        performanceMonitor.$recommendedQuality
            .dropFirst()
            .sink { [weak self] newQuality in
                self?.adaptQuality(newQuality)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Stream Control
    
    func startStreaming() {
        guard !isStreaming else { return }
        
        isStreaming = true
        currentFrameRate = performanceMonitor.recommendedFrameRate
        currentQuality = performanceMonitor.recommendedQuality
        
        // Setup compression session
        setupCompressionSession()
        
        // Start frame capture timer
        startFrameCapture()
        
        print("Adaptive streaming started at \(currentFrameRate) fps, quality: \(currentQuality)")
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        isStreaming = false
        frameCaptureTimer?.invalidate()
        frameCaptureTimer = nil
        
        // Clean up compression session
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: CMTime.invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        print("Adaptive streaming stopped")
    }
    
    func pauseStreaming() {
        frameCaptureTimer?.invalidate()
        frameCaptureTimer = nil
        print("Adaptive streaming paused")
    }
    
    func resumeStreaming() {
        if isStreaming {
            startFrameCapture()
        }
    }
    
    // MARK: - Frame Capture
    
    private func startFrameCapture() {
        let interval = 1.0 / currentFrameRate
        
        frameCaptureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }
    }
    
    private func captureFrame() {
        // In production, this would capture from the Meta glasses stream
        // For now, this is a placeholder that would integrate with StreamSessionViewModel
        
        let now = Date()
        lastFrameTime = now
        frameTimestamps.append(now)
        
        // Keep only recent timestamps for rate calculation
        let cutoff = now.addingTimeInterval(-10) // Keep last 10 seconds
        frameTimestamps.removeAll { $0 < cutoff }
        
        // Update stream health based on frame rate stability
        updateStreamHealth()
    }
    
    // MARK: - Compression (HEVC)
    
    private func setupCompressionSession() {
        guard configuration.codec == .hevc else { return }
        
        let width = Int32(currentQuality.resolution.width)
        let height = Int32(currentQuality.resolution.height)
        
        let codecType = kCMVideoCodecType_HEVC
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: codecType,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: hermesCompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("Failed to create HEVC compression session")
            return
        }
        
        // Configure compression properties
        let properties: [NSString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_HEVC_Main_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate: 500000, // 500 kbps
            kVTCompressionPropertyKey_DataRateLimits: [500000, 1] as CFArray, // 500 kbps, 1 second
            kVTCompressionPropertyKey_KeyFrameInterval: configuration.keyFrameInterval,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_Quality: compressionRatio
        ]
        
        VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func compressFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let session = compressionSession else {
            compressFrameJPEG(sampleBuffer)
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            infoFlagsOut: nil
        )

        if status != noErr {
            print("VTCompressionSessionEncodeFrame error: \(status)")
        }
    }
    
    private func compressFrameJPEG(_ sampleBuffer: CMSampleBuffer) {
        frameProcessor.processFrame(sampleBuffer) { [weak self] result in
            switch result {
            case .success(let frame):
                if let data = Data(base64Encoded: frame.base64Data) {
                    self?.updateBitrate(Int64(data.count))
                    self?.onFrameCompressed?(data, Date().timeIntervalSince1970)
                }
            case .failure(let error):
                print("JPEG compression failed: \(error)")
            }
        }
    }
    
    func sampleBufferToData(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard status == noErr, let pointer = dataPointer else {
            return nil
        }
        
        return Data(bytes: pointer, count: length)
    }
    
    // MARK: - Adaptive Logic
    
    private func adaptFrameRate(_ newRate: Double) {
        guard isStreaming else { return }
        
        // Clamp to min/max
        let clampedRate = max(configuration.minFrameRate, min(configuration.maxFrameRate, newRate))
        
        guard clampedRate != currentFrameRate else { return }
        
        currentFrameRate = clampedRate
        
        // Restart timer with new interval
        frameCaptureTimer?.invalidate()
        startFrameCapture()
        
        print("Adapted frame rate to \(currentFrameRate) fps")
    }
    
    private func adaptQuality(_ newQuality: PerformanceMonitor.StreamQuality) {
        guard newQuality != currentQuality else { return }
        
        currentQuality = newQuality
        compressionRatio = newQuality.compressionQuality
        
        // Recreate compression session with new quality
        if isStreaming {
            if let session = compressionSession {
                VTCompressionSessionInvalidate(session)
            }
            setupCompressionSession()
        }
        
        print("Adapted quality to \(currentQuality), compression: \(compressionRatio)")
    }
    
    func updateBitrate(_ bytes: Int64) {
        bytesTransmitted += bytes
        
        // Calculate bitrate over last 10 seconds
        let now = Date()
        let recentTimestamps = frameTimestamps.filter { now.timeIntervalSince($0) < 10 }
        
        guard recentTimestamps.count >= 2 else { return }
        
        let duration = recentTimestamps.last!.timeIntervalSince(recentTimestamps.first!)
        guard duration > 0 else { return }
        
        // Estimate bitrate (bits per second)
        let bits = Double(bytesTransmitted) * 8
        estimatedBitrate = bits / duration
        
        onBitrateChanged?(estimatedBitrate)
    }
    
    private func updateStreamHealth() {
        // Calculate actual frame rate
        let actualRate = Double(frameTimestamps.count) / 10.0 // Over 10 second window
        
        // Compare to target
        let ratio = actualRate / currentFrameRate
        
        if ratio > 0.95 {
            streamHealth = .excellent
        } else if ratio > 0.8 {
            streamHealth = .good
        } else if ratio > 0.5 {
            streamHealth = .fair
        } else {
            streamHealth = .poor
        }
        
        // If health is poor, reduce quality
        if streamHealth == .poor && currentQuality != .low {
            adaptQuality(.low)
        }
    }
    
    // MARK: - Background Streaming
    
    func enableBackgroundMode() {
        guard configuration.enableBackgroundStreaming else { return }
        
        // HEVC supports background streaming better than H.264
        // Reduce quality for background
        if configuration.codec == .hevc {
            adaptQuality(.low)
            adaptFrameRate(0.5)
            print("Background mode enabled with HEVC")
        }
    }
    
    func disableBackgroundMode() {
        // Restore normal streaming
        adaptQuality(performanceMonitor.recommendedQuality)
        adaptFrameRate(performanceMonitor.recommendedFrameRate)
        print("Background mode disabled")
    }
    
    // MARK: - Statistics
    
    func getStreamStatistics() -> StreamStatistics {
        let actualRate = Double(frameTimestamps.count) / 10.0
        
        return StreamStatistics(
            targetFrameRate: currentFrameRate,
            actualFrameRate: actualRate,
            currentQuality: currentQuality,
            estimatedBitrate: estimatedBitrate,
            compressionRatio: compressionRatio,
            streamHealth: streamHealth,
            totalFrames: frameTimestamps.count,
            codec: configuration.codec
        )
    }
    
    struct StreamStatistics {
        let targetFrameRate: Double
        let actualFrameRate: Double
        let currentQuality: PerformanceMonitor.StreamQuality
        let estimatedBitrate: Double
        let compressionRatio: Double
        let streamHealth: StreamHealth
        let totalFrames: Int
        let codec: StreamConfiguration.VideoCodec
    }
}
