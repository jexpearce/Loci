import Foundation
import Combine

// MARK: - Realtime Event Types

enum RealtimeEventType: String, Codable {
    case connected = "connected"
    case disconnected = "disconnected"
    case heartbeat = "heartbeat"
    case chartUpdate = "chart_update"
    case newMatch = "new_match"
    case leaderboardChange = "leaderboard_change"
    case trendAlert = "trend_alert"
    case sessionUpdate = "session_update"
    case locationActivity = "location_activity"
    case error = "error"
}

// MARK: - Realtime Manager

class RealtimeManager: NSObject, ObservableObject {
    static let shared = RealtimeManager()
    
    // Connection state
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    
    // Event streams
    let chartUpdates = PassthroughSubject<ChartUpdate, Never>()
    let matchAlerts = PassthroughSubject<MatchAlert, Never>()
    let leaderboardChanges = PassthroughSubject<LeaderboardChange, Never>()
    let trendAlerts = PassthroughSubject<TrendAlert, Never>()
    let locationActivity = PassthroughSubject<LocationActivityUpdate, Never>()
    
    // Configuration
    private let websocketURL = URL(string: "wss://realtime.loci.app/v1/ws")!
    private let reconnectDelay: TimeInterval = 5.0
    private let heartbeatInterval: TimeInterval = 30.0
    private let timeoutInterval: TimeInterval = 60.0
    
    // WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    
    // Timers
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var timeoutTimer: Timer?
    
    // State
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Subscriptions
    private var subscriptions = Set<RealtimeSubscription>()
    private let subscriptionQueue = DispatchQueue(label: "com.loci.realtime.subscriptions")
    
    private override init() {
        super.init()
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        
        self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        shouldReconnect = true
        connectionStatus = .connecting
        
        // Build URL with auth token
        var request = URLRequest(url: websocketURL)
        if let token = APIClient.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        startReceiving()
        startHeartbeat()
        startTimeout()
    }
    
    func disconnect() {
        shouldReconnect = false
        connectionStatus = .disconnecting
        
        cancelTimers()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        isConnected = false
        connectionStatus = .disconnected
        reconnectAttempts = 0
    }
    
    private func reconnect() {
        guard shouldReconnect else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = .failed
            return
        }
        
        reconnectAttempts += 1
        connectionStatus = .reconnecting
        
        // Exponential backoff
        let delay = reconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            self.connect()
        }
    }
    
    // MARK: - Message Handling
    
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving() // Continue receiving
                
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        resetTimeout()
        
        switch message {
        case .string(let text):
            handleTextMessage(text)
            
        case .data(let data):
            handleDataMessage(data)
            
        @unknown default:
            break
        }
    }
    
    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let event = try JSONDecoder().decode(RealtimeEvent.self, from: data)
            processEvent(event)
        } catch {
            print("❌ Failed to decode realtime event: \(error)")
        }
    }
    
    private func handleDataMessage(_ data: Data) {
        // Handle binary messages if needed
        print("📦 Received binary message: \(data.count) bytes")
    }
    
    private func processEvent(_ event: RealtimeEvent) {
        switch event.type {
        case .connected:
            handleConnected(event)
            
        case .heartbeat:
            // Heartbeat acknowledged
            break
            
        case .chartUpdate:
            if let update = try? JSONDecoder().decode(ChartUpdate.self, from: event.data ?? Data()) {
                chartUpdates.send(update)
            }
            
        case .newMatch:
            if let alert = try? JSONDecoder().decode(MatchAlert.self, from: event.data ?? Data()) {
                matchAlerts.send(alert)
                
                // Trigger notification
                NotificationManager.shared.notifyNewMatch(alert.match)
            }
            
        case .leaderboardChange:
            if let change = try? JSONDecoder().decode(LeaderboardChange.self, from: event.data ?? Data()) {
                leaderboardChanges.send(change)
            }
            
        case .trendAlert:
            if let alert = try? JSONDecoder().decode(TrendAlert.self, from: event.data ?? Data()) {
                trendAlerts.send(alert)
            }
            
        case .locationActivity:
            if let update = try? JSONDecoder().decode(LocationActivityUpdate.self, from: event.data ?? Data()) {
                locationActivity.send(update)
            }
            
        case .error:
            if let errorData = event.data,
               let errorInfo = try? JSONDecoder().decode(RealtimeError.self, from: errorData) {
                handleRealtimeError(errorInfo)
            }
            
        default:
            print("📨 Unhandled event type: \(event.type)")
        }
    }
    
    private func handleConnected(_ event: RealtimeEvent) {
        isConnected = true
        connectionStatus = .connected
        reconnectAttempts = 0
        
        // Re-subscribe to all active subscriptions
        resubscribeAll()
    }
    
    private func handleRealtimeError(_ error: RealtimeError) {
        print("❌ Realtime error: \(error.message)")
        lastError = NSError(domain: "RealtimeManager", code: error.code, userInfo: [
            NSLocalizedDescriptionKey: error.message
        ])
    }
    
    private func handleError(_ error: Error) {
        print("❌ WebSocket error: \(error)")
        lastError = error
        
        isConnected = false
        connectionStatus = .disconnected
        
        if shouldReconnect {
            reconnect()
        }
    }
    
    // MARK: - Subscriptions
    
    func subscribe(to subscription: RealtimeSubscription) {
        subscriptionQueue.sync {
            subscriptions.insert(subscription)
        }
        
        if isConnected {
            sendSubscription(subscription)
        }
    }
    
    func unsubscribe(from subscription: RealtimeSubscription) {
        subscriptionQueue.sync {
            subscriptions.remove(subscription)
        }
        
        if isConnected {
            sendUnsubscription(subscription)
        }
    }
    
    private func resubscribeAll() {
        subscriptionQueue.sync {
            subscriptions.forEach { subscription in
                sendSubscription(subscription)
            }
        }
    }
    
    private func sendSubscription(_ subscription: RealtimeSubscription) {
        let message = SubscriptionMessage(
            action: .subscribe,
            subscription: subscription
        )
        
        sendMessage(message)
    }
    
    private func sendUnsubscription(_ subscription: RealtimeSubscription) {
        let message = SubscriptionMessage(
            action: .unsubscribe,
            subscription: subscription
        )
        
        sendMessage(message)
    }
    
    // MARK: - Message Sending
    
    private func sendMessage<T: Encodable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                print("❌ Failed to send message: \(error)")
            }
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { _ in
            self.sendHeartbeat()
        }
    }
    
    private func sendHeartbeat() {
        let heartbeat = HeartbeatMessage(timestamp: Date())
        sendMessage(heartbeat)
    }
    
    // MARK: - Timeout
    
    private func startTimeout() {
        resetTimeout()
    }
    
    private func resetTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { _ in
            self.handleTimeout()
        }
    }
    
    private func handleTimeout() {
        print("⏱️ Connection timeout")
        handleError(NSError(domain: "RealtimeManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Connection timeout"
        ]))
    }
    
    // MARK: - Cleanup
    
    private func cancelTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RealtimeManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket closed: \(closeCode)")
        handleError(NSError(domain: "RealtimeManager", code: Int(closeCode.rawValue), userInfo: nil))
    }
}

