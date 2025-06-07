import Foundation
import SwiftData

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
    var sessionMode: SessionMode = .unknown

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
struct SessionData: Identifiable, Codable {
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

extension BuildingChange: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, fromBuildingName, toBuildingName
        case fromLatitude, fromLongitude, toLatitude, toLongitude, wasAutoDetected
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(fromBuildingName, forKey: .fromBuildingName)
        try container.encode(toBuildingName, forKey: .toBuildingName)
        try container.encodeIfPresent(fromLatitude, forKey: .fromLatitude)
        try container.encodeIfPresent(fromLongitude, forKey: .fromLongitude)
        try container.encode(toLatitude, forKey: .toLatitude)
        try container.encode(toLongitude, forKey: .toLongitude)
        try container.encode(wasAutoDetected, forKey: .wasAutoDetected)
    }
}

// MARK: - Firebase Models

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let spotifyUserId: String?
    let profileImageURL: String?
    let joinedDate: Date
    let privacySettings: PrivacySettings
    let musicPreferences: MusicPreferences
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
    case invalidData
    case networkError
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
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
