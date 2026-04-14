/*
 * ToolRegistry Tests
 * Unit tests for tool registration, discovery, and search
 */

import XCTest
@testable import CameraAccess

final class ToolRegistryTests: XCTestCase {
    
    var sut: ToolRegistry!
    
    override func setUp() {
        super.setUp()
        sut = ToolRegistry.shared
    }
    
    override func tearDown() {
        // Reset state if needed
        super.tearDown()
    }
    
    // MARK: - Registration Tests
    
    func testToolRegistration_CountsAreCorrect() {
        // Then
        XCTAssertGreaterThan(sut.totalToolCount, 0, "Should have registered tools")
        
        let counts = sut.toolCountByCategory()
        XCTAssertGreaterThan(counts[.messaging, default: 0], 0, "Should have messaging tools")
        XCTAssertGreaterThan(counts[.productivity, default: 0], 0, "Should have productivity tools")
    }
    
    func testGetTool_WithValidID_ReturnsTool() {
        // When
        let tool = sut.getTool("reminders_add")
        
        // Then
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.name, "Add Reminder")
        XCTAssertEqual(tool?.category, .productivity)
    }
    
    func testGetTool_WithInvalidID_ReturnsNil() {
        // When
        let tool = sut.getTool("nonexistent_tool")
        
        // Then
        XCTAssertNil(tool)
    }
    
    func testGetAllTools_ReturnsAllTools() {
        // When
        let tools = sut.getAllTools()
        
        // Then
        XCTAssertEqual(tools.count, sut.totalToolCount)
    }
    
    func testGetToolsByCategory_ReturnsCorrectCategory() {
        // When
        let messagingTools = sut.getToolsByCategory(.messaging)
        
        // Then
        XCTAssertGreaterThan(messagingTools.count, 0)
        for tool in messagingTools {
            XCTAssertEqual(tool.category, .messaging)
        }
    }
    
    // MARK: - Search Tests
    
    func testSearchTools_WithMatchingQuery_ReturnsResults() {
        // When
        let results = sut.searchTools(query: "reminder")
        
        // Then
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.contains { $0.id == "reminders_add" })
    }
    
    func testSearchTools_CaseInsensitive() {
        // When
        let lowerResults = sut.searchTools(query: "message")
        let upperResults = sut.searchTools(query: "MESSAGE")
        
        // Then
        XCTAssertEqual(lowerResults.count, upperResults.count)
    }
    
    func testSearchTools_WithShortcut() {
        // When
        let results = sut.searchTools(query: "text")
        
        // Then
        XCTAssertTrue(results.contains { $0.shortcuts.contains("text") })
    }
    
    func testSearchTools_NoResults() {
        // When
        let results = sut.searchTools(query: "xyz123nonexistent")
        
        // Then
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Tool Properties Tests
    
    func testTool_ParametersAreValid() {
        // When
        let tool = sut.getTool("imessage_send")
        
        // Then
        XCTAssertNotNil(tool)
        XCTAssertTrue(tool!.requiresConfirmation)
        XCTAssertTrue(tool!.voiceOptimized)
        
        let recipientParam = tool!.parameters.first { $0.name == "recipient" }
        XCTAssertNotNil(recipientParam)
        XCTAssertTrue(recipientParam!.required)
        XCTAssertNotNil(recipientParam!.voicePrompt)
    }
    
    func testTool_LocalVsRemoteExecution() {
        // Local tools
        let remindersTool = sut.getTool("reminders_add")
        XCTAssertTrue(remindersTool?.localExecution ?? false)
        
        // Remote tools
        let telegramTool = sut.getTool("telegram_send")
        XCTAssertFalse(telegramTool?.localExecution ?? true)
    }
    
    // MARK: - Executor Registration Tests
    
    func testRegisterExecutor_StoresExecutor() {
        // Given
        let mockExecutor = MockToolExecutor()
        
        // When
        sut.registerExecutor(for: "test_tool", executor: mockExecutor)
        
        // Then
        let retrieved = sut.getExecutor(for: "test_tool")
        XCTAssertNotNil(retrieved)
    }
    
    // MARK: - Category Count Tests
    
    func testCategoryCounts_SumToTotal() {
        // When
        let counts = sut.toolCountByCategory()
        let totalFromCategories = counts.values.reduce(0, +)
        
        // Then
        XCTAssertEqual(totalFromCategories, sut.totalToolCount)
    }
    
    func testAllCategoriesHaveTools() {
        // When
        let counts = sut.toolCountByCategory()
        
        // Then
        for category in HermesTool.ToolCategory.allCases {
            XCTAssertGreaterThan(counts[category, default: 0], 0, "Category \(category) should have tools")
        }
    }
}

// MARK: - Mock Executor

class MockToolExecutor: ToolExecutor {
    var shouldSucceed = true
    var lastParameters: [String: Any]?
    
    func execute(parameters: [String: Any]) async throws -> ToolExecutionResult {
        lastParameters = parameters
        
        if shouldSucceed {
            return ToolExecutionResult(
                success: true,
                message: "Mock execution successful",
                detailedMessage: nil,
                data: ["mock": true],
                error: nil,
                followUpActions: nil
            )
        } else {
            throw ToolExecutionError.executionFailed("Mock failure")
        }
    }
    
    func validateParameters(_ parameters: [String: Any]) -> [String: String] {
        return [:]
    }
}
