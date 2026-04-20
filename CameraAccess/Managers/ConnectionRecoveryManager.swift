/*
 * Connection Recovery Manager
 * Handles automatic reconnection, error recovery, and connection quality monitoring
 */

import Foundation
import Network
import Combine

@MainActor
class ConnectionRecoveryManager: ObservableObject {
    static let shared = ConnectionRecoveryManager()
    
    // MARK: - Published State
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isReconnecting = false
    @Published var lastError: ConnectionError?
    @Published var retryCount = 0
    @Published var estimatedRecoveryTime: TimeInterval?
    
    enum ConnectionState: String {
        case connected = "Connected"
        case connecting = "Connecting"
        case disconnected = "Disconnected"
        case reconnecting = "Reconnecting"
        case failed = "Failed"
    }
    
    enum ConnectionError: Error, LocalizedError {
        case networkUnavailable
        case serverUnreachable
        case authenticationFailed
        case timeout
        case protocolError
        case unexpectedDisconnect
        case tooManyRetries
        
        var errorDescription: String? {
            switch self {
            case .networkUnavailable:
                return "No network connection"
            case .serverUnreachable:
                return "Cannot reach Hermes server"
            case .authenticationFailed:
                return "Authentication failed"
            case .timeout:
                return "Connection timed out"
            case .protocolError:
                return "Protocol error"
            case .unexpectedDisconnect:
                return "Unexpectedly disconnected"
            case .tooManyRetries:
                return "Too many reconnection attempts"
            }
        }
        
        var isRecoverable: Bool {
            switch self {
            case .networkUnavailable, .serverUnreachable, .timeout, .unexpectedDisconnect:
                return true
            case .authenticationFailed, .protocolError, .tooManyRetries:
                return false
            }
        }
    }
    
    // MARK: - Configuration
    
    struct Configuration {
        var maxRetries: Int = 5
        var initialRetryDelay: TimeInterval = 1.0
        var maxRetryDelay: TimeInterval = 60.0
        var retryBackoffMultiplier: Double = 2.0
        var heartbeatInterval: TimeInterval = 30.0
        var connectionTimeout: TimeInterval = 10.0
        var enableAutomaticReconnect: Bool = true
        var enableNetworkMonitoring: Bool = true
    }
    
    var configuration = Configuration()
    
    // MARK: - Private Properties
    
    private var monitor: NWPathMonitor?
    private var isNetworkAvailable = true
    private var retryTimer: Timer?
    private var heartbeatTimer: Timer?
    private var connectionTimeoutTimer: Timer?
    
    private var currentRetryDelay: TimeInterval = 1.0
    private var onReconnect: (() -> Void)?
    private var onDisconnect: ((ConnectionError) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    
    var onStateChanged: ((ConnectionState) -> Void)?
    var onRecoveryAttempt: ((Int, TimeInterval) -> Void)?
    var onRecovered: (() -> Void)?
    var onPermanentlyFailed: ((ConnectionError) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        if configuration.enableNetworkMonitoring {
            startNetworkMonitoring()
        }
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        monitor = NWPathMonitor()
        
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasAvailable = self?.isNetworkAvailable ?? true
                self?.isNetworkAvailable = path.status == .satisfied
                
                if !wasAvailable && path.status == .satisfied {
                    // Network became available
                    print("Network became available")
                    self?.attemptRecovery()
                } else if wasAvailable && path.status != .satisfied {
                    // Network lost
                    print("Network connection lost")
                    self?.handleDisconnect(.networkUnavailable)
                }
            }
        }
        
        monitor?.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    // MARK: - Connection Management
    
    func connect(
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (ConnectionError) -> Void
    ) {
        guard connectionState != .connected else {
            onSuccess()
            return
        }
        
        updateState(.connecting)
        
        // Start connection timeout
        startConnectionTimeout(onFailure)
        
        // Attempt connection (this would integrate with HermesService)
        attemptConnection { [weak self] result in
            self?.cancelConnectionTimeout()
            
            switch result {
            case .success:
                self?.handleSuccessfulConnection()
                onSuccess()
            case .failure(let error):
                self?.handleConnectionFailure(error)
                onFailure(error)
            }
        }
    }
    
    func disconnect() {
        stopRetryTimer()
        stopHeartbeat()
        updateState(.disconnected)
        retryCount = 0
    }
    
    func handleDisconnect(_ error: ConnectionError) {
        lastError = error
        updateState(.disconnected)
        
        onDisconnect?(error)
        
        if error.isRecoverable && configuration.enableAutomaticReconnect {
            scheduleRetry()
        } else {
            updateState(.failed)
            onPermanentlyFailed?(error)
        }
    }
    
    // MARK: - Recovery Logic
    
    private func handleSuccessfulConnection() {
        retryCount = 0
        currentRetryDelay = configuration.initialRetryDelay
        updateState(.connected)
        startHeartbeat()
        onRecovered?()
    }
    
    private func handleConnectionFailure(_ error: ConnectionError) {
        lastError = error
        
        if error.isRecoverable && retryCount < configuration.maxRetries {
            scheduleRetry()
        } else if retryCount >= configuration.maxRetries {
            updateState(.failed)
            onPermanentlyFailed?(.tooManyRetries)
        } else {
            updateState(.failed)
            onPermanentlyFailed?(error)
        }
    }
    
