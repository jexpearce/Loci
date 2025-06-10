import Foundation
import SwiftData
import MapKit
// MARK: - Session Mode (Updated for simplified UX)

enum SessionMode: String, CaseIterable, Codable, Identifiable {
    case onePlace  // "One-Place" mode: one-time location, stays until significant change
    case onTheMove // "On the Move" mode: continuous tracking with duration
    case unknown   // Fallback for legacy sessions or errors
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .onePlace: return "One-Place"
        case .onTheMove: return "On the Move"
        case .unknown: return "Unknown"
        }
    }
    
    var description: String {
        switch self {
        case .onePlace: return "Perfect for staying in one location. Automatically detects when you move to a new building."
        case .onTheMove: return "Track your music as you move around. Choose how long to track with automatic stop."
        case .unknown: return "Legacy session mode"
        }
    }
    
    var icon: String {
        switch self {
        case .onePlace: return "location.square.fill"
        case .onTheMove: return "location.fill.viewfinder"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var requiresDuration: Bool {
        switch self {
        case .onePlace: return false
        case .onTheMove: return true
        case .unknown: return false
        }
    }
    
    var supportsBackground: Bool {
        switch self {
        case .onePlace: return true  // Uses significant location changes
        case .onTheMove: return true // Continuous tracking
        case .unknown: return false
        }
    }
}

// MARK: - SwiftData Models

@Model
class Session {
    @Attribute(.unique) var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var durationRaw: String
    var mode: SessionMode
    var privacyLevelRaw: String = SessionPrivacyLevel.friends.rawValue
    
    // New properties for improved UX
    var buildingChanges: [BuildingChange] = []  // Track building transitions for one-place mode
    var isActive: Bool = false  // For one-place sessions that don't technically "end"
    
    @Relationship(deleteRule: .cascade) var events: [ListeningEvent] = []

    init(startTime: Date, endTime: Date, duration: SessionDuration, mode: SessionMode, events: [ListeningEvent] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.durationRaw = duration.rawValue
        self.mode = mode
        self.events = events
        self.isActive = mode == .onePlace // One-place sessions start as active
    }

    var duration: SessionDuration {
        get { SessionDuration(rawValue: durationRaw) ?? .twelveHours }
        set { durationRaw = newValue.rawValue }
    }
    
    // Computed properties for analytics
    var uniqueLocations: Int {
        Set(events.compactMap { $0.buildingName }).count
    }
    
    var currentBuilding: String? {
        if mode == .onePlace && isActive {
            return buildingChanges.last?.toBuildingName ?? events.last?.buildingName
        }
        return events.last?.buildingName
    }
}

@Model
final class ListeningEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var buildingName: String?
    var trackName: String
    var artistName: String
    var albumName: String?
    var genre: String?
    var spotifyTrackId: String
    
    // New property for better tracking
    var sessionMode: SessionMode = SessionMode.unknown

    init(timestamp: Date,
         latitude: Double,
         longitude: Double,
         buildingName: String?,
         trackName: String,
         artistName: String,
         albumName: String?,
         genre: String?,
         spotifyTrackId: String,
         sessionMode: SessionMode = .unknown) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.buildingName = buildingName
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.genre = genre
        self.spotifyTrackId = spotifyTrackId
        self.sessionMode = sessionMode
    }
}

// MARK: - Building Change Tracking (New)

@Model
final class BuildingChange {
    @Attribute(.unique) var id: UUID = UUID()
    var timestamp: Date
    var fromBuildingName: String?
    var toBuildingName: String
    var fromLatitude: Double?
    var fromLongitude: Double?
    var toLatitude: Double
    var toLongitude: Double
    var wasAutoDetected: Bool // vs manual change
    