// MARK: - Supporting Types

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}

struct RealtimeEvent: Decodable {
    let type: RealtimeEventType
    let timestamp: Date
    let data: Data?
}

struct RealtimeError: Decodable {
    let code: Int
    let message: String
}

// MARK: - Subscription Types

enum RealtimeSubscription: Hashable {
    case building(name: String)
    case location(latitude: Double, longitude: Double, radius: Double)
    case user(id: String)
    case genre(name: String)
    case globalTrends
    
    var identifier: String {
        switch self {
        case .building(let name):
            return "building:\(name)"
        case .location(let lat, let lon, let radius):
            return "location:\(lat),\(lon),\(radius)"
        case .user(let id):
            return "user:\(id)"
        case .genre(let name):
            return "genre:\(name)"
        case .globalTrends:
            return "global:trends"
        }
    }
}

// MARK: - Message Types

struct SubscriptionMessage: Encodable {
    let action: SubscriptionAction
    let subscription: RealtimeSubscription
    
    enum SubscriptionAction: String, Encodable {
        case subscribe
        case unsubscribe
    }
    
    private enum CodingKeys: String, CodingKey {
        case action
        case channel
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(subscription.identifier, forKey: .channel)
    }
}

struct HeartbeatMessage: Encodable {
    let type = "heartbeat"
    let timestamp: Date
}

// MARK: - Update Models

struct ChartUpdate: Decodable {
    let building: String
    let type: ChartType
    let items: [ChartItem]
    let timestamp: Date
    
    enum ChartType: String, Decodable {
        case tracks
        case artists
        case genres
    }
    
    struct ChartItem: Decodable {
        let rank: Int
        let name: String
        let playCount: Int
        let change: Int? // Position change
    }
}

struct MatchAlert: Decodable {
    let match: Match
    let reason: String
    let timestamp: Date
}

struct LeaderboardChange: Decodable {
    let building: String
    let leaderboardType: String
    let changes: [PositionChange]
    let timestamp: Date
    
    struct PositionChange: Decodable {
        let userId: String
        let oldPosition: Int?
        let newPosition: Int
        let metric: Int // Play count, etc.
    }
}

struct TrendAlert: Decodable {
    let type: TrendType
    let item: String
    let metric: TrendMetric
    let building: String?
    let timestamp: Date
    
    struct TrendMetric: Decodable {
        let growth: Double
        let plays: Int
        let listeners: Int
    }
}

struct LocationActivityUpdate: Decodable {
    let building: String
    let activeUsers: Int
    let activeTracks: [String]
    let dominantGenre: String?
    let activityLevel: Double
    let timestamp: Date
}
