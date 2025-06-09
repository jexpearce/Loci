import Foundation
import SwiftData
import Combine
import CloudKit
import CoreLocation

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    let container: ModelContainer

    @Published var currentSessionEvents: [ListeningEvent] = []
    @Published var sessionHistory: [Session] = []
    @Published var sessionMode: SessionMode = .onePlace
    @Published var buildingChanges: [BuildingChange] = []
    
    // One-place session specific properties
    var singleSessionBuildingName: String?
    private var activeOnePlaceSession: Session?

    // MARK: - Designated Location System

    @Published var designatedLocation: DesignatedLocation?

    struct DesignatedLocation: Codable {
        let region: String
        let building: String?
        let coordinate: CLLocationCoordinate2D?
        let lastUpdated: Date
        
        var displayName: String {
            if let building = building {
                return "\(building), \(region)"
            }
            return region
        }
    }

    func setDesignatedLocation(region: String, building: String? = nil, coordinate: CLLocationCoordinate2D? = nil) {
        designatedLocation = DesignatedLocation(
            region: region,
            building: building,
            coordinate: coordinate,
            lastUpdated: Date()
        )
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(designatedLocation) {
            UserDefaults.standard.set(encoded, forKey: "designatedLocation")
        }
        
        print("✅ Set designated location: \(designatedLocation?.displayName ?? "Unknown")")
    }

    func loadDesignatedLocation() {
        if let data = UserDefaults.standard.data(forKey: "designatedLocation"),
           let decoded = try? JSONDecoder().decode(DesignatedLocation.self, from: data) {
            designatedLocation = decoded
            print("✅ Loaded designated location: \(decoded.displayName)")
        }
    }

    func clearDesignatedLocation() {
        designatedLocation = nil
        UserDefaults.standard.removeObject(forKey: "designatedLocation")
    }

    private init() {
        self.container = try! ModelContainer(
            for: Session.self, ListeningEvent.self, BuildingChange.self
        )
        
        fetchSessionHistory()
        loadActiveOnePlaceSession()
        loadDesignatedLocation()
        loadImportedTrackIds()
    }

    // MARK: - Current Session Management

    func addEvent(_ event: ListeningEvent) {
        Task { @MainActor in
            container.mainContext.insert(event)
            try? container.mainContext.save()
            currentSessionEvents.append(event)
            CloudSyncManager.shared.enqueueEvent(event)
            
            // Update active one-place session if applicable
            if sessionMode == .onePlace, let activeSession = activeOnePlaceSession {
                activeSession.events.append(event)
                try? container.mainContext.save()
            }
        }
    }

    func clearCurrentSession() {
        Task { @MainActor in
            currentSessionEvents.removeAll()
            buildingChanges.removeAll()
            singleSessionBuildingName = nil
        }
    }
    
    func setSingleSessionBuilding(_ name: String) {
        singleSessionBuildingName = name
        
        // Update active one-place session if it exists
        if let activeSession = activeOnePlaceSession {
            // We don't update the session building directly here,
            // as building changes are tracked separately
        }
    }

    // MARK: - Building Change Management

    func addBuildingChange(_ change: BuildingChange) {
        Task { @MainActor in
            container.mainContext.insert(change)
            try? container.mainContext.save()
            buildingChanges.append(change)
            
            // Update active one-place session
            if let activeSession = activeOnePlaceSession {
                activeSession.buildingChanges.append(change)
                try? container.mainContext.save()
            }
        }
    }

    // MARK: - One-Place Session Management

    func startOnePlaceSession(building: String) -> Session {
        // End any existing active session first
        endActiveOnePlaceSession()
        
        let session = Session(
            startTime: Date(),
            endTime: Date.distantFuture, // One-place sessions don't have predetermined end times
            duration: .twelveHours, // Default duration, will be updated when session ends
            mode: .onePlace,
            events: []
        )
        session.isActive = true
        
        container.mainContext.insert(session)
        try? container.mainContext.save()
        
        activeOnePlaceSession = session
        sessionMode = .onePlace
        singleSessionBuildingName = building
        
        print("📍 Started one-place session for: \(building)")
        return session
    }
    
    func endActiveOnePlaceSession() {
        guard let activeSession = activeOnePlaceSession else { return }
        
        activeSession.isActive = false
        activeSession.endTime = Date()
        
        // Calculate actual duration
        let actualDuration = activeSession.endTime.timeIntervalSince(activeSession.startTime)
        activeSession.duration = SessionDuration.fromTimeInterval(actualDuration)
        
        try? container.mainContext.save()
        
        // Add to session history if not already there
        if !sessionHistory.contains(where: { $0.id == activeSession.id }) {
            sessionHistory.insert(activeSession, at: 0)
        }
        
        activeOnePlaceSession = nil
        
        print("🏁 Ended one-place session")
    }
    
    func getActiveOnePlaceSession() -> Session? {
        return activeOnePlaceSession
    }
    
    private func loadActiveOnePlaceSession() {
        // Note: With the new session system, active session management
        // is handled by SessionManager, not DataStore
        // This method is kept for compatibility but doesn't need to do anything
        print("📱 DataStore: Active session management now handled by SessionManager")
    }

    // MARK: - Session History Management

    func saveSession(
        startTime: Date,
        endTime: Date,
        duration: SessionDuration,
        mode: SessionMode,
        events: [ListeningEvent]
    ) {
        let session = Session(
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            mode: mode,
            events: events
        )
        
        // Add building changes if this is a one-place session
        if mode == .onePlace {
            session.buildingChanges = buildingChanges
        }
        
        container.mainContext.insert(session)
        
        do {
            try container.mainContext.save()
            print("✅ Session saved with \(events.count) events (mode: \(mode.rawValue))")
            
            // Update session history
            sessionHistory.insert(session, at: 0)
            clearCurrentSession()
            
            // If this was an active one-place session, clear it
            if mode == .onePlace && activeOnePlaceSession?.id == session.id {
                activeOnePlaceSession = nil
            }
            
            // Notify completion
            NotificationCenter.default.post(
                name: .sessionCompleted,
                object: SessionData(
                    id: session.id,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    mode: mode,
                    events: events,
                    buildingChanges: session.buildingChanges,
                    isActive: session.isActive
                )
            )
            
        } catch {
            print("❌ Failed to save session: \(error)")
        }
    }
    
    /// Save a SessionData to persistent storage by converting it to a Session model
    func saveSession(_ sessionData: SessionData) {
        Task { @MainActor in
            let session = Session(
                startTime: sessionData.startTime,
                endTime: sessionData.endTime,
                duration: sessionData.duration,
                mode: sessionData.mode,
                events: sessionData.events
            )
            session.id = sessionData.id
            session.buildingChanges = sessionData.buildingChanges
            session.isActive = sessionData.isActive
            
            container.mainContext.insert(session)
            try? container.mainContext.save()
            sessionHistory.insert(session, at: 0)
            clearCurrentSession()
        }
    }

    private func fetchSessionHistory() {
        Task { @MainActor in
            let descriptor = FetchDescriptor<Session>(
                sortBy: [SortDescriptor(\Session.startTime, order: .reverse)]
            )
            sessionHistory = (try? container.mainContext.fetch(descriptor)) ?? []
        }
    }

    // MARK: - Analytics and Queries

    func getSessionsForBuilding(_ buildingName: String) -> [Session] {
        return sessionHistory.filter { session in
            session.events.contains { $0.buildingName == buildingName } ||
            session.buildingChanges.contains { $0.toBuildingName == buildingName }
        }
    }
    
    func getSessionsForTimeRange(_ timeRange: TimeRange) -> [Session] {
        let startDate = timeRange.startDate
        return sessionHistory.filter { $0.startTime >= startDate }
    }
    
    func getSessionsByMode(_ mode: SessionMode) -> [Session] {
        return sessionHistory.filter { $0.mode == mode }
    }
    
    func getTotalListeningTime() -> TimeInterval {
        return sessionHistory.reduce(0) { total, session in
            total + session.endTime.timeIntervalSince(session.startTime)
        }
    }
    
    func getMostVisitedBuildings(limit: Int = 10) -> [(building: String, visitCount: Int)] {
        var buildingCounts: [String: Int] = [:]
        
        for session in sessionHistory {
            // Count from events
            for event in session.events {
                if let building = event.buildingName {
                    buildingCounts[building, default: 0] += 1
                }
            }
            
            // Count from building changes (one-place sessions)
            for change in session.buildingChanges {
                buildingCounts[change.toBuildingName, default: 0] += 1
            }
        }
        
        return buildingCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (building: $0.key, visitCount: $0.value) }
    }
    // MARK: - Leaderboard Data Integration

    func getLeaderboardData(scope: LocationScope, type: LeaderboardType, context: LocationContext) -> [UserListeningData] {
        print("🔍 DataStore.getLeaderboardData called for scope: \(scope.displayName), type: \(type.displayName)")
        print("🔍 Current sessionHistory count: \(sessionHistory.count)")
        print("🔍 Current importBatches count: \(importBatches.count)")
        
        let result: [UserListeningData]
        switch scope {
        case .building:
            result = getBuildingLeaderboardData(buildingName: context.building, type: type)
        case .region:
            result = getRegionalLeaderboardData(region: context.region, type: type)
        case .global:
            result = getGlobalLeaderboardData(type: type)
        }
        
        print("🔍 Returning \(result.count) user data entries")
        return result
    }

    private func getBuildingLeaderboardData(buildingName: String?, type: LeaderboardType) -> [UserListeningData] {
        guard let building = buildingName else { return [] }
        
        // Get all sessions for this building
        let buildingSessions = sessionHistory.filter { session in
            session.events.contains { $0.buildingName == building }
        }
        
        // Get all import batches for this building
        let buildingImports = importBatches.filter { $0.location == building && $0.assignmentType == .building }
        
        return aggregateUserData(sessions: buildingSessions, imports: buildingImports, type: type)
    }

    private func getRegionalLeaderboardData(region: String?, type: LeaderboardType) -> [UserListeningData] {
        // For now, use all sessions as regional data
        // In production, you'd filter by actual geographic region
        let regionalSessions = sessionHistory
        let regionalImports = importBatches.filter { $0.assignmentType == .region }
        
        return aggregateUserData(sessions: regionalSessions, imports: regionalImports, type: type)
    }

    private func getGlobalLeaderboardData(type: LeaderboardType) -> [UserListeningData] {
        // Use all available data
        return aggregateUserData(sessions: sessionHistory, imports: importBatches, type: type)
    }

    private func aggregateUserData(sessions: [Session], imports: [ImportBatch], type: LeaderboardType) -> [UserListeningData] {
        print("🔍 aggregateUserData called with \(sessions.count) sessions, \(imports.count) imports")
        var userDataMap: [String: UserListeningData] = [:]
        
        // Process sessions
        for session in sessions {
            let userId = "current-user" // In production, get from session.userId
            let username = "You" // In production, get from user profile
            
            if userDataMap[userId] == nil {
                userDataMap[userId] = UserListeningData(
                    userId: userId,
                    username: username,
                    profileImageURL: nil,
                    totalMinutes: 0,
                    totalSongs: 0,
                    artistMinutes: [:],
                    artistSongs: [:],
                    genreMinutes: [:],
                    genreSongs: [:]
                )
            }
            
            // Add session data
            userDataMap[userId]?.addSession(session)
            print("🔍 Added session with \(session.events.count) events")
        }
        
        // Process imports
        for importBatch in imports {
            let userId = "current-user" // In production, get from import.userId
            let username = "You"
            
            if userDataMap[userId] == nil {
                userDataMap[userId] = UserListeningData(
                    userId: userId,
                    username: username,
                    profileImageURL: nil,
                    totalMinutes: 0,
                    totalSongs: 0,
                    artistMinutes: [:],
                    artistSongs: [:],
                    genreMinutes: [:],
                    genreSongs: [:]
                )
            }
            
            // Add import data
            userDataMap[userId]?.addImportBatch(importBatch)
            print("🔍 Added import batch with \(importBatch.tracks.count) tracks")
        }
        
        if let currentUser = userDataMap["current-user"] {
            print("🔍 Current user has \(currentUser.totalSongs) total songs, \(currentUser.totalMinutes) total minutes")
        }
        
        // Add demo users for testing
        addDemoUsers(to: &userDataMap, basedOn: userDataMap["current-user"])
        
        print("🔍 Final userDataMap has \(userDataMap.count) users")
        return Array(userDataMap.values)
    }

    // MARK: - Import Batch Storage

    @Published var importBatches: [ImportBatch] = []
    
    // Track imported songs to prevent duplicates
    private var importedTrackIds: Set<String> = []

    func saveImportBatch(_ batch: ImportBatch) {
        // Add track IDs to imported set
        for track in batch.tracks {
            importedTrackIds.insert(track.id)
        }
        
        importBatches.append(batch)
        
        // Save to persistent storage
        container.mainContext.insert(ImportBatchEntity.from(batch))
        try? container.mainContext.save()
        
        // Save imported track IDs to UserDefaults
        let trackIdArray = Array(importedTrackIds)
        UserDefaults.standard.set(trackIdArray, forKey: "importedTrackIds")
        
        // Trigger leaderboard refresh
        NotificationCenter.default.post(name: .leaderboardDataUpdated, object: batch)
        
        print("✅ Saved import batch: \(batch.tracks.count) tracks to \(batch.location)")
    }
    
    func filterNewTracks<T: SpotifyTrackProtocol>(_ tracks: [T]) -> [T] {
        return tracks.filter { !importedTrackIds.contains($0.id) }
    }
    
    func getNewTrackCount<T: SpotifyTrackProtocol>(_ tracks: [T]) -> Int {
        return filterNewTracks(tracks).count
    }
    
    private func loadImportedTrackIds() {
        if let savedIds = UserDefaults.standard.array(forKey: "importedTrackIds") as? [String] {
            importedTrackIds = Set(savedIds)
            print("✅ Loaded \(importedTrackIds.count) imported track IDs")
        }
    }

    private func addDemoUsers(to userDataMap: inout [String: UserListeningData], basedOn currentUser: UserListeningData?) {
        let demoUsers = [
            ("demo-user-1", "Alex Chen", 1.2),
            ("demo-user-2", "Jordan Smith", 0.8),
            ("demo-user-3", "Taylor Kim", 1.5),
            ("demo-user-4", "Casey Wong", 0.6),
            ("demo-user-5", "Sam Rivera", 2.0)
        ]
        
        guard let currentUserData = currentUser else { return }
        
        for (userId, username, multiplier) in demoUsers {
            let demoData = UserListeningData(
                userId: userId,
                username: username,
                profileImageURL: nil,
                totalMinutes: currentUserData.totalMinutes * multiplier,
                totalSongs: currentUserData.totalSongs * multiplier,
                artistMinutes: currentUserData.artistMinutes.mapValues { $0 * multiplier },
                artistSongs: currentUserData.artistSongs.mapValues { $0 * multiplier },
                genreMinutes: currentUserData.genreMinutes.mapValues { $0 * multiplier },
                genreSongs: currentUserData.genreSongs.mapValues { $0 * multiplier }
            )
            
            userDataMap[userId] = demoData
        }
    }

    // MARK: - Data Management

    func deleteSession(_ session: Session) {
        Task { @MainActor in
            container.mainContext.delete(session)
            try? container.mainContext.save()
            
            // Remove from history
            sessionHistory.removeAll { $0.id == session.id }
            
            // If this was the active session, clear it
            if activeOnePlaceSession?.id == session.id {
                activeOnePlaceSession = nil
            }
        }
    }
    
    func deleteAllSessions() {
        Task { @MainActor in
            for session in sessionHistory {
                container.mainContext.delete(session)
            }
            
            try? container.mainContext.save()
            sessionHistory.removeAll()
            activeOnePlaceSession = nil
            clearCurrentSession()
        }
    }

    // MARK: - Export Utilities

    func exportSessionAsJSON(_ session: Session) -> Data? {
        let sessionData = SessionData(
            id: session.id,
            startTime: session.startTime,
            endTime: session.endTime,
            duration: session.duration,
            mode: session.mode,
            events: session.events,
            buildingChanges: session.buildingChanges,
            isActive: session.isActive
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sessionData)
    }

    func exportSessionAsCSV(_ session: Session) -> String {
        var csv = "Timestamp,Latitude,Longitude,Building,Track,Artist,Album,Genre,SessionMode\n"
        
        for event in session.events {
            let row = [
                ISO8601DateFormatter().string(from: event.timestamp),
                String(event.latitude),
                String(event.longitude),
                event.buildingName ?? "",
                event.trackName,
                event.artistName,
                event.albumName ?? "",
                event.genre ?? "",
                event.sessionMode.rawValue
            ]
            csv += row.map { field in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return field.contains(",") ? "\"\(escaped)\"" : escaped
            }.joined(separator: ",") + "\n"
        }
        
        // Add building changes for one-place sessions
        if session.mode == .onePlace && !session.buildingChanges.isEmpty {
            csv += "\n# Building Changes\n"
            csv += "Timestamp,FromBuilding,ToBuilding,AutoDetected\n"
            
            for change in session.buildingChanges {
                let row = [
                    ISO8601DateFormatter().string(from: change.timestamp),
                    change.fromBuildingName ?? "",
                    change.toBuildingName,
                    String(change.wasAutoDetected)
                ]
                csv += row.map { field in
                    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                    return field.contains(",") ? "\"\(escaped)\"" : escaped
                }.joined(separator: ",") + "\n"
            }
        }
        
        return csv
    }
    
    // MARK: - Statistics
    
    func generateSessionStatistics() -> SessionStatistics {
        let totalSessions = sessionHistory.count
        let onePlaceSessions = getSessionsByMode(.onePlace).count
        let onTheMoveSessions = getSessionsByMode(.onTheMove).count
        
        let totalEvents = sessionHistory.reduce(0) { $0 + $1.events.count }
        let totalListeningTime = getTotalListeningTime()
        
        let uniqueBuildings = Set(sessionHistory.flatMap { session in
            session.events.compactMap { $0.buildingName } +
            session.buildingChanges.map { $0.toBuildingName }
        }).count
        
        let averageSessionLength = totalSessions > 0 ? totalListeningTime / Double(totalSessions) : 0
        
        return SessionStatistics(
            totalSessions: totalSessions,
            onePlaceSessions: onePlaceSessions,
            onTheMoveSessions: onTheMoveSessions,
            totalEvents: totalEvents,
            totalListeningTime: totalListeningTime,
            uniqueBuildings: uniqueBuildings,
            averageSessionLength: averageSessionLength,
            mostVisitedBuildings: getMostVisitedBuildings(limit: 5)
        )
    }
}

// MARK: - Supporting Types

struct SessionStatistics {
    let totalSessions: Int
    let onePlaceSessions: Int
    let onTheMoveSessions: Int
    let totalEvents: Int
    let totalListeningTime: TimeInterval
    let uniqueBuildings: Int
    let averageSessionLength: TimeInterval
    let mostVisitedBuildings: [(building: String, visitCount: Int)]
    
    var formattedTotalListeningTime: String {
        let hours = Int(totalListeningTime) / 3600
        let minutes = (Int(totalListeningTime) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var formattedAverageSessionLength: String {
        let hours = Int(averageSessionLength) / 3600
        let minutes = (Int(averageSessionLength) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - SessionDuration Extension

extension SessionDuration {
    static func fromTimeInterval(_ interval: TimeInterval) -> SessionDuration {
        let hours = interval / 3600
        
        if hours <= 0.5 { return .thirtyMinutes }
        else if hours <= 1 { return .oneHour }
        else if hours <= 2 { return .twoHours }
        else if hours <= 4 { return .fourHours }
        else if hours <= 6 { return .sixHours }
        else if hours <= 8 { return .eightHours }
        else if hours <= 12 { return .twelveHours }
        else { return .sixteenHours }
    }
}



