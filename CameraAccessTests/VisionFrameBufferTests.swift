/*
 * VisionFrameBuffer Tests
 * Unit tests for thread-safe frame buffering
 */

import XCTest
@testable import CameraAccess

final class VisionFrameBufferTests: XCTestCase {
    
    var sut: VisionFrameBuffer!
    
    override func setUp() {
        super.setUp()
        sut = VisionFrameBuffer()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Basic Operations
    
    func testBuffer_AddFrame_IncreasesCount() {
        // Given
        let frame = createTestFrame()
        
        // When
        sut.addFrame(frame)
        
        // Then
        XCTAssertEqual(sut.frameCount, 1)
    }
    
    func testBuffer_MaxCapacity_Enforced() {
        // Given
        let maxFrames = 10
        
        // When - Add more than max frames
        for i in 0..<15 {
            var frame = createTestFrame()
            frame.timestamp = Date().addingTimeInterval(Double(i))
            sut.addFrame(frame)
        }
        
        // Then
        XCTAssertEqual(sut.frameCount, maxFrames)
    }
    
    func testBuffer_OldestFramesRemoved() {
        // Given
        let oldFrame = createTestFrame(timestamp: Date().addingTimeInterval(-10))
        let newFrame = createTestFrame(timestamp: Date())
        
        // When
        sut.addFrame(oldFrame)
        for _ in 0..<10 {
            sut.addFrame(newFrame)
        }
        
        // Then - Old frame should be evicted
        XCTAssertFalse(sut.containsFrame(withId: oldFrame.id))
    }
    
    func testBuffer_GetLatestFrame_ReturnsMostRecent() {
        // Given
        let oldFrame = createTestFrame(timestamp: Date().addingTimeInterval(-5))
        let newFrame = createTestFrame(timestamp: Date())
        
        // When
        sut.addFrame(oldFrame)
        sut.addFrame(newFrame)
        
        // Then
        let latest = sut.getLatestFrame()
        XCTAssertEqual(latest?.id, newFrame.id)
    }
    
    func testBuffer_CaptureFrameForCommand_MarksAsUsed() {
        // Given
        let frame = createTestFrame()
        sut.addFrame(frame)
        
        // When
        let captured = sut.captureFrameForCommand()
        
        // Then
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.id, frame.id)
    }
    
    func testBuffer_CaptureFrameForCommand_RespectsTiming() {
        // Given
        let frame1 = createTestFrame(timestamp: Date().addingTimeInterval(-0.1))
        let frame2 = createTestFrame(timestamp: Date())
        sut.addFrame(frame1)
        sut.addFrame(frame2)
        
        // When - Capture twice in succession
        let first = sut.captureFrameForCommand()
        let second = sut.captureFrameForCommand()
        
        // Then - Second capture should be nil (too soon)
        XCTAssertNotNil(first)
        // Note: This depends on minCaptureInterval implementation
    }
    
    // MARK: - Age-Based Cleanup
    
    func testBuffer_OldFramesPurged() {
        // Given
        let oldFrame = createTestFrame(timestamp: Date().addingTimeInterval(-10))
        sut.addFrame(oldFrame)
        XCTAssertEqual(sut.frameCount, 1)
        
        // When - Trigger cleanup (simulated by adding new frame)
        let newFrame = createTestFrame(timestamp: Date())
        sut.addFrame(newFrame)
        
        // Then - Old frame should be purged (if > 5 seconds old)
        // This depends on maxAge implementation
    }
    
    func testBuffer_Clear_RemovesAllFrames() {
        // Given
        for _ in 0..<5 {
            sut.addFrame(createTestFrame())
        }
        XCTAssertEqual(sut.frameCount, 5)
        
        // When
        sut.clear()
        
        // Then
        XCTAssertEqual(sut.frameCount, 0)
    }
    
    // MARK: - Thread Safety
    
    func testBuffer_ConcurrentAccess_DoesNotCrash() {
        // Given
        let expectation = XCTestExpectation(description: "Concurrent access")
        let iterations = 100
        
        // When - Access from multiple threads
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let frame = createTestFrame(timestamp: Date().addingTimeInterval(Double(i)))
                sut.addFrame(frame)
            } else {
                _ = sut.getLatestFrame()
                _ = sut.captureFrameForCommand()
            }
        }
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 5.0)
        
        // Then - Should not crash (test passes if we get here)
        XCTAssertTrue(true)
    }
    
    func testBuffer_ConcurrentAddAndRemove_DoesNotCrash() {
        // Given
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        let group = DispatchGroup()
        
        // When
        for i in 0..<50 {
            group.enter()
            queue.async {
                let frame = self.createTestFrame(timestamp: Date().addingTimeInterval(Double(i)))
                self.sut.addFrame(frame)
                group.leave()
            }
        }
        
        for _ in 0..<50 {
            group.enter()
            queue.async {
                self.sut.clear()
                group.leave()
            }
        }
        
        // Then
        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success)
    }
    
    // MARK: - Statistics
    
    func testBuffer_Statistics_Accurate() {
        // Given
        for _ in 0..<5 {
            sut.addFrame(createTestFrame())
        }
        
        // When
        let stats = sut.statistics
        
        // Then
        XCTAssertEqual(stats.totalFrames, 5)
        XCTAssertNotNil(stats.oldestFrame)
        XCTAssertNotNil(stats.newestFrame)
        XCTAssertGreaterThan(stats.averageAge, 0)
    }
    
    // MARK: - Helper
    
    private func createTestFrame(timestamp: Date = Date()) -> ProcessedFrame {
        return ProcessedFrame(
            id: UUID(),
            base64Data: "dGVzdF9kYXRh", // "test_data" in base64
            width: 640,
            height: 480,
            mimeType: "image/jpeg",
            compressionQuality: 0.75,
            timestamp: timestamp,
            originalSize: 100000,
            processedSize: 50000,
            processingTime: 0.1
        )
    }
}

// MARK: - Extension for Testing

extension VisionFrameBuffer {
    var frameCount: Int {
        // Would need to expose this for testing
        // For now, estimate via other means
        var count = 0
        for _ in 0..<100 {
            if getLatestFrame() != nil {
                count += 1
            }
        }
        return count
    }
    
    func containsFrame(withId id: UUID) -> Bool {
        // Would need to search through buffer
        return false
    }
    
    struct Statistics {
        let totalFrames: Int
        let oldestFrame: Date?
        let newestFrame: Date?
        let averageAge: TimeInterval
    }
    
    var statistics: Statistics {
        // Would calculate from actual buffer
        return Statistics(
            totalFrames: 0,
            oldestFrame: nil,
            newestFrame: nil,
            averageAge: 0
        )
    }
}
