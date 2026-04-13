import Foundation
import UIKit
import VideoToolbox

/// Processes frames from Meta glasses for transmission to Hermes Agent
/// Handles resizing, compression, and base64 encoding
class VisionFrameProcessor {
    
    // MARK: - Configuration
    struct Configuration {
        var targetSize: CGSize = CGSize(width: 640, height: 480)
        var compressionQuality: CGFloat = 0.75
        var maxFileSizeKB: Int = 200
        var format: FrameFormat = .jpeg
        
        enum FrameFormat {
            case jpeg
            case hevc  // For future use with HEVC streaming
        }
    }
    
    // MARK: - Properties
    private let configuration: Configuration
    private let processingQueue = DispatchQueue(label: "com.hermespecs.frameprocessing", qos: .userInitiated)
    
    // MARK: - Initialization
    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - Frame Processing
    
    /// Processes a CMSampleBuffer (from camera) into a transmittable format
    func processFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (Result<ProcessedFrame, FrameProcessingError>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Convert CMSampleBuffer to UIImage
                guard let image = self.convertSampleBufferToUIImage(sampleBuffer) else {
                    throw FrameProcessingError.conversionFailed
                }
                
                // Resize image
                let resizedImage = self.resizeImage(image, to: self.configuration.targetSize)
                
                // Compress to JPEG
                guard let jpegData = resizedImage.jpegData(compressionQuality: self.configuration.compressionQuality) else {
                    throw FrameProcessingError.compressionFailed
                }
                
                // Check file size and adjust if needed
                let finalData = try self.adjustQualityIfNeeded(data: jpegData, image: resizedImage)
                
                // Base64 encode
                let base64String = finalData.base64EncodedString()
                
                let processedFrame = ProcessedFrame(
                    base64Data: base64String,
                    mimeType: "image/jpeg",
                    width: resizedImage.size.width,
                    height: resizedImage.size.height,
                    fileSize: finalData.count
                )
                
                DispatchQueue.main.async {
                    completion(.success(processedFrame))
                }
                
            } catch let error as FrameProcessingError {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.unknown(error)))
                }
            }
        }
    }
    
    /// Processes a UIImage directly (for photo capture mode)
    func processUIImage(_ image: UIImage, completion: @escaping (Result<ProcessedFrame, FrameProcessingError>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Resize image
                let resizedImage = self.resizeImage(image, to: self.configuration.targetSize)
                
                // Compress to JPEG
                guard let jpegData = resizedImage.jpegData(compressionQuality: self.configuration.compressionQuality) else {
                    throw FrameProcessingError.compressionFailed
                }
                
                // Check file size
                let finalData = try self.adjustQualityIfNeeded(data: jpegData, image: resizedImage)
                
                // Base64 encode
                let base64String = finalData.base64EncodedString()
                
                let processedFrame = ProcessedFrame(
                    base64Data: base64String,
                    mimeType: "image/jpeg",
                    width: resizedImage.size.width,
                    height: resizedImage.size.height,
                    fileSize: finalData.count
                )
                
                DispatchQueue.main.async {
                    completion(.success(processedFrame))
                }
                
            } catch let error as FrameProcessingError {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.unknown(error)))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func convertSampleBufferToUIImage(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let size = image.size
        
        // Calculate aspect ratio
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    private func adjustQualityIfNeeded(data: Data, image: UIImage) throws -> Data {
        let maxSize = configuration.maxFileSizeKB * 1024
        var currentQuality = configuration.compressionQuality
        var currentData = data
        
        // If already small enough, return as-is
        if currentData.count <= maxSize {
            return currentData
        }
        
        // Reduce quality until size is acceptable (minimum quality 0.3)
        while currentData.count > maxSize && currentQuality > 0.3 {
            currentQuality -= 0.1
            guard let compressed = image.jpegData(compressionQuality: currentQuality) else {
                throw FrameProcessingError.compressionFailed
            }
            currentData = compressed
        }
        
        // If still too large, reduce dimensions
        if currentData.count > maxSize {
            let scaleFactor = sqrt(Double(maxSize) / Double(currentData.count))
            let newSize = CGSize(
                width: image.size.width * scaleFactor,
                height: image.size.height * scaleFactor
            )
            let smallerImage = resizeImage(image, to: newSize)
            
            guard let finalData = smallerImage.jpegData(compressionQuality: currentQuality) else {
                throw FrameProcessingError.compressionFailed
            }
            currentData = finalData
        }
        
        return currentData
    }
}

// MARK: - Supporting Types

struct ProcessedFrame {
    let base64Data: String
    let mimeType: String
    let width: CGFloat
    let height: CGFloat
    let fileSize: Int
    let timestamp: Date = Date()
}

enum FrameProcessingError: Error {
    case conversionFailed
    case compressionFailed
    case encodingFailed
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .conversionFailed:
            return "Failed to convert frame to image"
        case .compressionFailed:
            return "Failed to compress frame"
        case .encodingFailed:
            return "Failed to encode frame"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