    init(timestamp: Date,
         fromBuilding: String?,
         toBuilding: String,
         fromCoordinate: (lat: Double, lon: Double)?,
         toCoordinate: (lat: Double, lon: Double),
         autoDetected: Bool = true) {
        self.timestamp = timestamp
        self.fromBuildingName = fromBuilding
        self.toBuildingName = toBuilding
        self.fromLatitude = fromCoordinate?.lat
        self.fromLongitude = fromCoordinate?.lon
        self.toLatitude = toCoordinate.lat
        self.toLongitude = toCoordinate.lon
        self.wasAutoDetected = autoDetected
    }
}

// MARK: - Session Duration (Updated for new modes)

enum SessionDuration: String, CaseIterable, Codable {
    case thirtyMinutes = "30min"
    case oneHour = "1hr"
    case twoHours = "2hr"
    case fourHours = "4hr"
    case sixHours = "6hr"  // Max for onTheMove mode
    case eightHours = "8hr"
    case twelveHours = "12hr"
    case sixteenHours = "16hr"
    
    var displayText: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hr"
        case .twoHours: return "2 hrs"
        case .fourHours: return "4 hrs"
        case .sixHours: return "6 hrs"
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
        case .sixHours: return 6 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .sixteenHours: return 16 * 60 * 60
        }
    }
    
    // Available durations for "On the Move" mode (max 6 hours)
    static var onTheMoveOptions: [SessionDuration] {
        return [.thirtyMinutes, .oneHour, .twoHours, .fourHours, .sixHours]
    }
}

// MARK: - Spotify Import Mode (New - separate from main session modes)

enum SpotifyImportMode: String, CaseIterable, Codable {
    case recentTracks = "recent"     // Import recently played tracks
    case timeRange = "timerange"     // Import tracks from specific time period
    case playlist = "playlist"       // Import from specific playlist
    
    var displayName: String {
        switch self {
        case .recentTracks: return "Recent Tracks"
        case .timeRange: return "Time Period"
        case .playlist: return "From Playlist"
        }
    }
    
    var description: String {
        switch self {
        case .recentTracks: return "Import your recently played tracks from Spotify"
        case .timeRange: return "Import tracks from a specific date and time range"
        case .playlist: return "Import tracks from one of your Spotify playlists"
        }
    }
    
    var icon: String {
        switch self {
        case .recentTracks: return "clock.arrow.circlepath"
        case .timeRange: return "calendar.badge.clock"
        case .playlist: return "music.note.list"
        }
    }
}

// MARK: - Non-SwiftData Models

// SessionData is used for in-memory operations and data transfer
struct SessionData: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let duration: SessionDuration
    let mode: SessionMode
    let events: [ListeningEvent]
    let buildingChanges: [BuildingChange]
    let isActive: Bool
    
    init(id: UUID, startTime: Date, endTime: Date, duration: SessionDuration, mode: SessionMode, events: [ListeningEvent], buildingChanges: [BuildingChange] = [], isActive: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.mode = mode
        self.events = events
        self.buildingChanges = buildingChanges
        self.isActive = isActive
    }
    
    // Computed properties for analytics
    var uniqueLocations: Int {
        Set(events.compactMap { $0.buildingName }).count
    }
    
    var topArtist: String? {
        let artistCounts = Dictionary(grouping: events) { $0.artistName }
            .mapValues { $0.count }
        return artistCounts.max { $0.value < $1.value }?.key
    }
    
    var topTrack: String? {
        let trackCounts = Dictionary(grouping: events) { $0.trackName }
            .mapValues { $0.count }
        return trackCounts.max { $0.value < $1.value }?.key
    }
    
    var topGenre: String? {
        let genreCounts = Dictionary(grouping: events.compactMap { $0.genre }) { $0 }
            .mapValues { $0.count }
        return genreCounts.max { $0.value < $1.value }?.key
    }
    
    var totalMinutes: Int {
        events.count * 90 / 60  // 90 seconds per event
    }
    
    var currentBuilding: String? {
        if mode == .onePlace && isActive {
            return buildingChanges.last?.toBuildingName ?? events.last?.buildingName
        }
        return events.last?.buildingName
    }
}
extension SessionData: Codable {
    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, duration, mode, events, buildingChanges, isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        duration = try container.decode(SessionDuration.self, forKey: .duration)
        mode = try container.decode(SessionMode.self, forKey: .mode)
        events = try container.decode([ListeningEvent].self, forKey: .events)
        let exportedChanges = try container.decodeIfPresent([BuildingChangeExport].self, forKey: .buildingChanges) ?? []
        buildingChanges = exportedChanges.map { exportChange in
            BuildingChange(
                timestamp: exportChange.timestamp,
                fromBuilding: exportChange.fromBuildingName,
                toBuilding: exportChange.toBuildingName,
                fromCoordinate: exportChange.fromLatitude != nil && exportChange.fromLongitude != nil ?
                    (lat: exportChange.fromLatitude!, lon: exportChange.fromLongitude!) : nil,
                toCoordinate: (lat: exportChange.toLatitude, lon: exportChange.toLongitude),
                autoDetected: exportChange.wasAutoDetected
            )
        }
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(mode, forKey: .mode)
        try container.encode(events, forKey: .events)
        try container.encode(buildingChanges.map(BuildingChangeExport.init), forKey: .buildingChanges)
        try container.encode(isActive, forKey: .isActive)
    }
}
struct BuildingChangeExport: Codable {
    let id: UUID
    let timestamp: Date
    let fromBuildingName: String?
    let toBuildingName: String
    let fromLatitude: Double?
    let fromLongitude: Double?
    let toLatitude: Double
    let toLongitude: Double
    let wasAutoDetected: Bool
    
