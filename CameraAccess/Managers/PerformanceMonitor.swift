/*
 * Performance Monitor
 * Tracks battery, thermal state, and connection quality
 * Manages adaptive streaming based on device conditions
 */

import Foundation
import UIKit
import Combine
import MWDATCamera
import MWDATCore

@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    // MARK: - Published State
    
    @Published var batteryLevel: Int = 100
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var connectionQuality: ConnectionQuality = .good
    @Published var isThrottling = false
    @Published var recommendedFrameRate: Double = 1.0
    @Published var recommendedQuality: StreamQuality = .medium
    
    // MARK: - Performance Metrics
    
    @Published var averageLatency: Double = 0
    @Published var droppedFrames: Int = 0
    @Published var totalFrames: Int = 0
    @Published var memoryUsage: UInt64 = 0
    @Published var cpuUsage: Double = 0
    
    // MARK: - Configuration
    
    struct Configuration {
        var lowBatteryThreshold: Int = 20
        var criticalBatteryThreshold: Int = 10
        var thermalThrottleThreshold: ProcessInfo.ThermalState = .serious
        var targetLatencyMs: Double = 500
        var maxLatencyMs: Double = 2000
        var enableAdaptiveBitrate: Bool = true
        var enableBackgroundStreaming: Bool = true
        var powerSaveMode: Bool = false
    }
    
    var configuration = Configuration()
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?
    private var latencyMeasurements: [Double] = []
    private let maxLatencyMeasurements = 10
    
    private var streamSession: StreamSession?
    
    // MARK: - Connection Quality
    
    enum ConnectionQuality: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        
        var color: String {
            switch self {
            case .excellent: return "#00C853"
            case .good: return "#64DD17"
            case .fair: return "#FFD600"
            case .poor: return "#FF3D00"
            }
        }
    }
    
    enum StreamQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case auto = "Auto"
        
        var resolution: CGSize {
            switch self {
            case .low: return CGSize(width: 320, height: 240)
            case .medium: return CGSize(width: 640, height: 480)
            case .high: return CGSize(width: 1280, height: 720)
            case .auto: return CGSize(width: 640, height: 480) // Dynamic
            }
        }
        
        var compressionQuality: CGFloat {
            switch self {
            case .low: return 0.5
            case .medium: return 0.75
            case .high: return 0.9
            case .auto: return 0.75 // Dynamic
            }
        }
        
        var frameRate: Double {
            switch self {
            case .low: return 0.5 // 1 frame per 2 seconds
            case .medium: return 1.0 // 1 fps
            case .high: return 2.0 // 2 fps
            case .auto: return 1.0 // Dynamic
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupBatteryMonitoring()
        setupThermalMonitoring()
        startMonitoring()
    }
    
    // MARK: - Setup
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Update initial state
        batteryLevel = Int(UIDevice.current.batteryLevel * 100)
        batteryState = UIDevice.current.batteryState
        
        // Listen for battery changes
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryState()
            }
            .store(in: &cancellables)
    }
    
    private func setupThermalMonitoring() {
        // Update initial state
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Listen for thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
            .store(in: &cancellables)
    }
    
    private func startMonitoring() {
        // Update every 5 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
                self?.applyOptimizations()
            }
        }
    }
    
    // MARK: - State Updates
    
    private func updateBatteryState() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Int(level * 100) : 100
        batteryState = UIDevice.current.batteryState
        
        // Apply power save if battery is low
        if batteryLevel <= configuration.lowBatteryThreshold {
            enablePowerSaveMode()
        }
    }
    
    private func updateThermalState() {
        let newState = ProcessInfo.processInfo.thermalState
        thermalState = newState
        
        // Apply throttling if needed
        if newState == .critical || newState == .serious {
            isThrottling = true
            applyThermalThrottling()
        } else if newState == .fair && isThrottling {
            // Gradually restore performance
            graduallyRestorePerformance()
        } else {
            isThrottling = false
        }
    }
    
    private func updateMetrics() {
        // Update memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            memoryUsage = info.resident_size
        }
        
        // Calculate average latency
        if !latencyMeasurements.isEmpty {
            averageLatency = latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)
        }
    }
    
    // MARK: - Optimization Logic
    
    private func applyOptimizations() {
        // Determine optimal settings based on current conditions
        var newFrameRate: Double = 1.0
        var newQuality: StreamQuality = .medium
        
        // Battery-based optimization
        if batteryLevel <= configuration.criticalBatteryThreshold {
            newFrameRate = 0.2 // 1 frame per 5 seconds
            newQuality = .low
        } else if batteryLevel <= configuration.lowBatteryThreshold {
            newFrameRate = 0.5
            newQuality = .low
        } else if batteryState == .charging {
            newFrameRate = 2.0
            newQuality = .high
        }
        
        // Thermal-based optimization
        switch thermalState {
        case .critical:
            newFrameRate = min(newFrameRate, 0.1)
            newQuality = .low
        case .serious:
            newFrameRate = min(newFrameRate, 0.5)
            newQuality = .low
        case .fair:
            newFrameRate = min(newFrameRate, 1.0)
            newQuality = .medium
        case .nominal:
            break // Use battery-based settings
        @unknown default:
            break
        }
        
        // Connection quality optimization
        switch connectionQuality {
        case .poor:
            newFrameRate = min(newFrameRate, 0.5)
            newQuality = .low
        case .fair:
            newFrameRate = min(newFrameRate, 1.0)
            newQuality = .medium
        case .good, .excellent:
            break // Use other settings
        }
        
        // Latency-based optimization
        if averageLatency > configuration.maxLatencyMs {
            newFrameRate = min(newFrameRate, 0.5)
            newQuality = .low
        } else if averageLatency > configuration.targetLatencyMs {
            newFrameRate = min(newFrameRate, 1.0)
            newQuality = .medium
        }
        
        // Apply settings
        recommendedFrameRate = newFrameRate
        recommendedQuality = newQuality
        
        // Notify observers
        objectWillChange.send()
    }
    
    private func applyThermalThrottling() {
        // Immediate throttling
        recommendedFrameRate = 0.5
        recommendedQuality = .low
        
        // Reduce stream quality if session exists
        if let session = streamSession {
            // Request quality reduction from session
            Task {
                try? await reduceStreamQuality(for: session)
            }
        }
    }
    
    private func graduallyRestorePerformance() {
        // Gradually increase frame rate
        if recommendedFrameRate < 1.0 {
            recommendedFrameRate += 0.1
        }
        
        // Restore quality if conditions improve
        if thermalState == .fair && batteryLevel > 20 {
            recommendedQuality = .medium
        }
    }
    
    private func enablePowerSaveMode() {
        configuration.powerSaveMode = true
        recommendedFrameRate = 0.5
        recommendedQuality = .low
        
        // Disable non-essential features
        // In production, this would disable things like:
        // - Background vision processing
        // - Detailed analytics
        // - Non-critical notifications
    }
    
    // MARK: - Public Methods
    
    func recordLatency(_ latencyMs: Double) {
        latencyMeasurements.append(latencyMs)
        
        // Keep only recent measurements
        if latencyMeasurements.count > maxLatencyMeasurements {
            latencyMeasurements.removeFirst()
        }
        
        // Update connection quality
        updateConnectionQuality(latencyMs)
    }
    
    func recordFrameProcessed(success: Bool) {
        totalFrames += 1
        if !success {
            droppedFrames += 1
        }
        
        // Calculate drop rate
        let dropRate = Double(droppedFrames) / Double(totalFrames)
        
        // Adjust quality if drop rate is high
        if dropRate > 0.1 { // More than 10% dropped
            recommendedQuality = .low
        }
    }
    
    func setStreamSession(_ session: StreamSession?) {
        self.streamSession = session
    }
    
    func getPerformanceReport() -> PerformanceReport {
        let dropRate = totalFrames > 0 ? Double(droppedFrames) / Double(totalFrames) : 0
        
        return PerformanceReport(
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            thermalState: thermalState,
            connectionQuality: connectionQuality,
            averageLatency: averageLatency,
            frameDropRate: dropRate,
            memoryUsageMB: Double(memoryUsage) / 1024 / 1024,
            recommendedFrameRate: recommendedFrameRate,
            recommendedQuality: recommendedQuality,
            isThrottling: isThrottling,
            powerSaveMode: configuration.powerSaveMode
        )
    }
    
    // MARK: - Private Helpers
    
    private func updateConnectionQuality(_ latencyMs: Double) {
        if latencyMs < 100 {
            connectionQuality = .excellent
        } else if latencyMs < 300 {
            connectionQuality = .good
        } else if latencyMs < 1000 {
            connectionQuality = .fair
        } else {
            connectionQuality = .poor
        }
    }
    
    private func reduceStreamQuality(for session: StreamSession) async throws {
        // This would interact with MetaWearablesSDK to reduce quality
        // For now, this is a placeholder
    }
    
    // MARK: - Cleanup
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}

// MARK: - Performance Report

struct PerformanceReport {
    let batteryLevel: Int
    let batteryState: UIDevice.BatteryState
    let thermalState: ProcessInfo.ThermalState
    let connectionQuality: PerformanceMonitor.ConnectionQuality
    let averageLatency: Double
    let frameDropRate: Double
    let memoryUsageMB: Double
    let recommendedFrameRate: Double
    let recommendedQuality: PerformanceMonitor.StreamQuality
    let isThrottling: Bool
    let powerSaveMode: Bool
    
    var isHealthy: Bool {
        batteryLevel > 10 &&
        thermalState != .critical &&
        frameDropRate < 0.1 &&
        averageLatency < 1000
    }
    
    var healthStatus: String {
        if !isHealthy {
            if batteryLevel <= 10 {
                return "Critical battery"
            } else if thermalState == .critical {
                return "Overheating"
            } else if frameDropRate > 0.1 {
                return "High frame drops"
            } else if averageLatency > 1000 {
                return "High latency"
            }
        }
        return "Healthy"
    }
}
