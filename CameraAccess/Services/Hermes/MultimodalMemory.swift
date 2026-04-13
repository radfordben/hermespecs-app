/*
 * Multi-Modal Memory
 * Stores and retrieves memories with vision, audio, and text context
 * Enables "Remember this" and "What did I see yesterday?" functionality
 */

import Foundation
import UIKit
import CoreLocation

// MARK: - Memory Entry

struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let description: String
    let textContent: String?
    let imageData: String?  // Base64 encoded thumbnail
    let audioTranscript: String?
    let location: LocationInfo?
    let tags: [String]
    let source: MemorySource
    let context: MemoryContext
    
    enum MemorySource: String, Codable {
        case vision  // Remembered via camera
        case voice   // Remembered via voice command
        case text    // Remembered via text input
        case auto    // Auto-remembered (AI decided)
    }
    
    struct LocationInfo: Codable {
        let latitude: Double
        let longitude: Double
        let locationName: String?
        let accuracy: Double
    }
    
    struct MemoryContext: Codable {
        let precedingCommand: String?
        let followingCommand: String?
        let sceneDescription: String?
        let objectsDetected: [String]?
    }
}

// MARK: - Memory Query

struct MemoryQuery {
    let text: String?
    let dateRange: ClosedRange<Date>?
    let location: CLLocation?
    let radius: Double?  // Meters
    let tags: [String]?
    let source: MemoryEntry.MemorySource?
    let limit: Int
    
    init(
        text: String? = nil,
        dateRange: ClosedRange<Date>? = nil,
        location: CLLocation? = nil,
        radius: Double? = nil,
        tags: [String]? = nil,
        source: MemoryEntry.MemorySource? = nil,
        limit: Int = 10
    ) {
        self.text = text
        self.dateRange = dateRange
        self.location = location
        self.radius = radius
        self.tags = tags
        self.source = source
        self.limit = limit
    }
}

// MARK: - Multi-Modal Memory Manager

@MainActor
class MultimodalMemoryManager: ObservableObject {
    static let shared = MultimodalMemoryManager()
    
    // MARK: - Published State
    
    @Published var memories: [MemoryEntry] = []
    @Published var recentMemories: [MemoryEntry] = []
    @Published var isLoading = false
    @Published var searchResults: [MemoryEntry] = []
    
    // MARK: - Configuration
    
    struct Configuration {
        var maxMemories: Int = 1000
        var retentionDays: Int = 90
        var autoCleanup: Bool = true
        var enableLocationTagging: Bool = true
        var thumbnailSize: CGSize = CGSize(width: 200, height: 150)
        var compressionQuality: CGFloat = 0.6
    }
    
    var configuration = Configuration()
    
    // MARK: - Private Properties
    
    private let storageKey = "hermespecs.multimodal_memory"
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    private let frameProcessor = VisionFrameProcessor(configuration: VisionFrameProcessor.Configuration(
        targetSize: CGSize(width: 200, height: 150),
        compressionQuality: 0.6,
        maxFileSizeKB: 50
    ))
    
    // MARK: - Initialization
    
    private init() {
        loadMemories()
        setupLocationManager()
        scheduleCleanup()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        if configuration.enableLocationTagging {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    private func scheduleCleanup() {
        // Clean up old memories daily
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldMemories()
            }
        }
    }
    
    // MARK: - Memory Creation
    
    func remember(
        description: String,
        image: UIImage? = nil,
        textContent: String? = nil,
        audioTranscript: String? = nil,
        tags: [String] = [],
        source: MemoryEntry.MemorySource = .voice,
        context: MemoryEntry.MemoryContext? = nil
    ) async -> MemoryEntry? {
        
        let id = UUID()
        let timestamp = Date()
        
        // Process image if provided
        var imageData: String?
        if let image = image {
            imageData = await processImage(image)
        }
        
        // Get location if available
        let location = getCurrentLocationInfo()
        
        let memory = MemoryEntry(
            id: id,
            timestamp: timestamp,
            description: description,
            textContent: textContent,
            imageData: imageData,
            audioTranscript: audioTranscript,
            location: location,
            tags: tags,
            source: source,
            context: context ?? MemoryEntry.MemoryContext(
                precedingCommand: nil,
                followingCommand: nil,
                sceneDescription: nil,
                objectsDetected: nil
            )
        )
        
        // Add to storage
        memories.append(memory)
        recentMemories.insert(memory, at: 0)
        
        // Limit recent memories
        if recentMemories.count > 20 {
            recentMemories = Array(recentMemories.prefix(20))
        }
        
        // Save
        saveMemories()
        
        return memory
    }
    
    func rememberFromFrame(
        description: String,
        frame: ProcessedFrame,
        textContent: String? = nil,
        tags: [String] = []
    ) -> MemoryEntry {
        
        let memory = MemoryEntry(
            id: UUID(),
            timestamp: Date(),
            description: description,
            textContent: textContent,
            imageData: frame.base64Data,
            audioTranscript: nil,
            location: getCurrentLocationInfo(),
            tags: tags,
            source: .vision,
            context: MemoryEntry.MemoryContext(
                precedingCommand: nil,
                followingCommand: nil,
                sceneDescription: nil,
                objectsDetected: nil
            )
        )
        
        memories.append(memory)
        recentMemories.insert(memory, at: 0)
        
        if recentMemories.count > 20 {
            recentMemories = Array(recentMemories.prefix(20))
        }
        
        saveMemories()
        
        return memory
    }
    
    // MARK: - Memory Retrieval
    
