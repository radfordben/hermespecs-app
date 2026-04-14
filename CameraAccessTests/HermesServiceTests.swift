/*
 * HermesService Tests
 * Unit tests for WebSocket connection, authentication, and message handling
 */

import XCTest
@testable import CameraAccess

@MainActor
final class HermesServiceTests: XCTestCase {
    
    var sut: HermesService!
    var mockWebSocket: MockWebSocketProvider!
    
    override func setUp() {
        super.setUp()
        mockWebSocket = MockWebSocketProvider()
        sut = HermesService(webSocketProvider: mockWebSocket)
    }
    
    override func tearDown() {
        sut = nil
        mockWebSocket = nil
        super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testConnection_WithValidConfig_ReturnsConnected() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token_123",
            timeout: 10
        )
        mockWebSocket.shouldSucceed = true
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.connectionState, .connected)
    }
    
    func testConnection_WithInvalidURL_ReturnsFalse() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "not_a_valid_url",
            apiToken: "token",
            timeout: 10
        )
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sut.connectionState, .disconnected)
    }
    
    func testConnection_WithEmptyToken_ReturnsFalse() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "",
            timeout: 10
        )
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testDisconnect_CleansUpResources() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 10
        )
        _ = await sut.connect(configuration: config)
        
        // When
        sut.disconnect()
        
        // Then
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertTrue(mockWebSocket.wasClosed)
    }
    
    // MARK: - Message Tests
    
    func testSendCommand_SendsValidJSON() async throws {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 10
        )
        _ = await sut.connect(configuration: config)
        
        let command = "test command"
        
        // When
        try await sut.sendCommand(command)
        
        // Then
        XCTAssertEqual(mockWebSocket.sentMessages.count, 1)
        let sentData = mockWebSocket.sentMessages.first!
        let json = try JSONSerialization.jsonObject(with: sentData) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "command")
        XCTAssertEqual(json["command"] as? String, command)
    }
    
    func testSendVisionCommand_IncludesImageData() async throws {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 10
        )
        _ = await sut.connect(configuration: config)
        
        let request = HermesVisionRequest(
            command: "What is this?",
            imageData: "base64_image_data_here",
            imageMimeType: "image/jpeg",
            imageDimensions: ImageDimensions(width: 640, height: 480),
            context: VisionContext(
                cameraSource: "rayban_meta",
                lighting: nil,
                location: nil,
                previousContext: nil
            ),
            timestamp: Date()
        )
        
        // When
        try await sut.sendVisionRequest(request)
        
        // Then
        XCTAssertEqual(mockWebSocket.sentMessages.count, 1)
        let sentData = mockWebSocket.sentMessages.first!
        let json = try JSONSerialization.jsonObject(with: sentData) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "vision_command")
        XCTAssertNotNil(json["image_data"])
    }
    
    func testReceiveResponse_ParsesCorrectly() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 10
        )
        _ = await sut.connect(configuration: config)
        
        let responseJSON = """
        {
            "success": true,
            "message": "Test response",
            "tool_calls": [],
            "should_speak": true
        }
        """
        
        // When
        mockWebSocket.simulateReceive(message: responseJSON)
        
        // Then
        // Verify response was parsed and callback triggered
        // This would need async expectation in real test
    }
    
    // MARK: - Error Handling Tests
    
    func testConnectionTimeout_TriggersError() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 0.1  // Very short timeout
        )
        mockWebSocket.shouldTimeout = true
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sut.connectionState, .disconnected)
    }
    
    func testAuthenticationFailure_ReportsError() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "invalid_token",
            timeout: 10
        )
        mockWebSocket.shouldAuthenticate = false
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testReconnection_AfterDisconnect() async {
        // Given
        let config = HermesConfiguration(
            serverURL: "wss://test.hermes.ai",
            apiToken: "valid_token",
            timeout: 10
        )
        _ = await sut.connect(configuration: config)
        sut.disconnect()
        mockWebSocket.reset()
        
        // When
        let result = await sut.connect(configuration: config)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.connectionState, .connected)
    }
}

// MARK: - Mock WebSocket Provider

class MockWebSocketProvider: WebSocketProvider {
    var shouldSucceed = true
    var shouldTimeout = false
    var shouldAuthenticate = true
    var wasClosed = false
    var sentMessages: [Data] = []
    
    private var onReceive: ((String) -> Void)?
    
    func connect(url: URL, token: String) async throws {
        if shouldTimeout {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            throw HermesError.timeout
        }
        
        guard shouldSucceed else {
            throw HermesError.connectionFailed
        }
        
        guard shouldAuthenticate || !token.isEmpty else {
            throw HermesError.authenticationFailed
        }
    }
    
    func disconnect() {
        wasClosed = true
    }
    
    func send(_ data: Data) async throws {
        sentMessages.append(data)
    }
    
    func onReceive(_ handler: @escaping (String) -> Void) {
        onReceive = handler
    }
    
    func simulateReceive(message: String) {
        onReceive?(message)
    }
    
    func reset() {
        wasClosed = false
        sentMessages.removeAll()
    }
}
