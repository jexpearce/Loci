import Foundation
import Combine
import BackgroundTasks
import UIKit

class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var isSessionActive = false
    @Published var sessionStartTime: Date?
    @Published var sessionEndTime: Date?
    @Published var currentSessionDuration: SessionDuration = .twelveHours
    
    private let locationManager = LocationManager.shared
    private let spotifyManager = SpotifyManager.shared
    private let dataStore = DataStore.shared
    
    private var locationUpdateTimer: Timer?
    private var sessionEndTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Background task identifiers
    private let backgroundTaskIdentifier = "com.loci.sessionUpdate"
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private init() {
        setupBackgroundTasks()
        setupNotifications()
    }
    
    // MARK: - Session Control
    
    func startSession(duration: SessionDuration) {
        print("🎵 Starting session for \(duration.displayText)")
        
        isSessionActive = true
        sessionStartTime = Date()
        sessionEndTime = Date().addingTimeInterval(duration.timeInterval)
        currentSessionDuration = duration
        
        // Clear any existing session data
        dataStore.clearCurrentSession()
        
        // Start location tracking
        locationManager.startTracking()
        
        // Start the update cycle
        startLocationUpdateCycle()
        
        // Set session end timer
        sessionEndTimer = Timer.scheduledTimer(withTimeInterval: duration.timeInterval, repeats: false) { _ in
            self.stopSession()
        }
        
        // Log session start
        logEvent(type: .sessionStart)
    }
    
    func stopSession() {
        print("🛑 Stopping session")
        
        isSessionActive = false
        
        // Stop timers
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        sessionEndTimer?.invalidate()
        sessionEndTimer = nil
        
        // Stop location tracking
        locationManager.stopTracking()
        
        // Save session to history
        if let startTime = sessionStartTime {
            let session = SessionData(
                id: UUID(),
                startTime: startTime,
                endTime: Date(),
                duration: currentSessionDuration,
                events: dataStore.currentSessionEvents
            )
            dataStore.saveSession(session)
        }
        
        // Log session end
        logEvent(type: .sessionEnd)
        
        // Reset session times
        sessionStartTime = nil
        sessionEndTime = nil
        
        // End any active background task
        endBackgroundTask()
    }
    
    // MARK: - Location Update Cycle
    
    private func startLocationUpdateCycle() {
        // Perform first update immediately
        performLocationUpdate()
        
        // Schedule updates every 90 seconds
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { _ in
            self.performLocationUpdate()
        }
    }
    
    private func performLocationUpdate() {
        // Start background task to ensure we complete our work
        beginBackgroundTask()
        
        print("📍 Performing location update at \(Date().formatted(date: .omitted, time: .standard))")
        
        // Get current location
        guard let location = locationManager.currentLocation else {
            print("❌ No location available")
            endBackgroundTask()
            return
        }
        
        // Reverse geocode to get building
        locationManager.reverseGeocode(location: location) { [weak self] building in
            guard let self = self else { return }
            
            // Get current Spotify track
            self.spotifyManager.getCurrentTrack { track in
                if let track = track {
                    // Create listening event
                    let event = ListeningEvent(
                        id: UUID(),
                        timestamp: Date(),
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        buildingName: building,
                        trackName: track.name,
                        artistName: track.artist,
                        albumName: track.album,
                        genre: track.genre,
                        spotifyTrackId: track.id
                    )
                    
                    // Store event
                    self.dataStore.addEvent(event)
                    
                    AnalyticsEngine.shared.processNewEvent(event)
                    
                    print("✅ Logged: \(track.name) by \(track.artist) at \(building ?? "Unknown location")")
                }
                
                // End background task
                self.endBackgroundTask()
            }
        }
    }
    
    // MARK: - Background Task Management
    
    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // If we're running out of time, end the task
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Background Tasks Setup
    
    private func setupBackgroundTasks() {
        // Register background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleBackgroundTask(task: task)
        }
    }
    
    private func handleBackgroundTask(task: BGTask) {
        // Schedule next background task
        scheduleNextBackgroundTask()
        
        // Perform update if session is active
        if isSessionActive {
            performLocationUpdate()
        }
        
        // Mark task as completed
        task.setTaskCompleted(success: true)
    }
    
    private func scheduleNextBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 90) // 90 seconds
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ Could not schedule background task: \(error)")
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Listen for app lifecycle events
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                if self?.isSessionActive == true {
                    self?.scheduleNextBackgroundTask()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                // Cancel any pending background tasks when returning to foreground
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: self?.backgroundTaskIdentifier ?? "")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Logging
    
    private func logEvent(type: SessionEventType) {
        let logMessage: String
        switch type {
        case .sessionStart:
            logMessage = "📱 Session started - Duration: \(currentSessionDuration.displayText)"
        case .sessionEnd:
            logMessage = "🏁 Session ended - Total events: \(dataStore.currentSessionEvents.count)"
        case .locationUpdate:
            logMessage = "📍 Location updated"
        case .spotifyUpdate:
            logMessage = "🎵 Spotify track updated"
        }
        
        print("[\(Date().formatted(date: .omitted, time: .standard))] \(logMessage)")
    }
}

// MARK: - Supporting Types

enum SessionEventType {
    case sessionStart
    case sessionEnd
    case locationUpdate
    case spotifyUpdate
}

enum SessionDuration: CaseIterable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case twelveHours
    case sixteenHours
    
    var displayText: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hr"
        case .twoHours: return "2 hrs"
        case .fourHours: return "4 hrs"
        case .eightHours: return "8 hrs"
        case .twelveHours: return "12 hrs"
        case .sixteenHours: return "16 hrs"
        }
    }
    
    var timeInterval: TimeInterval {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .sixteenHours: return 16 * 60 * 60
        }
    }
}
