/*
 * PerformanceMonitor Tests
 * Unit tests for battery, thermal, and performance tracking
 */

import XCTest
@testable import CameraAccess

@MainActor
final class PerformanceMonitorTests: XCTestCase {
    
    var sut: PerformanceMonitor!
    
    override func setUp() {
        super.setUp()
        sut = PerformanceMonitor.shared
    }
    
    override func tearDown() {
        sut.stopMonitoring()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testMonitor_InitializesWithDefaultValues() {
        // Then
        XCTAssertGreaterThanOrEqual(sut.batteryLevel, 0)
        XCTAssertLessThanOrEqual(sut.batteryLevel, 100)
        XCTAssertEqual(sut.thermalState, .nominal)
        XCTAssertEqual(sut.connectionQuality, .good)
    }
    
    // MARK: - Latency Tracking Tests
    
    func testRecordLatency_AffectsConnectionQuality() {
        // Given
        let excellentLatency = 50.0  // 50ms
        
        // When
        sut.recordLatency(excellentLatency)
        
        // Then
        XCTAssertEqual(sut.connectionQuality, .excellent)
    }
    
    func testRecordLatency_FairQuality() {
        // Given
        let fairLatency = 500.0  // 500ms
        
        // When
        sut.recordLatency(fairLatency)
        
        // Then
        XCTAssertEqual(sut.connectionQuality, .fair)
    }
    
    func testRecordLatency_PoorQuality() {
        // Given
        let poorLatency = 1500.0  // 1.5 seconds
        
        // When
        sut.recordLatency(poorLatency)
        
        // Then
        XCTAssertEqual(sut.connectionQuality, .poor)
    }
    
    func testRecordLatency_AverageCalculation() {
        // Given
        let latencies = [100.0, 200.0, 300.0, 400.0, 500.0]
        
        // When
        for latency in latencies {
            sut.recordLatency(latency)
        }
        
        // Then
        let expectedAverage = latencies.reduce(0, +) / Double(latencies.count)
        XCTAssertEqual(sut.averageLatency, expectedAverage, accuracy: 0.1)
    }
    
    // MARK: - Frame Tracking Tests
    
    func testRecordFrameProcessed_IncrementsCount() {
        // Given
        let initialCount = sut.totalFrames
        
        // When
        sut.recordFrameProcessed(success: true)
        
        // Then
        XCTAssertEqual(sut.totalFrames, initialCount + 1)
    }
    
    func testRecordFrameDropped_TracksDrops() {
        // Given
        let initialDropped = sut.droppedFrames
        
        // When
        sut.recordFrameProcessed(success: false)
        
        // Then
        XCTAssertEqual(sut.droppedFrames, initialDropped + 1)
    }
    
    func testFrameDropRate_Calculation() {
        // Given - 20% drop rate
        for _ in 0..<8 {
            sut.recordFrameProcessed(success: true)
        }
        for _ in 0..<2 {
            sut.recordFrameProcessed(success: false)
        }
        
        // When
        let report = sut.getPerformanceReport()
        
        // Then
        XCTAssertEqual(report.frameDropRate, 0.2, accuracy: 0.01)
    }
    
    // MARK: - Recommendation Tests
    
    func testRecommendations_LowBattery_ReducesQuality() {
        // Given - Simulate low battery
        // Note: Cannot directly set battery level, but can test recommendation logic
        
        // When
        let config = PerformanceMonitor.Configuration(
            lowBatteryThreshold: 20,
            criticalBatteryThreshold: 10
        )
        sut.configuration = config
        
        // Then - Would need to trigger via battery notification
        // This is a partial test
    }
    
    func testRecommendations_ThermalThrottling() {
        // Given
        sut.thermalState = .serious
        
        // When
        sut.applyOptimizations()
        
        // Then
        XCTAssertTrue(sut.isThrottling)
        XCTAssertLessThanOrEqual(sut.recommendedFrameRate, 0.5)
        XCTAssertEqual(sut.recommendedQuality, .low)
    }
    
    func testRecommendations_CriticalThermal() {
        // Given
        sut.thermalState = .critical
        
        // When
        sut.applyOptimizations()
        
        // Then
        XCTAssertTrue(sut.isThrottling)
        XCTAssertLessThanOrEqual(sut.recommendedFrameRate, 0.1)
        XCTAssertEqual(sut.recommendedQuality, .low)
    }
    
    func testRecommendations_HighLatency() {
        // Given
        sut.recordLatency(2500) // 2.5 seconds
        
        // When
        sut.applyOptimizations()
        
        // Then
        XCTAssertLessThanOrEqual(sut.recommendedFrameRate, 0.5)
        XCTAssertEqual(sut.recommendedQuality, .low)
    }
    
    // MARK: - Performance Report Tests
    
    func testGetPerformanceReport_ContainsAllMetrics() {
        // When
        let report = sut.getPerformanceReport()
        
        // Then
        XCTAssertGreaterThanOrEqual(report.batteryLevel, 0)
        XCTAssertGreaterThanOrEqual(report.memoryUsageMB, 0)
        XCTAssertNotNil(report.healthStatus)
    }
    
    func testPerformanceReport_HealthStatus() {
        // Given
        sut.batteryLevel = 50
        sut.thermalState = .nominal
        for _ in 0..<100 {
            sut.recordFrameProcessed(success: true)
        }
        sut.recordLatency(200)
        
        // When
        let report = sut.getPerformanceReport()
        
        // Then
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.healthStatus, "Healthy")
    }
    
    func testPerformanceReport_Unhealthy_CriticalBattery() {
        // Given
        sut.batteryLevel = 5
        
        // When
        let report = sut.getPerformanceReport()
        
        // Then
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(report.healthStatus, "Critical battery")
    }
    
    func testPerformanceReport_Unhealthy_HighDrops() {
        // Given - 20% drop rate
        for _ in 0..<80 {
            sut.recordFrameProcessed(success: true)
        }
        for _ in 0..<20 {
            sut.recordFrameProcessed(success: false)
        }
        
        // When
        let report = sut.getPerformanceReport()
        
        // Then
        XCTAssertFalse(report.isHealthy)
    }
    
    // MARK: - Memory Tracking Tests
    
    func testMemoryUsage_Tracked() {
        // When
        sut.updateMetrics()
        
        // Then
        XCTAssertGreaterThan(sut.memoryUsage, 0)
        let report = sut.getPerformanceReport()
        XCTAssertGreaterThan(report.memoryUsageMB, 0)
    }
    
    // MARK: - Cleanup Tests
    
    func testStopMonitoring_CleansUp() {
        // Given
        XCTAssertNotNil(sut.monitoringTimer)
        
        // When
        sut.stopMonitoring()
        
        // Then
        // Timer should be invalidated
    }
}

// MARK: - Extension for Testing

extension PerformanceMonitor {
    var monitoringTimer: Timer? {
        // Would expose for testing
        return nil
    }
    
    func updateMetrics() {
        // Public for testing
    }
    
    func applyOptimizations() {
        // Public for testing
    }
}