    init(from buildingChange: BuildingChange) {
        self.id = buildingChange.id
        self.timestamp = buildingChange.timestamp
        self.fromBuildingName = buildingChange.fromBuildingName
        self.toBuildingName = buildingChange.toBuildingName
        self.fromLatitude = buildingChange.fromLatitude
        self.fromLongitude = buildingChange.fromLongitude
        self.toLatitude = buildingChange.toLatitude
        self.toLongitude = buildingChange.toLongitude
        self.wasAutoDetected = buildingChange.wasAutoDetected
    }
}

// MARK: - Extensions for Codable support

extension ListeningEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, latitude, longitude, buildingName
        case trackName, artistName, albumName, genre, spotifyTrackId, sessionMode
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(buildingName, forKey: .buildingName)
        try container.encode(trackName, forKey: .trackName)
        try container.encode(artistName, forKey: .artistName)
        try container.encodeIfPresent(albumName, forKey: .albumName)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encode(spotifyTrackId, forKey: .spotifyTrackId)
        try container.encode(sessionMode, forKey: .sessionMode)
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let buildingName = try container.decodeIfPresent(String.self, forKey: .buildingName)
        let trackName = try container.decode(String.self, forKey: .trackName)
        let artistName = try container.decode(String.self, forKey: .artistName)
        let albumName = try container.decodeIfPresent(String.self, forKey: .albumName)
        let genre = try container.decodeIfPresent(String.self, forKey: .genre)
        let spotifyTrackId = try container.decode(String.self, forKey: .spotifyTrackId)
        let sessionMode = try container.decodeIfPresent(SessionMode.self, forKey: .sessionMode) ?? .unknown
        
        self.init(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            buildingName: buildingName,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            genre: genre,
            spotifyTrackId: spotifyTrackId,
            sessionMode: sessionMode
        )
        self.id = id
    }
}

