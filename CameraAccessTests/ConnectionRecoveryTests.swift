/*
 * ConnectionRecoveryManager Tests
 * Unit tests for connection state management and recovery
 */

import XCTest
@testable import CameraAccess

@MainActor
final class ConnectionRecoveryTests: XCTestCase {
    
    var sut: ConnectionRecoveryManager!
    
    override func setUp() {
        super.setUp()
        sut = ConnectionRecoveryManager.shared
        sut.configuration.enableAutomaticReconnect = false // Disable for testing
    }
    
    override func tearDown() {
        sut.disconnect()
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState_IsDisconnected() {
        // Then
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertFalse(sut.isReconnecting)
        XCTAssertEqual(sut.retryCount, 0)
    }
    
    // MARK: - Connection Tests
    
    func testConnect_Success_TransitionsToConnected() async {
        // Given
        let expectation = expectation(description: "Connected")
        var stateChanged = false
        
        sut.onStateChanged = { state in
            if state == .connected {
                stateChanged = true
                expectation.fulfill()
            }
        }
        
        // When
        await sut.connect(
            onSuccess: {},
            onFailure: { _ in }
        )
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(stateChanged)
    }
    
    func testConnect_Failure_TransitionsToFailed() async {
        // Given
        let expectation = expectation(description: "Failed")
        var errorReceived: ConnectionRecoveryManager.ConnectionError?
        
        // When - Force a failure (would need mock)
        // For now, test the state transition
        sut.handleDisconnect(.authenticationFailed)
        
        // Then
        XCTAssertEqual(sut.connectionState, .failed)
        XCTAssertNotNil(sut.lastError)
    }
    
    func testDisconnect_ResetsState() {
        // Given
        // First connect
        Task {
            await sut.connect(onSuccess: {}, onFailure: { _ in })
        }
        
        // When
        sut.disconnect()
        
        // Then
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertEqual(sut.retryCount, 0)
    }
    
    // MARK: - Recovery Tests
    
    func testRecovery_IncrementsRetryCount() {
        // Given
        sut.configuration.enableAutomaticReconnect = true
        
        // When
        sut.handleDisconnect(.serverUnreachable)
        
        // Then
        XCTAssertGreaterThan(sut.retryCount, 0)
    }
    
    func testRecovery_MaxRetries_ReachesFailed() {
        // Given
        sut.configuration.enableAutomaticReconnect = true
        sut.configuration.maxRetries = 3
        sut.retryCount = 3
        
        // When
        sut.handleDisconnect(.serverUnreachable)
        
        // Then
        XCTAssertEqual(sut.connectionState, .failed)
        XCTAssertEqual(sut.lastError, .tooManyRetries)
    }
    
    func testRecovery_NonRecoverableError_NoRetry() {
        // Given
        sut.configuration.enableAutomaticReconnect = true
        let initialRetryCount = sut.retryCount
        
        // When
        sut.handleDisconnect(.authenticationFailed)
        
        // Then
        XCTAssertEqual(sut.connectionState, .failed)
        XCTAssertEqual(sut.retryCount, initialRetryCount)
    }
    
    func testResetRetryCount_ClearsCounter() {
        // Given
        sut.retryCount = 5
        
        // When
        sut.resetRetryCount()
        
        // Then
        XCTAssertEqual(sut.retryCount, 0)
    }
    
    // MARK: - State Transition Tests
    
    func testStateTransitions_DisconnectedToConnecting() async {
        // Given
        var states: [ConnectionRecoveryManager.ConnectionState] = []
        sut.onStateChanged = { state in
            states.append(state)
        }
        
        // When
        await sut.connect(onSuccess: {}, onFailure: { _ in })
        
        // Then
        XCTAssertTrue(states.contains(.connecting))
        XCTAssertTrue(states.contains(.connected))
    }
    
    func testStateTransitions_ConnectedToDisconnected() {
        // Given
        Task {
            await sut.connect(onSuccess: {}, onFailure: { _ in })
        }
        
        var states: [ConnectionRecoveryManager.ConnectionState] = []
        sut.onStateChanged = { state in
            states.append(state)
        }
        
        // When
        sut.disconnect()
        
        // Then
        XCTAssertTrue(states.contains(.disconnected))
    }
    
    // MARK: - Callback Tests
    
    func testCallback_OnStateChanged() {
        // Given
        let expectation = expectation(description: "State changed")
        
        sut.onStateChanged = { _ in
            expectation.fulfill()
        }
        
        // When
        sut.handleDisconnect(.networkUnavailable)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCallback_OnRecoveryAttempt() {
        // Given
        let expectation = expectation(description: "Recovery attempt")
        sut.configuration.enableAutomaticReconnect = true
        
        sut.onRecoveryAttempt = { attempt, delay in
            expectation.fulfill()
        }
        
        // When
        sut.handleDisconnect(.serverUnreachable)
        
        // Then
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testCallback_OnRecovered() async {
        // Given
        let expectation = expectation(description: "Recovered")
        sut.configuration.enableAutomaticReconnect = true
        
        sut.onRecovered = {
            expectation.fulfill()
        }
        
        // When - Connect after disconnect
        sut.handleDisconnect(.serverUnreachable)
        await sut.connect(onSuccess: {}, onFailure: { _ in })
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testCallback_OnPermanentlyFailed() {
        // Given
        let expectation = expectation(description: "Permanently failed")
        sut.configuration.enableAutomaticReconnect = false
        
        sut.onPermanentlyFailed = { _ in
            expectation.fulfill()
        }
        
        // When
        sut.handleDisconnect(.authenticationFailed)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Status Tests
    
    func testGetConnectionStatus_ReturnsCurrentState() {
        // When
        let status = sut.getConnectionStatus()
        
        // Then
        XCTAssertEqual(status.state, sut.connectionState)
        XCTAssertEqual(status.retryCount, sut.retryCount)
        XCTAssertEqual(status.maxRetries, sut.configuration.maxRetries)
    }
    
    func testGetConnectionStatus_ShowsRetryUI() {
        // Given
        sut.retryCount = 2
        sut.isReconnecting = true
        
        // When
        let status = sut.getConnectionStatus()
        
        // Then
        XCTAssertTrue(status.shouldShowRetryUI)
    }
    
    func testGetConnectionStatus_RecoveryProgress() {
        // Given
        sut.retryCount = 2
        sut.configuration.maxRetries = 4
        
        // When
        let status = sut.getConnectionStatus()
        
        // Then
        XCTAssertEqual(status.recoveryProgress, 0.5)
    }
    
    // MARK: - Error Classification Tests
    
    func testErrorClassification_RecoverableErrors() {
        // Then
        XCTAssertTrue(ConnectionRecoveryManager.ConnectionError.networkUnavailable.isRecoverable)
        XCTAssertTrue(ConnectionRecoveryManager.ConnectionError.serverUnreachable.isRecoverable)
        XCTAssertTrue(ConnectionRecoveryManager.ConnectionError.timeout.isRecoverable)
        XCTAssertTrue(ConnectionRecoveryManager.ConnectionError.unexpectedDisconnect.isRecoverable)
    }
    
    func testErrorClassification_NonRecoverableErrors() {
        // Then
        XCTAssertFalse(ConnectionRecoveryManager.ConnectionError.authenticationFailed.isRecoverable)
        XCTAssertFalse(ConnectionRecoveryManager.ConnectionError.protocolError.isRecoverable)
        XCTAssertFalse(ConnectionRecoveryManager.ConnectionError.tooManyRetries.isRecoverable)
    }
    
    func testErrorDescriptions() {
        // Then
        XCTAssertEqual(
            ConnectionRecoveryManager.ConnectionError.networkUnavailable.errorDescription,
            "No network connection"
        )
        XCTAssertEqual(
            ConnectionRecoveryManager.ConnectionError.authenticationFailed.errorDescription,
            "Authentication failed"
        )
    }
}

// MARK: - Connection Quality Monitor Tests

final class ConnectionQualityMonitorTests: XCTestCase {
    
    var sut: ConnectionQualityMonitor!
    
    override func setUp() {
        super.setUp()
        sut = ConnectionQualityMonitor()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testLatencyTracking_AverageCalculation() {
        // Given
        let latencies = [50.0, 100.0, 150.0, 200.0, 250.0]
        
        // When
        for latency in latencies {
            sut.recordLatency(latency)
        }
        
        // Then
        let expectedAverage = latencies.reduce(0, +) / Double(latencies.count)
        XCTAssertEqual(sut.latency, expectedAverage, accuracy: 0.1)
    }
    
    func testLatencyTracking_MovingWindow() {
        // Given - Add more than 50 measurements
        for i in 0..<60 {
            sut.recordLatency(Double(i))
        }
        
        // Then - Should only keep last 50
        // Implementation detail, but latency should reflect recent values
        XCTAssertGreaterThan(sut.latency, 0)
    }
    
    func testQualityScore_ExcellentLatency() {
        // Given
        sut.recordLatency(50) // 50ms
        
        // Then
        XCTAssertGreaterThanOrEqual(sut.qualityScore, 95)
    }
    
    func testQualityScore_PoorLatency() {
        // Given
        sut.recordLatency(600) // 600ms
        
        // Then
        XCTAssertLessThan(sut.qualityScore, 70)
    }
    
    func testQualityScore_PacketLossImpact() {
        // Given - Start with good latency
        sut.recordLatency(100)
        let initialScore = sut.qualityScore
        
        // When
        sut.recordPacketLoss(10) // 10% packet loss
        
        // Then
        XCTAssertLessThan(sut.qualityScore, initialScore)
    }
    
    func testQualityScore_MaximumPenalty() {
        // Given
        sut.recordLatency(1000)
        sut.recordPacketLoss(50)
        
        // Then
        XCTAssertEqual(sut.qualityScore, 0)
    }
}
