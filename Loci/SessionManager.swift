import Foundation
import Combine
import BackgroundTasks
import UIKit
import CoreLocation
import UserNotifications

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var isSessionActive = false
    @Published var sessionStartTime: Date?
    @Published var sessionEndTime: Date?
    @Published private(set) var sessionMode: SessionMode = .active
    
    private let locationManager = LocationManager.shared
    private let spotifyManager = SpotifyManager.shared
    private let dataStore = DataStore.shared
    private var manualRegionName: String?    // For Manual/Region mode
    
    private var locationUpdateTimer: Timer?
    private var sessionEndTimer: Timer?
    private var maxSessionTimer: Timer? // Maximum session length enforcement
    private var cancellables = Set<AnyCancellable>()
    
    // Background task identifiers
    private let backgroundTaskIdentifier = "com.loci.sessionUpdate"
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Session limits
    private let maxSessionLength: TimeInterval = 12 * 60 * 60 // 12 hours maximum
    
    private init() {
        //setupBackgroundTasks()
        setupNotifications()
    }
    
    // MARK: - Session Control
    
    /// Start a session with the specified mode. Active mode auto-stops after 6 hours.
    @MainActor func startSession(mode: SessionMode, manualRegion: String? = nil) {
        guard !isSessionActive else { return }
        isSessionActive = true
        sessionMode = mode
        manualRegionName = manualRegion   // Will be non-nil if mode == .manual
        sessionStartTime = Date()
        dataStore.clearCurrentSession()

        // Enforce maximum session length for all modes (12 hours)
        maxSessionTimer = Timer.scheduledTimer(
            timeInterval: maxSessionLength,
            target: self,
            selector: #selector(stopSessionDueToMaxLength),
            userInfo: nil,
            repeats: false
        )

        switch mode {
        case .active:
            // ── "Active" (continuous) workflow: unchanged from before ──
            locationManager.startTracking()
            startLocationUpdateCycle()
            // Auto-stop after 6 hours for active mode (in addition to max length)
            sessionEndTimer = Timer.scheduledTimer(
                timeInterval: 6 * 60 * 60, // 6 hours
                target: self,
                selector: #selector(stopSession),
                userInfo: nil,
                repeats: false
            )

        case .passive:
            // ── "Passive" (one‐time) workflow ──
            // Fetch location once, store building name for later
            locationManager.requestOneTimeLocation { [weak self] location in
                guard let self = self, let loc = location else { return }
                self.locationManager.reverseGeocode(location: loc) { placemark in
                    let buildingName = placemark ?? "Unknown Place"
                    self.dataStore.setSingleSessionBuilding(buildingName)
                }
            }

        case .manual:
            // ── "Manual/Region" workflow ──
            // We assume the view already collected `manualRegion` from the user.
            guard let regionName = manualRegionName else {
                // If somehow `manualRegionName` is nil, we can early‐abort or show an error.
                return
            }
            dataStore.setSingleSessionBuilding(regionName)
        }
        
        // Log session start
        logEvent(type: .sessionStart)
    }
    
    @objc func stopSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        sessionEndTimer?.invalidate()
        sessionEndTimer = nil
        maxSessionTimer?.invalidate()
        maxSessionTimer = nil
        sessionEndTime = Date()

        switch sessionMode {
        case .active:
            // ── Active mode: same as your old code ──
            locationManager.stopTracking()
            locationUpdateTimer?.invalidate()
            locationUpdateTimer = nil
            guard let start = sessionStartTime, let end = sessionEndTime else { return }
            spotifyManager.reconcilePartialEvents(within: start, end: end) { [weak self] enrichedEvents in
                guard let self = self else { return }
                self.dataStore.saveSession(
                    startTime: start,
                    endTime: end,
                    duration: .sixHours, // Since we auto-stop after 6 hours or user stops manually
                    mode: .active,
                    events: enrichedEvents
                )
            }

        case .passive:
            // ── Passive: Fetch recently-played for the session window ──
            guard let start = sessionStartTime, let end = sessionEndTime else { return }
            let building = self.dataStore.singleSessionBuildingName ?? "Unknown Place"
            spotifyManager.fetchRecentlyPlayed(after: start, before: end) { [weak self] tracks in
                guard let self = self else { return }
                let passiveEvents = tracks.map { trackData -> ListeningEvent in
                    ListeningEvent(
                        timestamp: trackData.playedAt,
                        latitude: 0.0,
                        longitude: 0.0,
                        buildingName: building,
                        trackName: trackData.title,
                        artistName: trackData.artist,
                        albumName: trackData.album,
                        genre: nil,
                        spotifyTrackId: trackData.id
                    )
                }
                self.dataStore.saveSession(
                    startTime: start,
                    endTime: end,
                    duration: self.calculateSessionDuration(start: start, end: end),
                    mode: .passive,
                    events: passiveEvents
                )
            }

        case .manual:
            // ── Manual/Region: Exactly like passive, but we used a user-picked region instead of a geocode ──
            guard let start = sessionStartTime, let end = sessionEndTime else { return }
            let region = self.dataStore.singleSessionBuildingName ?? "Unknown Place"
            spotifyManager.fetchRecentlyPlayed(after: start, before: end) { [weak self] tracks in
                guard let self = self else { return }
                let manualEvents = tracks.map { trackData -> ListeningEvent in
                    ListeningEvent(
                        timestamp: trackData.playedAt,
                        latitude: 0.0,
                        longitude: 0.0,
                        buildingName: region,
                        trackName: trackData.title,
                        artistName: trackData.artist,
                        albumName: trackData.album,
                        genre: nil,
                        spotifyTrackId: trackData.id
                    )
                }
                self.dataStore.saveSession(
                    startTime: start,
                    endTime: end,
                    duration: self.calculateSessionDuration(start: start, end: end),
                    mode: .manual,
                    events: manualEvents
                )
            }
        }
        
        // Log session end
        logEvent(type: .sessionEnd)
        
        // Reset session times
        sessionStartTime = nil
        sessionEndTime = nil
    }
    
    @objc private func stopSessionDueToMaxLength() {
        print("⏰ Session stopped due to maximum length (12 hours)")
        stopSession()
    }
    
    // MARK: - Helper Methods
    
    private func calculateSessionDuration(start: Date, end: Date) -> SessionDuration {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600
        
        if hours <= 0.5 { return .thirtyMinutes }
        else if hours <= 1 { return .oneHour }
        else if hours <= 2 { return .twoHours }
        else if hours <= 4 { return .fourHours }
        else if hours <= 8 { return .eightHours }
        else if hours <= 12 { return .twelveHours }
        else { return .sixteenHours }
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
    
    func handleBackgroundTask(task: BGTask) {
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
            logMessage = "📱 Session started - Mode: \(sessionMode.rawValue)"
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
