import Foundation
import Combine
import BackgroundTasks
import UIKit
import CoreLocation


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
    
    @MainActor func startSession(duration: SessionDuration) {
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
    
    @MainActor func stopSession() {
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
            Task { @MainActor in
                    dataStore.saveSession(session)
                }
        }
        
        // Log session end
        logEvent(type: .sessionEnd)
        
        // Reset session times
        sessionStartTime = nil
        sessionEndTime = nil
        
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

        let bgTaskID = BackgroundTaskManager.shared.beginTask("com.loci.sessionUpdate")
        defer { BackgroundTaskManager.shared.endTask(bgTaskID) }


          // Get current location
          guard let location = locationManager.currentLocation else {
              print("❌ No location available")
                    return
                }
        
        print("📍 Performing location update at \(Date().formatted(date: .omitted, time: .standard))")
        
        Task { [weak self] in
                guard let self = self else { return }

                // Turn CoreLocation into a CLPlacemark lookup
                let clLocation = CLLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                let building = await GeocodingService.shared.reverseGeocode(clLocation)

                // Now fetch Spotify
                self.spotifyManager.getCurrentTrack { track in
                    if let track = track {
                        let event = ListeningEvent(
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

                        // Persist + analytics
                        Task { @MainActor in
                            self.dataStore.addEvent(event)
                        }
                        AnalyticsEngine.shared.processNewEvent(event)

                        print("✅ Logged: \(track.name) by \(track.artist) at \(building ?? "Unknown location")")
                    }
                    // no need to explicitly end—our defer up top handles it
                }
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
    
    @MainActor private func logEvent(type: SessionEventType) {
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
