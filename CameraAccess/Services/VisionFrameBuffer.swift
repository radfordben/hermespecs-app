import Foundation
import UIKit

/// Thread-safe buffer for caching recent video frames
/// Allows quick access to recent visual context when user speaks
class VisionFrameBuffer {
    
    // MARK: - Configuration
    struct Configuration {
        var maxBufferSize: Int = 10  // Keep last 10 frames
        var maxAgeSeconds: TimeInterval = 5.0  // Discard frames older than 5 seconds
    }
    
    // MARK: - Properties
    private let configuration: Configuration
    private var buffer: [BufferedFrame] = []
    private let queue = DispatchQueue(label: "com.hermespecs.framebuffer", qos: .userInitiated)
    private let processor: VisionFrameProcessor
    
    // MARK: - Types
    struct BufferedFrame {
        let processedFrame: ProcessedFrame
        let originalTimestamp: Date
    }
    
    // MARK: - Initialization
    init(configuration: Configuration = Configuration(),
         processor: VisionFrameProcessor = VisionFrameProcessor()) {
        self.configuration = configuration
        self.processor = processor
    }
    
    // MARK: - Public Methods
    
    /// Adds a processed frame to the buffer
    func addFrame(_ frame: ProcessedFrame) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let bufferedFrame = BufferedFrame(
                processedFrame: frame,
                originalTimestamp: frame.timestamp
            )
            
            self.buffer.append(bufferedFrame)
            self.cleanupOldFrames()
            
            // Limit buffer size
            while self.buffer.count > self.configuration.maxBufferSize {
                self.buffer.removeFirst()
            }
        }
    }
    
    /// Gets the most recent frame from the buffer
    func getLatestFrame() -> ProcessedFrame? {
        return queue.sync {
            cleanupOldFrames()
            return buffer.last?.processedFrame
        }
    }
    
    /// Gets the most recent frame that meets minimum quality criteria
    func getBestFrame(minFileSizeKB: Int = 10) -> ProcessedFrame? {
        return queue.sync {
            cleanupOldFrames()
            
            // Return the most recent frame that meets minimum size (not too compressed)
            return buffer.reversed().first { frame in
                frame.processedFrame.fileSize >= (minFileSizeKB * 1024)
            }?.processedFrame ?? buffer.last?.processedFrame
        }
    }
    
    /// Gets all frames in the buffer (newest first)
    func getAllFrames() -> [ProcessedFrame] {
        return queue.sync {
            cleanupOldFrames()
            return buffer.reversed().map { $0.processedFrame }
        }
    }
    
    /// Clears all frames from the buffer
    func clearBuffer() {
        queue.async { [weak self] in
            self?.buffer.removeAll()
        }
    }
    
    /// Returns the current number of frames in the buffer
    var frameCount: Int {
        return queue.sync {
            cleanupOldFrames()
            return buffer.count
        }
    }
    
    /// Checks if buffer has any valid frames
    var hasFrames: Bool {
        return frameCount > 0
    }
    
    /// Processes and adds a CMSampleBuffer directly
    func processAndAddFrame(_ sampleBuffer: CMSampleBuffer, completion: ((Bool) -> Void)? = nil) {
        processor.processFrame(sampleBuffer) { [weak self] result in
            switch result {
            case .success(let frame):
                self?.addFrame(frame)
                completion?(true)
            case .failure(let error):
                print("Frame processing error: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
    
    /// Processes and adds a UIImage directly
    func processAndAddImage(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        processor.processUIImage(image) { [weak self] result in
            switch result {
            case .success(let frame):
                self?.addFrame(frame)
                completion?(true)
            case .failure(let error):
                print("Image processing error: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
    
    /// Captures current frame with vision context for command processing
    /// Returns the frame that should be sent with a voice command
    func captureFrameForCommand() -> ProcessedFrame? {
        return getBestFrame(minFileSizeKB: 15)
    }
    
    // MARK: - Private Methods
    
    private func cleanupOldFrames() {
        let cutoffTime = Date().addingTimeInterval(-configuration.maxAgeSeconds)
        buffer.removeAll { $0.originalTimestamp < cutoffTime }
    }
}

// MARK: - Convenience Extensions

extension VisionFrameBuffer {
    /// Starts automatic frame capture from a video stream
    /// Call this when glasses streaming begins
    func startAutoCapture(from streamManager: StreamSessionViewModel, interval: TimeInterval = 1.0) -> Timer? {
        // Note: This is a simplified version. In production, you'd integrate with StreamManager
        // to get frames from the Meta glasses camera stream
        
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // In actual implementation, this would grab the current frame from StreamManager
            // For now, this is a placeholder
            print("Auto-capture tick - would capture frame here")
        }
        
        return timer
    }
    
    /// Stops auto capture
    func stopAutoCapture(_ timer: Timer?) {
        timer?.invalidate()
    }
}