    func search(query: MemoryQuery) -> [MemoryEntry] {
        var results = memories
        
        // Filter by date range
        if let dateRange = query.dateRange {
            results = results.filter { dateRange.contains($0.timestamp) }
        }
        
        // Filter by location
        if let location = query.location, let radius = query.radius {
            results = results.filter { entry in
                guard let entryLocation = entry.location else { return false }
                let entryCLLocation = CLLocation(
                    latitude: entryLocation.latitude,
                    longitude: entryLocation.longitude
                )
                return location.distance(from: entryCLLocation) <= radius
            }
        }
        
        // Filter by tags
        if let tags = query.tags, !tags.isEmpty {
            results = results.filter { entry in
                !Set(entry.tags).isDisjoint(with: tags)
            }
        }
        
        // Filter by source
        if let source = query.source {
            results = results.filter { $0.source == source }
        }
        
        // Text search
        if let text = query.text, !text.isEmpty {
            let lowercasedQuery = text.lowercased()
            results = results.filter { entry in
                entry.description.lowercased().contains(lowercasedQuery) ||
                entry.textContent?.lowercased().contains(lowercasedQuery) ?? false ||
                entry.audioTranscript?.lowercased().contains(lowercasedQuery) ?? false ||
                entry.tags.contains { $0.lowercased().contains(lowercasedQuery) }
            }
        }
        
        // Sort by relevance (newest first for now)
        results.sort { $0.timestamp > $1.timestamp }
        
        // Limit results
        return Array(results.prefix(query.limit))
    }
    
    func searchByText(_ text: String, limit: Int = 5) -> [MemoryEntry] {
        let query = MemoryQuery(text: text, limit: limit)
        return search(query: query)
    }
    
    func getMemoriesForToday() -> [MemoryEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let query = MemoryQuery(
            dateRange: startOfDay...endOfDay,
            limit: 50
        )
        return search(query: query)
    }
    
    func getMemoriesForYesterday() -> [MemoryEntry] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday)!
        
        let query = MemoryQuery(
            dateRange: startOfYesterday...endOfYesterday,
            limit: 50
        )
        return search(query: query)
    }
    
    func getMemoriesNearCurrentLocation(radius: Double = 100) -> [MemoryEntry] {
        guard let location = currentLocation else { return [] }
        
        let query = MemoryQuery(
            location: location,
            radius: radius,
            limit: 20
        )
        return search(query: query)
    }
    
    // MARK: - Memory Management
    
    func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        recentMemories.removeAll { $0.id == id }
        saveMemories()
    }
    
    func addTag(to memoryId: UUID, tag: String) {
        if let index = memories.firstIndex(where: { $0.id == memoryId }) {
            var memory = memories[index]
            if !memory.tags.contains(tag) {
                var newTags = memory.tags
                newTags.append(tag)
                memory = MemoryEntry(
                    id: memory.id,
                    timestamp: memory.timestamp,
                    description: memory.description,
                    textContent: memory.textContent,
                    imageData: memory.imageData,
                    audioTranscript: memory.audioTranscript,
                    location: memory.location,
                    tags: newTags,
                    source: memory.source,
                    context: memory.context
                )
                memories[index] = memory
                saveMemories()
            }
        }
    }
    
    func cleanupOldMemories() {
        guard configuration.autoCleanup else { return }
        
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -configuration.retentionDays,
            to: Date()
        )!
        
        let beforeCount = memories.count
        memories.removeAll { $0.timestamp < cutoffDate }
        
        // Also limit total memories
        if memories.count > configuration.maxMemories {
            memories.sort { $0.timestamp > $1.timestamp }
            memories = Array(memories.prefix(configuration.maxMemories))
        }
        
        if memories.count != beforeCount {
            saveMemories()
            print("Cleaned up \(beforeCount - memories.count) old memories")
        }
    }
    
    // MARK: - Natural Language Queries
    
    func processNaturalLanguageQuery(_ query: String) -> [MemoryEntry] {
        let lowercased = query.lowercased()
        
        // Time-based queries
        if lowercased.contains("today") {
            return getMemoriesForToday()
        } else if lowercased.contains("yesterday") {
            return getMemoriesForYesterday()
        } else if lowercased.contains("last week") {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return search(query: MemoryQuery(dateRange: weekAgo...Date(), limit: 20))
        }
        
        // Location-based queries
        if lowercased.contains("near me") || lowercased.contains("nearby") || lowercased.contains("here") {
            return getMemoriesNearCurrentLocation()
        }
        
        // Source-based queries
        if lowercased.contains("i saw") || lowercased.contains("i remembered") {
            return search(query: MemoryQuery(source: .vision, limit: 10))
        }
        
        // General text search
        return searchByText(query, limit: 10)
    }
    
    // MARK: - Export
    
    func exportMemories() -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(memories)
        } catch {
            print("Failed to export memories: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func processImage(_ image: UIImage) async -> String? {
        return await withCheckedContinuation { continuation in
            frameProcessor.processUIImage(image) { result in
                switch result {
                case .success(let frame):
                    continuation.resume(returning: frame.base64Data)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func getCurrentLocationInfo() -> MemoryEntry.LocationInfo? {
        guard configuration.enableLocationTagging,
              let location = currentLocation else {
            return nil
        }
        
        return MemoryEntry.LocationInfo(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            locationName: nil, // Could use reverse geocoding
            accuracy: location.horizontalAccuracy
        )
    }
    
    private func loadMemories() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memories = try decoder.decode([MemoryEntry].self, from: data)
            recentMemories = Array(memories.suffix(20).reversed())
        } catch {
            print("Failed to load memories: \(error)")
        }
    }
    
    private func saveMemories() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memories)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save memories: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension MultimodalMemoryManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}