    private func scheduleRetry() {
        guard configuration.enableAutomaticReconnect else { return }
        
        retryCount += 1
        updateState(.reconnecting)
        
        // Calculate next retry delay with exponential backoff
        let delay = min(currentRetryDelay, configuration.maxRetryDelay)
        currentRetryDelay *= configuration.retryBackoffMultiplier
        
        estimatedRecoveryTime = Date().timeIntervalSince1970 + delay
        onRecoveryAttempt?(retryCount, delay)
        
        print("Scheduling retry #\(retryCount) in \(delay) seconds")
        
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptRecovery()
        }
    }
    
    private func attemptRecovery() {
        guard connectionState != .connected else { return }
        
        isReconnecting = true
        updateState(.reconnecting)
        
        attemptConnection { [weak self] result in
            self?.isReconnecting = false
            
            switch result {
            case .success:
                self?.handleSuccessfulConnection()
            case .failure(let error):
                self?.handleConnectionFailure(error)
            }
        }
    }
    
    private func attemptConnection(completion: @escaping (Result<Void, ConnectionError>) -> Void) {
        // Check network availability
        guard isNetworkAvailable else {
            completion(.failure(.networkUnavailable))
            return
        }

        // Check if AI service is configured
        Task { @MainActor in
            let aiService = HermesAIService.shared
            if aiService.hasAPIKeyConfigured {
                // Verify connectivity with a test request
                let reachable = await aiService.testConnection()
                if reachable {
                    completion(.success(()))
                } else {
                    completion(.failure(.serverUnreachable))
                }
            } else {
                completion(.failure(.authenticationFailed))
            }
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: configuration.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        // Send ping to server
        // If no pong received within timeout, trigger reconnection
        
        // This would integrate with HermesService
        // For now, just log
        print("Sending heartbeat...")
    }
    
    // MARK: - Timeout Management
    
    private func startConnectionTimeout(_ onTimeout: @escaping (ConnectionError) -> Void) {
        cancelConnectionTimeout()
        
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: configuration.connectionTimeout, repeats: false) { _ in
            onTimeout(.timeout)
        }
    }
    
    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }
    
    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: ConnectionState) {
        guard connectionState != newState else { return }
        
        connectionState = newState
        onStateChanged?(newState)
        
        // Post notification for other components
        NotificationCenter.default.post(
            name: .init("HermespecsConnectionStateChanged"),
            object: nil,
            userInfo: ["state": newState.rawValue]
        )
    }
    
    // MARK: - Public Helpers
    
    func resetRetryCount() {
        retryCount = 0
        currentRetryDelay = configuration.initialRetryDelay
    }
    
    func getConnectionStatus() -> ConnectionStatus {
        return ConnectionStatus(
            state: connectionState,
            isReconnecting: isReconnecting,
            retryCount: retryCount,
            maxRetries: configuration.maxRetries,
            lastError: lastError,
            estimatedRecoveryTime: estimatedRecoveryTime,
            isNetworkAvailable: isNetworkAvailable
        )
    }
    
    struct ConnectionStatus {
        let state: ConnectionState
        let isReconnecting: Bool
        let retryCount: Int
        let maxRetries: Int
        let lastError: ConnectionError?
        let estimatedRecoveryTime: TimeInterval?
        let isNetworkAvailable: Bool
        
        var shouldShowRetryUI: Bool {
            return isReconnecting && retryCount > 0
        }
        
        var recoveryProgress: Double {
            guard maxRetries > 0 else { return 0 }
            return Double(retryCount) / Double(maxRetries)
        }
    }
}

// MARK: - Connection Quality Monitor

class ConnectionQualityMonitor: ObservableObject {
    @Published var latency: Double = 0
    @Published var packetLoss: Double = 0
    @Published var jitter: Double = 0
    @Published var qualityScore: Int = 100
    
    private var latencyMeasurements: [Double] = []
    private let maxMeasurements = 50
    
    func recordLatency(_ ms: Double) {
        latencyMeasurements.append(ms)
        
        if latencyMeasurements.count > maxMeasurements {
            latencyMeasurements.removeFirst()
        }
        
        updateMetrics()
    }
    
    func recordPacketLoss(_ percentage: Double) {
        packetLoss = percentage
        updateQualityScore()
    }
    
    private func updateMetrics() {
        guard !latencyMeasurements.isEmpty else { return }
        
        let sorted = latencyMeasurements.sorted()
        latency = sorted.reduce(0, +) / Double(sorted.count)
        
        // Calculate jitter (standard deviation)
        let mean = latency
        let variance = sorted.map { pow($0 - mean, 2) }.reduce(0, +) / Double(sorted.count)
        jitter = sqrt(variance)
        
        updateQualityScore()
    }
    
    private func updateQualityScore() {
        // Calculate quality score based on latency, jitter, and packet loss
        var score = 100
        
        // Deduct for high latency
        if latency > 500 {
            score -= 30
        } else if latency > 200 {
            score -= 15
        } else if latency > 100 {
            score -= 5
        }
        
        // Deduct for packet loss
        score -= Int(packetLoss * 2)
        
        // Deduct for high jitter
        if jitter > 50 {
            score -= 10
        }
        
        qualityScore = max(0, min(100, score))
    }
}