// MARK: - Firebase Models

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let username: String // NEW: Unique username for @mentions and search
    let spotifyUserId: String?
    let profileImageURL: String?
    let joinedDate: Date
    let privacySettings: PrivacySettings
    let musicPreferences: MusicPreferences
    
    // Custom initializer to handle missing username field for existing accounts
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        
        // Handle missing username field for existing accounts
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        print("🔍 User model decoded - username: '\(username)', displayName: '\(displayName)'")
        
        spotifyUserId = try container.decodeIfPresent(String.self, forKey: .spotifyUserId)
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        joinedDate = try container.decode(Date.self, forKey: .joinedDate)
        
        // Handle missing privacy settings
        privacySettings = try container.decodeIfPresent(PrivacySettings.self, forKey: .privacySettings) ?? PrivacySettings()
        
        // Handle missing music preferences
        musicPreferences = try container.decodeIfPresent(MusicPreferences.self, forKey: .musicPreferences) ?? MusicPreferences()
    }
    
    // Keep the regular initializer for creating new users
    init(id: String, email: String, displayName: String, username: String, spotifyUserId: String?, profileImageURL: String?, joinedDate: Date, privacySettings: PrivacySettings, musicPreferences: MusicPreferences) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.username = username
        self.spotifyUserId = spotifyUserId
        self.profileImageURL = profileImageURL
        self.joinedDate = joinedDate
        self.privacySettings = privacySettings
        self.musicPreferences = musicPreferences
    }
    
    // Convert User to UserProfile for friend search
    func toUserProfile() -> UserProfile {
        return UserProfile(
            id: id,
            displayName: displayName,
            username: username,
            email: email,
            spotifyConnected: spotifyUserId != nil,
            joinedDate: joinedDate,
            totalSessions: 0, // Default values since we don't have this data
            totalTracks: 0,
            favoriteLocations: [],
            topGenres: [],
            sessionModePreference: nil,
            privacyLevel: "friends",
            profileImageURL: profileImageURL
        )
    }
}

// MARK: - Session Privacy

enum SessionPrivacyLevel: String, Codable, CaseIterable {
    case `private` = "private"
    case friends = "friends" 
    case `public` = "public"
    
    var displayName: String {
        switch self {
        case .private: return "Private"
        case .friends: return "Friends Only"
        case .public: return "Public"
        }
    }
    
    var icon: String {
        switch self {
        case .private: return "lock.fill"
        case .friends: return "person.2.fill"
        case .public: return "globe"
        }
    }
}

struct PrivacySettings: Codable {
    // Social sharing settings
    var shareLocation: Bool = true
    var shareListeningActivity: Bool = true
    var allowFriendRequests: Bool = true
    var showOnlineStatus: Bool = true
    var defaultSessionPrivacy: SessionPrivacyLevel = .friends
    
    // Top Artists/Songs privacy settings
    var topItemsVisibility: TopItemsVisibility = .friends
    
    // Data precision settings
    var locationPrecision: LocationPrecision = .building
    var timePrecision: TimePrecision = .minute
    var shareTrackNames: Bool = true
    var shareArtistNames: Bool = true
    var allowAnalytics: Bool = true
    
    // User management
    var blockedUsers: Set<String> = []
    
    // Discovery settings
    var allowDiscovery: Bool = true
    var shareProfile: Bool = true
    
    init() {}
}

// MARK: - Privacy Supporting Types

enum LocationPrecision: String, Codable, CaseIterable {
    case exact = "Exact"
    case building = "Building"
    case neighborhood = "Neighborhood"
    case city = "City"
}

enum TimePrecision: String, Codable, CaseIterable {
    case exact = "Exact"
    case minute = "Minute"
    case hour = "Hour"
    case day = "Day"
}

enum TopItemsVisibility: String, Codable, CaseIterable {
    case everyone = "Everyone"
    case friends = "Friends Only"
    case nobody = "Private"
    
    var description: String {
        switch self {
        case .everyone:
            return "Anyone can see your top artists and songs"
        case .friends:
            return "Only your friends can see your top artists and songs"
        case .nobody:
            return "Your top artists and songs are private"
        }
    }
}

struct MusicPreferences: Codable {
    var favoriteGenres: [String] = []
    var favoriteArtists: [String] = []
    var discoverabilityRadius: Double = 1000 // meters
    
    init() {}
}

struct BuildingActivity: Codable, Identifiable {
    let id: String
    let buildingName: String
    let latitude: Double
    let longitude: Double
    let lastActivity: Date
    let activeUsers: Int
    let currentTracks: [TrackInfo]
    let popularGenres: [String]
}

