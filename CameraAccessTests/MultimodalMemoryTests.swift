/*
 * MultimodalMemory Tests
 * Unit tests for memory storage, retrieval, and search
 */

import XCTest
import CoreLocation
@testable import CameraAccess

@MainActor
final class MultimodalMemoryTests: XCTestCase {
    
    var sut: MultimodalMemoryManager!
    
    override func setUp() {
        super.setUp()
        // Use a separate UserDefaults suite for testing
        UserDefaults.standard.removePersistentDomain(forName: "hermespecs.multimodal_memory")
        sut = MultimodalMemoryManager()
    }
    
    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: "hermespecs.multimodal_memory")
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Memory Creation Tests
    
    func testRemember_CreatesMemory() async {
        // Given
        let description = "Test restaurant with great pasta"
        
        // When
        let memory = await sut.remember(description: description)
        
        // Then
        XCTAssertNotNil(memory)
        XCTAssertEqual(memory?.description, description)
        XCTAssertEqual(memory?.source, .voice)
    }
    
    func testRemember_WithImage_IncludesImageData() async {
        // Given
        let description = "Beautiful sunset"
        let image = createTestImage()
        
        // When
        let memory = await sut.remember(description: description, image: image)
        
        // Then
        XCTAssertNotNil(memory)
        XCTAssertNotNil(memory?.imageData)
    }
    
    func testRemember_WithTags_IncludesTags() async {
        // Given
        let description = "Meeting notes"
        let tags = ["work", "important"]
        
        // When
        let memory = await sut.remember(description: description, tags: tags)
        
        // Then
        XCTAssertEqual(memory?.tags, tags)
    }
    
    func testRemember_AddsToMemoriesList() async {
        // Given
        let initialCount = sut.memories.count
        
        // When
        _ = await sut.remember(description: "Test")
        
        // Then
        XCTAssertEqual(sut.memories.count, initialCount + 1)
    }
    
    func testRemember_AddsToRecentMemories() async {
        // Given
        let initialCount = sut.recentMemories.count
        
        // When
        _ = await sut.remember(description: "Test")
        
        // Then
        XCTAssertEqual(sut.recentMemories.count, min(initialCount + 1, 20))
    }
    
    func testRememberFromFrame_CreatesVisionMemory() {
        // Given
        let frame = createTestFrame()
        
        // When
        let memory = sut.rememberFromFrame(description: "Test scene", frame: frame)
        
        // Then
        XCTAssertEqual(memory.source, .vision)
        XCTAssertEqual(memory.imageData, frame.base64Data)
    }
    
    // MARK: - Search Tests
    
    func testSearch_ByText() {
        // Given
        let memory1 = createMemory(description: "Restaurant with pasta")
        let memory2 = createMemory(description: "Coffee shop")
        sut.memories = [memory1, memory2]
        
        // When
        let results = sut.searchByText("pasta")
        
        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, memory1.id)
    }
    
    func testSearch_ByTag() {
        // Given
        let memory1 = createMemory(description: "Work meeting", tags: ["work"])
        let memory2 = createMemory(description: "Dinner", tags: ["personal"])
        sut.memories = [memory1, memory2]
        
        // When
        let query = MemoryQuery(tags: ["work"])
        let results = sut.search(query: query)
        
        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, memory1.id)
    }
    
    func testSearch_ByDateRange() {
        // Given
        let yesterday = Date().addingTimeInterval(-86400)
        let today = Date()
        let oldMemory = createMemory(description: "Old", timestamp: yesterday)
        let newMemory = createMemory(description: "New", timestamp: today)
        sut.memories = [oldMemory, newMemory]
        
        // When
        let query = MemoryQuery(dateRange: today...today.addingTimeInterval(1))
        let results = sut.search(query: query)
        
        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, newMemory.id)
    }
    
    func testSearch_BySource() {
        // Given
        let visionMemory = createMemory(description: "Vision", source: .vision)
        let voiceMemory = createMemory(description: "Voice", source: .voice)
        sut.memories = [visionMemory, voiceMemory]
        
        // When
        let query = MemoryQuery(source: .vision)
        let results = sut.search(query: query)
        
        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, visionMemory.id)
    }
    
    func testSearch_LimitsResults() {
        // Given
        for i in 0..<20 {
            sut.memories.append(createMemory(description: "Memory \(i)"))
        }
        
        // When
        let query = MemoryQuery(limit: 5)
        let results = sut.search(query: query)
        
        // Then
        XCTAssertEqual(results.count, 5)
    }
    
    // MARK: - Natural Language Query Tests
    
    func testProcessNaturalLanguageQuery_Today() {
        // Given
        let today = Date()
        let todayMemory = createMemory(description: "Today event", timestamp: today)
        let oldMemory = createMemory(description: "Old event", timestamp: today.addingTimeInterval(-86400))
        sut.memories = [todayMemory, oldMemory]
        
        // When
        let results = sut.processNaturalLanguageQuery("What did I do today?")
        
        // Then
        XCTAssertTrue(results.contains { $0.id == todayMemory.id })
    }
    
    func testProcessNaturalLanguageQuery_Yesterday() {
        // Given
        let yesterday = Date().addingTimeInterval(-86400)
        let yesterdayMemory = createMemory(description: "Yesterday event", timestamp: yesterday)
        let todayMemory = createMemory(description: "Today event", timestamp: Date())
        sut.memories = [yesterdayMemory, todayMemory]
        
        // When
        let results = sut.processNaturalLanguageQuery("What did I do yesterday?")
        
        // Then
        XCTAssertTrue(results.contains { $0.id == yesterdayMemory.id })
    }
    
    // MARK: - Memory Management Tests
    
    func testDeleteMemory_RemovesFromLists() {
        // Given
        let memory = createMemory(description: "To delete")
        sut.memories = [memory]
        sut.recentMemories = [memory]
        
        // When
        sut.deleteMemory(id: memory.id)
        
        // Then
        XCTAssertFalse(sut.memories.contains { $0.id == memory.id })
        XCTAssertFalse(sut.recentMemories.contains { $0.id == memory.id })
    }
    
    func testAddTag_AddsToMemory() {
        // Given
        let memory = createMemory(description: "Test", tags: ["initial"])
        sut.memories = [memory]
        
        // When
        sut.addTag(to: memory.id, tag: "new")
        
        // Then
        let updated = sut.memories.first { $0.id == memory.id }
        XCTAssertTrue(updated?.tags.contains("new") ?? false)
    }
    
    func testCleanupOldMemories_RemovesOldEntries() {
        // Given
        let oldDate = Date().addingTimeInterval(-86400 * 100) // 100 days ago
        let recentDate = Date()
        let oldMemory = createMemory(description: "Old", timestamp: oldDate)
        let recentMemory = createMemory(description: "Recent", timestamp: recentDate)
        sut.memories = [oldMemory, recentMemory]
        sut.configuration.retentionDays = 90
        
        // When
        sut.cleanupOldMemories()
        
        // Then
        XCTAssertFalse(sut.memories.contains { $0.id == oldMemory.id })
        XCTAssertTrue(sut.memories.contains { $0.id == recentMemory.id })
    }
    
    func testCleanupOldMemories_RespectsMaxCount() {
        // Given
        sut.configuration.maxMemories = 5
        for i in 0..<20 {
            sut.memories.append(createMemory(description: "Memory \(i)"))
        }
        
        // When
        sut.cleanupOldMemories()
        
        // Then
        XCTAssertLessThanOrEqual(sut.memories.count, 5)
    }
    
    // MARK: - Export Tests
    
    func testExportMemories_ReturnsValidData() {
        // Given
        sut.memories = [createMemory(description: "Test")]
        
        // When
        let data = sut.exportMemories()
        
        // Then
        XCTAssertNotNil(data)
        
        // Verify it's valid JSON
        if let data = data {
            let json = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(json)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 100, height: 100))
        defer { UIGraphicsEndImageContext() }
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    private func createTestFrame() -> ProcessedFrame {
        return ProcessedFrame(
            id: UUID(),
            base64Data: "dGVzdA==",
            width: 640,
            height: 480,
            mimeType: "image/jpeg",
            compressionQuality: 0.75,
            timestamp: Date(),
            originalSize: 100000,
            processedSize: 50000,
            processingTime: 0.1
        )
    }
    
    private func createMemory(
        description: String,
        timestamp: Date = Date(),
        tags: [String] = [],
        source: MemoryEntry.MemorySource = .voice
    ) -> MemoryEntry {
        return MemoryEntry(
            id: UUID(),
            timestamp: timestamp,
            description: description,
            textContent: nil,
            imageData: nil,
            audioTranscript: nil,
            location: nil,
            tags: tags,
            source: source,
            context: MemoryEntry.MemoryContext(
                precedingCommand: nil,
                followingCommand: nil,
                sceneDescription: nil,
                objectsDetected: nil
            )
        )
    }
}
