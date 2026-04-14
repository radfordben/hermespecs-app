/*
 * ToolExecutors Tests
 * Unit tests for local tool execution (Reminders, Notes, Timer, etc.)
 */

import XCTest
import EventKit
@testable import CameraAccess

@MainActor
final class ToolExecutorsTests: XCTestCase {
    
    // MARK: - Reminders Executor Tests
    
    func testRemindersExecutor_ValidateParameters_MissingTitle() {
        // Given
        let executor = RemindersExecutor()
        let params: [String: Any] = [:]
        
        // When
        let missing = executor.validateParameters(params)
        
        // Then
        XCTAssertTrue(missing.keys.contains("title"))
        XCTAssertEqual(missing["title"], "What should I remind you about?")
    }
    
    func testRemindersExecutor_ValidateParameters_HasTitle() {
        // Given
        let executor = RemindersExecutor()
        let params: [String: Any] = ["title": "Buy milk"]
        
        // When
        let missing = executor.validateParameters(params)
        
        // Then
        XCTAssertEqual(missing.count, 0)
    }
    
    func testRemindersExecutor_Execution_RequiresPermission() async {
        // Given
        let executor = RemindersExecutor()
        let params: [String: Any] = ["title": "Test reminder"]
        
        // When - Execute without permission (will fail in test env)
        do {
            _ = try await executor.execute(parameters: params)
            // In simulator without permission, this might fail
        } catch {
            // Expected in test environment without EventKit auth
            XCTAssertTrue(error is ToolExecutionError)
        }
    }
    
    // MARK: - Timer Executor Tests
    
    func testTimerExecutor_ValidateParameters_MissingDuration() {
        // Given
        let executor = TimerExecutor()
        let params: [String: Any] = [:]
        
        // When
        let missing = executor.validateParameters(params)
        
        // Then
        XCTAssertTrue(missing.keys.contains("duration"))
    }
    
    func testTimerExecutor_ParseDuration_Minutes() async {
        // Given
        let executor = TimerExecutor()
        let params: [String: Any] = [
            "duration": "5 minutes",
            "label": "Test timer"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success ?? false)
        XCTAssertTrue(result?.message.contains("5 minutes") ?? false)
    }
    
    func testTimerExecutor_ParseDuration_Hours() async {
        // Given
        let executor = TimerExecutor()
        let params: [String: Any] = [
            "duration": "2 hours",
            "label": "Long timer"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("2 hours") ?? false)
    }
    
    func testTimerExecutor_ParseDuration_Seconds() async {
        // Given
        let executor = TimerExecutor()
        let params: [String: Any] = [
            "duration": "30 seconds"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("30 seconds") ?? false)
    }
    
    // MARK: - iMessage Executor Tests
    
    func testiMessageExecutor_ValidateParameters_MissingFields() {
        // Given
        let executor = iMessageExecutor()
        let params: [String: Any] = [:]
        
        // When
        let missing = executor.validateParameters(params)
        
        // Then
        XCTAssertEqual(missing.count, 2)
        XCTAssertTrue(missing.keys.contains("recipient"))
        XCTAssertTrue(missing.keys.contains("message"))
    }
    
    func testiMessageExecutor_Execution_CreatesSMSURL() async {
        // Given
        let executor = iMessageExecutor()
        let params: [String: Any] = [
            "recipient": "+1234567890",
            "message": "Hello world"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success ?? false)
        XCTAssertTrue(result?.data?.keys.contains("sms_url") ?? false)
    }
    
    func testiMessageExecutor_Execution_EncodesMessage() async {
        // Given
        let executor = iMessageExecutor()
        let params: [String: Any] = [
            "recipient": "+1234567890",
            "message": "Hello & goodbye!"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        if let data = result?.data,
           let url = data["sms_url"] as? String {
            XCTAssertFalse(url.contains(" "), "URL should be encoded")
            XCTAssertFalse(url.contains("&"), "Special chars should be encoded")
        }
    }
    
    // MARK: - Music Control Executor Tests
    
    func testMusicControlExecutor_Play() async {
        // Given
        let executor = MusicControlExecutor()
        let params: [String: Any] = ["action": "play"]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("Playing") ?? false)
    }
    
    func testMusicControlExecutor_Pause() async {
        // Given
        let executor = MusicControlExecutor()
        let params: [String: Any] = ["action": "pause"]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("paused") ?? false)
    }
    
    func testMusicControlExecutor_Skip() async {
        // Given
        let executor = MusicControlExecutor()
        let params: [String: Any] = ["action": "skip"]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("next") ?? false)
    }
    
    func testMusicControlExecutor_PlayQuery() async {
        // Given
        let executor = MusicControlExecutor()
        let params: [String: Any] = [
            "action": "play",
            "query": "Taylor Swift"
        ]
        
        // When
        let result = try? await executor.execute(parameters: params)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("Taylor Swift") ?? false)
    }
    
    // MARK: - Voice Confirmation Manager Tests
    
    func testConfirmationManager_RequiresConfirmation_CommunicationTools() {
        // Given
        let manager = VoiceConfirmationManager.shared
        let tool = HermesTool(
            id: "imessage_send",
            name: "Send Message",
            description: "Send iMessage",
            category: .messaging,
            parameters: [],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: []
        )
        
        // When
        let requires = manager.requiresConfirmation(for: tool, parameters: [:])
        
        // Then
        XCTAssertTrue(requires)
    }
    
    func testConfirmationManager_RequiresConfirmation_DestructiveActions() {
        // Given
        let manager = VoiceConfirmationManager.shared
        let tool = HermesTool(
            id: "test_tool",
            name: "Test",
            description: "Test",
            category: .utilities,
            parameters: [],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: []
        )
        
        // When
        let requires = manager.requiresConfirmation(
            for: tool,
            parameters: ["action": "delete"]
        )
        
        // Then
        XCTAssertTrue(requires)
    }
    
    func testConfirmationManager_GeneratesConfirmationMessage() {
        // Given
        let manager = VoiceConfirmationManager.shared
        let tool = HermesTool(
            id: "imessage_send",
            name: "Send Message",
            description: "",
            category: .messaging,
            parameters: [],
            requiresConfirmation: true,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: []
        )
        
        // When
        let message = manager.generateConfirmationMessage(
            for: tool,
            parameters: [
                "recipient": "John",
                "message": "Running late"
            ]
        )
        
        // Then
        XCTAssertTrue(message.contains("John"))
        XCTAssertTrue(message.contains("Running late"))
    }
    
    func testConfirmationManager_GeneratesSuccessMessage() {
        // Given
        let manager = VoiceConfirmationManager.shared
        let tool = HermesTool(
            id: "reminders_add",
            name: "Add Reminder",
            description: "",
            category: .productivity,
            parameters: [],
            requiresConfirmation: false,
            voiceOptimized: true,
            localExecution: true,
            shortcuts: []
        )
        
        // When
        let message = manager.generateSuccessMessage(
            for: tool,
            parameters: ["title": "Buy groceries"]
        )
        
        // Then
        XCTAssertTrue(message.contains("Buy groceries"))
    }
}