struct TrackInfo: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let album: String?
    let spotifyId: String
    let playCount: Int
    let timestamp: Date
}

// MARK: - Session Privacy Extension

extension Session {
    // For backward compatibility, create a typealias
    typealias PrivacyLevel = SessionPrivacyLevel
    
    var privacyLevel: SessionPrivacyLevel {
        get {
            return SessionPrivacyLevel(rawValue: privacyLevelRaw) ?? .friends
        }
        set {
            privacyLevelRaw = newValue.rawValue
        }
    }
    
    // Computed property for location info
    var location: LocationInfo? {
        guard let firstEvent = events.first else { return nil }
        return LocationInfo(
            latitude: firstEvent.latitude,
            longitude: firstEvent.longitude,
            building: firstEvent.buildingName
        )
    }
}

struct LocationInfo: Codable {
    let latitude: Double
    let longitude: Double
    let building: String?
}

// MARK: - Firebase Errors

enum FirebaseError: Error, LocalizedError {
    case notAuthenticated
    case usernameAlreadyTaken
    case userNotFound
    case invalidData
    case networkError
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .usernameAlreadyTaken:
            return "Username is already taken"
        case .userNotFound:
            return "User not found"
        case .invalidData:
            return "Invalid data format"
        case .networkError:
            return "Network connection error"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}

// MARK: - Matching System Types

struct ListeningFingerprint: Codable {
    let id: UUID
    let artistVector: [Double]
    let genreVector: [Double]
    let locationVector: [Double]
    let timeVector: [Double]
    let diversityScore: Double
    let totalEvents: Int
    let createdAt: Date
}

enum TimeOfDay: String, CaseIterable, Codable {
    case earlyMorning = "earlyMorning"
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"
    case lateNight = "lateNight"
    
    static func from(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .lateNight
        }
    }
    
}

// MARK: - Analytics Types

enum TimeRange: String, Codable {
    case today = "today"
    case thisWeek = "week"
    case thisMonth = "month"
    case allTime = "all"
    
    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: Date())
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        case .allTime:
            return Date.distantPast
        }
    }
}

// MARK: - Supporting Types (Enhanced)

struct SelectedLocationInfo {
    let coordinate: CLLocationCoordinate2D
    let buildingName: String
}

struct SelectedLocation {
    let coordinate: CLLocationCoordinate2D
    let buildingInfo: BuildingInfo
    let source: LocationSource
    
    enum LocationSource {
        case current
        case manual
        case typed
        case automatic  // For building change detection
        
        var icon: String {
            switch self {
            case .current: return "location.fill"
            case .manual: return "map.fill"
            case .typed: return "keyboard"
            case .automatic: return "arrow.triangle.turn.up.right.circle.fill"
            }
        }
        
        var description: String {
            switch self {
            case .current: return "Current location"
            case .manual: return "Selected on map"
            case .typed: return "Manually entered"
            case .automatic: return "Auto-detected"
            }
        }
    }
}

// MARK: - Import Batch Model (NEW)

struct ImportBatch: Identifiable, Codable {
    let id: UUID
    let tracks: [SpotifyImportTrack]  // ✅ Correct type
    let location: String
    let assignmentType: LocationAssignmentType
    let importedAt: Date
}

enum LocationAssignmentType: String, Codable {
    case region
    case building
}
// MARK: - User Listening Data Models

class UserListeningData {
    let userId: String
    let username: String
    let profileImageURL: String?
    var totalMinutes: Double
    var totalSongs: Double
    var artistMinutes: [String: Double]
    var artistSongs: [String: Double]
    var genreMinutes: [String: Double]
    var genreSongs: [String: Double]
    
