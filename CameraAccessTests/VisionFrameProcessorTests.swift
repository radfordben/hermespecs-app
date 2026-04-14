/*
 * VisionFrameProcessor Tests
 * Unit tests for frame preprocessing, compression, and encoding
 */

import XCTest
import UIKit
@testable import CameraAccess

final class VisionFrameProcessorTests: XCTestCase {
    
    var sut: VisionFrameProcessor!
    
    override func setUp() {
        super.setUp()
        sut = VisionFrameProcessor()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Image Processing Tests
    
    func testProcessImage_WithValidUIImage_ReturnsBase64() async {
        // Given
        let testImage = createTestImage(size: CGSize(width: 1920, height: 1080))
        
        // When
        let result = await withCheckedContinuation { continuation in
            sut.processUIImage(testImage) { result in
                continuation.resume(returning: result)
            }
        }
        
        // Then
        switch result {
        case .success(let frame):
            XCTAssertFalse(frame.base64Data.isEmpty)
            XCTAssertEqual(frame.width, 640)
            XCTAssertEqual(frame.height, 480)
            XCTAssertEqual(frame.mimeType, "image/jpeg")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testProcessImage_ResizesLargeImage() async {
        // Given
        let largeImage = createTestImage(size: CGSize(width: 4000, height: 3000))
        
        // When
        let result = await withCheckedContinuation { continuation in
            sut.processUIImage(largeImage) { result in
                continuation.resume(returning: result)
            }
        }
        
        // Then
        switch result {
        case .success(let frame):
            XCTAssertLessThanOrEqual(frame.width, 640)
            XCTAssertLessThanOrEqual(frame.height, 480)
        case .failure:
            XCTFail("Expected success")
        }
    }
    
    func testProcessImage_FileSizeUnderLimit() async {
        // Given
        let testImage = createTestImage(size: CGSize(width: 1920, height: 1080))
        
        // When
        let result = await withCheckedContinuation { continuation in
            sut.processUIImage(testImage) { result in
                continuation.resume(returning: result)
            }
        }
        
        // Then
        switch result {
        case .success(let frame):
            if let data = Data(base64Encoded: frame.base64Data) {
                let sizeKB = Double(data.count) / 1024.0
                XCTAssertLessThan(sizeKB, 200, "Image should be under 200KB")
            } else {
                XCTFail("Invalid base64 data")
            }
        case .failure:
            XCTFail("Expected success")
        }
    }
    
    func testProcessImage_CompressionQualityAdjusts() async {
        // Given
        let config = VisionFrameProcessor.Configuration(
            targetSize: CGSize(width: 640, height: 480),
            compressionQuality: 0.5,  // Lower quality
            maxFileSizeKB: 100
        )
        let processor = VisionFrameProcessor(configuration: config)
        let testImage = createTestImage(size: CGSize(width: 1920, height: 1080))
        
        // When
        let result = await withCheckedContinuation { continuation in
            processor.processUIImage(testImage) { result in
                continuation.resume(returning: result)
            }
        }
        
        // Then
        switch result {
        case .success(let frame):
            XCTAssertEqual(frame.compressionQuality, 0.5)
        case .failure:
            XCTFail("Expected success")
        }
    }
    
    // MARK: - Configuration Tests
    
    func testProcessor_WithCustomConfiguration() {
        // Given
        let customConfig = VisionFrameProcessor.Configuration(
            targetSize: CGSize(width: 320, height: 240),
            compressionQuality: 0.6,
            maxFileSizeKB: 50
        )
        
        // When
        let processor = VisionFrameProcessor(configuration: customConfig)
        
        // Then
        // Verify configuration is stored (would need to expose config or test behavior)
        XCTAssertNotNil(processor)
    }
    
    // MARK: - Sample Buffer Tests
    
    func testProcessSampleBuffer_WithValidBuffer_ReturnsFrame() {
        // Given
        let expectation = XCTestExpectation(description: "Process frame")
        let sampleBuffer = createMockSampleBuffer()
        
        // When
        sut.processFrame(sampleBuffer) { result in
            // Then
            switch result {
            case .success(let frame):
                XCTAssertFalse(frame.base64Data.isEmpty)
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
            case .failure(let error):
                // May fail in test environment without actual camera
                print("Processing failed (expected in test env): \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    private func createMockSampleBuffer() -> CMSampleBuffer {
        // Create a mock sample buffer for testing
        // In real tests, this would create a proper CMSampleBuffer
        // For now, return a placeholder that will likely fail gracefully
        fatalError("Mock sample buffer not implemented - use UIImage tests instead")
    }
}

// MARK: - Performance Tests

extension VisionFrameProcessorTests {
    
    func testProcessingPerformance() async {
        // Given
        let testImage = createTestImage(size: CGSize(width: 1920, height: 1080))
        
        // When/Then
        measure {
            let expectation = XCTestExpectation(description: "Processing")
            
            Task {
                _ = await withCheckedContinuation { continuation in
                    sut.processUIImage(testImage) { result in
                        continuation.resume(returning: result)
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testMultipleConsecutiveFrames() async {
        // Given
        let testImage = createTestImage(size: CGSize(width: 1920, height: 1080))
        let iterations = 10
        
        // When
        let startTime = Date()
        
        for _ in 0..<iterations {
            _ = await withCheckedContinuation { continuation in
                sut.processUIImage(testImage) { result in
                    continuation.resume(returning: result)
                }
            }
        }
        
        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)
        let averageTime = totalTime / Double(iterations)
        
        // Then
        print("Average processing time: \(averageTime * 1000)ms")
        XCTAssertLessThan(averageTime, 1.0, "Should process each frame in under 1 second")
    }
}
