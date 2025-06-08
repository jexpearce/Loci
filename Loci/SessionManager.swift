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
    @Published private(set) var sessionMode: SessionMode = .onePlace
    @Published var currentBuilding: String?
    @Published var hasDetectedLocationChange = false
    
    private let locationManager = LocationManager.shared
    private let spotifyManager = SpotifyManager.shared
    private let dataStore = DataStore.shared
    private let reverseGeocoding = ReverseGeocoding.shared
    private let enrichmentEngine = EnrichmentEngine.shared
    
    // Session management
    private var locationUpdateTimer: Timer?
    private var sessionEndTimer: Timer?
    private var maxSessionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // One-place mode specific
    private var isMonitoringSignificantChanges = false
    private var lastKnownBuilding: String?
    private var lastKnownCoordinate: CLLocationCoordinate2D?
    
    // Background task identifiers
    private let backgroundTaskIdentifier = "com.loci.sessionUpdate"
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Session limits
    private let maxSessionLength: TimeInterval = 12 * 60 * 60 // 12 hours maximum
    private let onTheMoveMaxLength: TimeInterval = 6 * 60 * 60 // 6 hours for on-the-move
    
    private init() {
        setupNotifications()
        setupLocationMonitoring()
        checkForExistingOnePlaceSession()
    }
    
    // MARK: - Session Control
    
    /// Start a session with the specified mode
    @MainActor func startSession(mode: SessionMode, duration: SessionDuration? = nil, initialBuilding: String? = nil) {
        guard !isSessionActive || mode == .onePlace else {
            print("⚠️ Session already active")
            return
        }
        
        // For one-place mode, check if we should resume or start fresh
        if mode == .onePlace && isSessionActive {
            // Just update the current building if provided
            if let building = initialBuilding {
                updateOnePlaceBuilding(building)
            }
            return
        }
        
        isSessionActive = true
        sessionMode = mode
        sessionStartTime = Date()
        dataStore.clearCurrentSession()
        hasDetectedLocationChange = false

        // Set maximum session length
        let maxLength = mode == .onTheMove ? onTheMoveMaxLength : maxSessionLength
        maxSessionTimer = Timer.scheduledTimer(
            timeInterval: maxLength,
            target: self,
            selector: #selector(stopSessionDueToMaxLength),
            userInfo: nil,
            repeats: false
        )

        switch mode {
        case .onTheMove:
            startOnTheMoveSession(duration: duration)
            
        case .onePlace:
            startOnePlaceSession(initialBuilding: initialBuilding)
            
        case .unknown:
            print("⚠️ Unknown session mode, treating as one-place")
            startOnePlaceSession(initialBuilding: initialBuilding)
        }
        
        logEvent(type: .sessionStart)
    }
    
    private func startOnTheMoveSession(duration: SessionDuration?) {
        // Start continuous location tracking
        locationManager.startTracking()
        startLocationUpdateCycle()
        
        // Auto-stop after specified duration (default 2 hours, max 6 hours)
        let sessionDuration = duration?.timeInterval ?? SessionDuration.twoHours.timeInterval
        let clampedDuration = min(sessionDuration, onTheMoveMaxLength)
        
        sessionEndTime = Date().addingTimeInterval(clampedDuration)
        
        sessionEndTimer = Timer.scheduledTimer(
            timeInterval: clampedDuration,
            target: self,
            selector: #selector(stopSession),
            userInfo: nil,
            repeats: false
        )
        
        print("🎯 Started On-the-Move session for \(clampedDuration/3600) hours")
    }
    
    private func startOnePlaceSession(initialBuilding: String?) {
        // Get current location once
        if let building = initialBuilding {
            currentBuilding = building
            lastKnownBuilding = building
            dataStore.setSingleSessionBuilding(building)
        } else {
            locationManager.requestOneTimeLocation { [weak self] location in
                guard let self = self, let loc = location else {
                    print("❌ Could not get location for one-place session")
                    return
                }
                
                self.reverseGeocoding.reverseGeocode(location: loc) { building in
                    let buildingName = building?.name ?? "Unknown Place"
                    self.currentBuilding = buildingName
                    self.lastKnownBuilding = buildingName
                    self.lastKnownCoordinate = loc.coordinate
                    self.dataStore.setSingleSessionBuilding(buildingName)
                }
            }
        }
        
        // Start monitoring for significant location changes
        startSignificantLocationMonitoring()
        
        // No auto-stop for one-place sessions
        sessionEndTime = nil
        
        print("📍 Started One-Place session")
    }
    
    @objc func stopSession() {
        guard isSessionActive else { return }
        
        let endTime = Date()
        sessionEndTime = endTime
        
        // Clean up timers
        sessionEndTimer?.invalidate()
        sessionEndTimer = nil
        maxSessionTimer?.invalidate()
        maxSessionTimer = nil

        switch sessionMode {
        case .onTheMove:
            stopOnTheMoveSession(endTime: endTime)
            
        case .onePlace:
            stopOnePlaceSession(endTime: endTime)
            
        case .unknown:
            print("⚠️ Stopping unknown session mode")
            stopOnePlaceSession(endTime: endTime)
        }
        
        logEvent(type: .sessionEnd)
        resetSessionState()
    }
    
    private func stopOnTheMoveSession(endTime: Date) {
        // Stop location tracking
        locationManager.stopTracking()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        
        guard let startTime = sessionStartTime else { return }
        
        // Convert current session events to partial events for enrichment
        let partialEvents = dataStore.currentSessionEvents.map { event in
            PartialListeningEvent(
                id: event.id,
                timestamp: event.timestamp,
                latitude: event.latitude,
                longitude: event.longitude,
                buildingName: event.buildingName,
                trackName: event.trackName,
                artistName: event.artistName,
                albumName: event.albumName
            )
        }
        
        // Reconcile with Spotify data using EnrichmentEngine
        Task {
            let enrichedEvents = await enrichmentEngine.reconcileSession(
                sessionStart: startTime,
                sessionEnd: endTime,
                partialEvents: partialEvents,
                sessionMode: .onTheMove
            )
            
            await MainActor.run {
                self.dataStore.saveSession(
                    startTime: startTime,
                    endTime: endTime,
                    duration: self.calculateSessionDuration(start: startTime, end: endTime),
                    mode: .onTheMove,
                    events: enrichedEvents
                )
            }
        }
        
        print("🏁 Stopped On-the-Move session")
    }
    
    private func stopOnePlaceSession(endTime: Date) {
        // Stop significant location monitoring
        stopSignificantLocationMonitoring()
        
        guard let startTime = sessionStartTime else { return }
        let building = currentBuilding ?? "Unknown Place"
        
        // Fetch recently played tracks for the session period
        spotifyManager.fetchRecentlyPlayed(after: startTime, before: endTime) { [weak self] tracks in
            guard let self = self else { return }
            
            let events = tracks.map { track -> ListeningEvent in
                ListeningEvent(
                    timestamp: track.playedAt,
                    latitude: self.lastKnownCoordinate?.latitude ?? 0.0,
                    longitude: self.lastKnownCoordinate?.longitude ?? 0.0,
                    buildingName: building,
                    trackName: track.title,
                    artistName: track.artist,
                    albumName: track.album,
                    genre: nil,
                    spotifyTrackId: track.id,
                    sessionMode: .onePlace
                )
            }
            
            self.dataStore.saveSession(
                startTime: startTime,
                endTime: endTime,
                duration: self.calculateSessionDuration(start: startTime, end: endTime),
                mode: .onePlace,
                events: events
            )
        }
        
        print("🏁 Stopped One-Place session")
    }
    
    private func resetSessionState() {
        isSessionActive = false
        sessionStartTime = nil
        sessionEndTime = nil
        currentBuilding = nil
        lastKnownBuilding = nil
        lastKnownCoordinate = nil
        hasDetectedLocationChange = false
    }
    
    @objc private func stopSessionDueToMaxLength() {
        print("⏰ Session stopped due to maximum length")
        stopSession()
    }
    
    // MARK: - One-Place Session Management
    
    private func startSignificantLocationMonitoring() {
        guard !isMonitoringSignificantChanges else { return }
        
        isMonitoringSignificantChanges = true
        
        // Listen for significant location changes
        NotificationCenter.default.publisher(for: .significantLocationChange)
            .sink { [weak self] _ in
                self?.checkForBuildingChange()
            }
            .store(in: &cancellables)
        
        print("📡 Started monitoring significant location changes")
    }
    
    private func stopSignificantLocationMonitoring() {
        isMonitoringSignificantChanges = false
        cancellables.removeAll()
        print("📡 Stopped monitoring significant location changes")
    }
    
    private func checkForBuildingChange() {
        guard sessionMode == .onePlace, isSessionActive else { return }
        
        locationManager.requestOneTimeLocation { [weak self] location in
            guard let self = self, let loc = location else { return }
            
            self.reverseGeocoding.reverseGeocode(location: loc) { building in
                guard let newBuilding = building else { return }
                
                if newBuilding.name != self.lastKnownBuilding {
                    self.handleBuildingChange(
                        from: self.lastKnownBuilding,
                        to: newBuilding.name,
                        newCoordinate: loc.coordinate
                    )
                }
            }
        }
    }
    
    private func handleBuildingChange(from oldBuilding: String?, to newBuilding: String, newCoordinate: CLLocationCoordinate2D) {
        print("🏢 Building changed: \(oldBuilding ?? "nil") → \(newBuilding)")
        
        // Create building change record
        let buildingChange = BuildingChange(
            timestamp: Date(),
            fromBuilding: oldBuilding,
            toBuilding: newBuilding,
            fromCoordinate: lastKnownCoordinate.map { (lat: $0.latitude, lon: $0.longitude) },
            toCoordinate: (lat: newCoordinate.latitude, lon: newCoordinate.longitude),
            autoDetected: true
        )
        
        // Update session state
        currentBuilding = newBuilding
        lastKnownBuilding = newBuilding
        lastKnownCoordinate = newCoordinate
        hasDetectedLocationChange = true
        
        // Update data store
        dataStore.setSingleSessionBuilding(newBuilding)
        dataStore.addBuildingChange(buildingChange)
        
        // Notify UI
        NotificationCenter.default.post(
            name: .buildingChangeDetected,
            object: buildingChange
        )
    }
    
    private func updateOnePlaceBuilding(_ building: String) {
        guard sessionMode == .onePlace else { return }
        
        currentBuilding = building
        lastKnownBuilding = building
        dataStore.setSingleSessionBuilding(building)
        
        print("📍 Updated one-place building: \(building)")
    }
    
    // MARK: - App Lifecycle Management
    
    private func checkForExistingOnePlaceSession() {
        // Check if there's an active one-place session from previous app launch
        if let activeSession = dataStore.getActiveOnePlaceSession() {
            print("🔄 Resuming one-place session")
            
            isSessionActive = true
            sessionMode = .onePlace
            sessionStartTime = activeSession.startTime
            currentBuilding = activeSession.currentBuilding
            lastKnownBuilding = activeSession.currentBuilding
            
            // Check if location has changed since last time
            checkForBuildingChange()
            
            // Resume monitoring
            startSignificantLocationMonitoring()
        }
    }
    
    // MARK: - On-the-Move Location Updates
    
    private func startLocationUpdateCycle() {
        // Perform first update immediately
        performLocationUpdate()
        
        // Schedule updates every 90 seconds
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { _ in
            self.performLocationUpdate()
        }
    }
    
    func performLocationUpdate() {
        let bgTaskID = BackgroundTaskManager.shared.beginTask("com.loci.sessionUpdate")
        defer { BackgroundTaskManager.shared.endTask(bgTaskID) }

        guard let location = locationManager.currentLocation else {
            print("❌ No location available for update")
            return
        }
        
        print("📍 Performing location update at \(Date().formatted(date: .omitted, time: .standard))")
        
        Task { [weak self] in
            guard let self = self else { return }

            let clLocation = CLLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            
            let building = await GeocodingService.shared.reverseGeocode(clLocation)

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
                        spotifyTrackId: track.id,
                        sessionMode: .onTheMove
                    )

                    Task { @MainActor in
                        self.dataStore.addEvent(event)
                    }
                    AnalyticsEngine.shared.processNewEvent(event)

                    print("✅ Logged: \(track.name) by \(track.artist) at \(building ?? "Unknown location")")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateSessionDuration(start: Date, end: Date) -> SessionDuration {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600
        
        if hours <= 0.5 { return .thirtyMinutes }
        else if hours <= 1 { return .oneHour }
        else if hours <= 2 { return .twoHours }
        else if hours <= 4 { return .fourHours }
        else if hours <= 6 { return .sixHours }
        else if hours <= 8 { return .eightHours }
        else if hours <= 12 { return .twelveHours }
        else { return .sixteenHours }
    }
    
    // MARK: - Location Monitoring Setup
    
    private func setupLocationMonitoring() {
        // Monitor for significant location changes even when app is closed
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    private func handleLocationUpdate(_ location: CLLocation) {
        // Only process for one-place sessions
        guard sessionMode == .onePlace, isSessionActive else { return }
        
        // Check if this is a significant change
        if let lastCoordinate = lastKnownCoordinate {
            let lastLocation = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
            let distance = location.distance(from: lastLocation)
            
            // If moved more than 100 meters, check for building change
            if distance > 100 {
                checkForBuildingChange()
            }
        }
    }
    
    // MARK: - Notifications Setup
    
    private func setupNotifications() {
        // Listen for app lifecycle events
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppDidEnterBackground() {
        if sessionMode == .onTheMove && isSessionActive {
            // Schedule background task for on-the-move sessions
            scheduleBackgroundTask()
        }
        // One-place sessions use significant location changes, no additional background tasks needed
    }
    
    private func handleAppWillEnterForeground() {
        // Cancel any pending background tasks
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        
        // For one-place sessions, check for location changes
        if sessionMode == .onePlace && isSessionActive {
            checkForBuildingChange()
        }
    }
    
    private func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 90) // 90 seconds
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ Could not schedule background task: \(error)")
        }
    }
    
    // MARK: - Public Interface for UI
    
    func canStartSession(mode: SessionMode) -> Bool {
        switch mode {
        case .onePlace:
            return true // Can always start/resume one-place
        case .onTheMove:
            return !isSessionActive || sessionMode != .onTheMove
        case .unknown:
            return false
        }
    }
    
    func getSessionTimeRemaining() -> TimeInterval? {
        guard sessionMode == .onTheMove, let endTime = sessionEndTime else { return nil }
        return max(0, endTime.timeIntervalSince(Date()))
    }
    
    func getSessionElapsed() -> TimeInterval? {
        guard let startTime = sessionStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
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

// MARK: - Notification Extensions

extension Notification.Name {
    static let buildingChangeDetected = Notification.Name("buildingChangeDetected")
    static let significantLocationChange = Notification.Name("significantLocationChange")
}