    init(userId: String, username: String, profileImageURL: String?,
         totalMinutes: Double, totalSongs: Double,
         artistMinutes: [String: Double], artistSongs: [String: Double],
         genreMinutes: [String: Double], genreSongs: [String: Double]) {
        self.userId = userId
        self.username = username
        self.profileImageURL = profileImageURL
        self.totalMinutes = totalMinutes
        self.totalSongs = totalSongs
        self.artistMinutes = artistMinutes
        self.artistSongs = artistSongs
        self.genreMinutes = genreMinutes
        self.genreSongs = genreSongs
    }
    
    func addSession(_ session: Session) {
        // Use consistent 3-minute average per track for both sessions and imports
        let sessionMinutes = Double(session.events.count) * 3.0 
        totalMinutes += sessionMinutes
        totalSongs += Double(session.events.count)
        
        // Add artist data
        for event in session.events {
            artistMinutes[event.artistName, default: 0] += 3.0
            artistSongs[event.artistName, default: 0] += 1
            
            if let genre = event.genre {
                genreMinutes[genre, default: 0] += 3.0
                genreSongs[genre, default: 0] += 1
            }
        }
    }
    
    func addImportBatch(_ batch: ImportBatch) {
        // Use actual track durations instead of assuming 3 minutes
        var batchMinutes = 0.0
        for track in batch.tracks {
            let trackMinutes = track.durationMinutes
            batchMinutes += trackMinutes
            
            // Add artist data with actual duration
            artistMinutes[track.artist, default: 0] += trackMinutes
            artistSongs[track.artist, default: 0] += 1
        }
        
        totalMinutes += batchMinutes
        totalSongs += Double(batch.tracks.count)
    }
    
    func getScore(for type: LeaderboardType, artistName: String? = nil) -> Double {
        switch type {
        case .totalMinutes:
            return totalMinutes
            
        case .artistMinutes:
            guard let artist = artistName else { return 0 }
            return artistMinutes[artist, default: 0]
        }
    }
}
// MARK: - Protocol for Track Filtering
protocol SpotifyTrackProtocol {
    var id: String { get }
}

// MARK: - UI Models for Import (Different from EnrichmentEngine internals)

struct SpotifyImportTrack: Identifiable, Codable, SpotifyTrackProtocol {
    let id: String
    let name: String
    let artist: String
    let album: String
    let playedAt: Date
    let imageURL: String?
    let durationMs: Int // Duration in milliseconds from Spotify
    
    var durationMinutes: Double {
        return Double(durationMs) / 60000.0 // Convert ms to minutes
    }
}

enum SpotifyError: Error {
    case notAuthenticated
    case invalidResponse
    case networkError
}

// MARK: - Import Batch Entity for SwiftData

@Model
class ImportBatchEntity {
    @Attribute(.unique) var id: UUID
    var tracksData: Data // JSON encoded SpotifyImportTrack array  // ✅ Update comment
        var location: String
        var assignmentTypeRaw: String
        var importedAt: Date
    
    init(id: UUID, tracksData: Data, location: String, assignmentType: LocationAssignmentType, importedAt: Date) {
        self.id = id
        self.tracksData = tracksData
        self.location = location
        self.assignmentTypeRaw = assignmentType.rawValue
        self.importedAt = importedAt
    }
    
    var assignmentType: LocationAssignmentType {
        LocationAssignmentType(rawValue: assignmentTypeRaw) ?? .region
    }
    
    var tracks: [SpotifyImportTrack] {  // ✅ Change return type
            (try? JSONDecoder().decode([SpotifyImportTrack].self, from: tracksData)) ?? []
        }
    
    static func from(_ batch: ImportBatch) -> ImportBatchEntity {
        let tracksData = (try? JSONEncoder().encode(batch.tracks)) ?? Data()
        return ImportBatchEntity(
            id: batch.id,
            tracksData: tracksData,
            location: batch.location,
            assignmentType: batch.assignmentType,
            importedAt: batch.importedAt
        )
    }
}

extension Notification.Name {
    static let leaderboardDataUpdated = Notification.Name("leaderboardDataUpdated")
}
