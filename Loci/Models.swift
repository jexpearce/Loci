import Foundation
import SwiftData

// MARK: - Session Mode

enum SessionMode: String, CaseIterable, Codable, Identifiable {
    case manual    // "Manual/Region" mode: user picks building/region from a map
    case passive   // One-time GPS ping, pin that building for entire session
    case active    // Continuous (~90s) tracking + partial events
    case unknown   // Fallback for legacy sessions or errors
    
    var id: String { rawValue }
}

// MARK: - SwiftData Models

@Model
class Session {
    @Attribute(.unique) var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var durationRaw: String
    var mode: SessionMode
    @Relationship(deleteRule: .cascade) var events: [ListeningEvent] = []

    init(startTime: Date, endTime: Date, duration: SessionDuration, mode: SessionMode, events: [ListeningEvent] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.durationRaw = duration.rawValue
        self.mode = mode
        self.events = events
    }

    var duration: SessionDuration {
        get { SessionDuration(rawValue: durationRaw) ?? .twelveHours }
        set { durationRaw = newValue.rawValue }
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

    //@Backlink(from: \Session.events) var session: [Session]

    init(timestamp: Date,
         latitude: Double,
         longitude: Double,
         buildingName: String?,
         trackName: String,
         artistName: String,
         albumName: String?,
         genre: String?,
         spotifyTrackId: String) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.buildingName = buildingName
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.genre = genre
        self.spotifyTrackId = spotifyTrackId
    }
}

// MARK: - Non-SwiftData Models

// SessionData is used for in-memory operations and data transfer
struct SessionData: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let duration: SessionDuration
    let events: [ListeningEvent]
    
    init(id: UUID, startTime: Date, endTime: Date, duration: SessionDuration, events: [ListeningEvent]) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.events = events
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
}

// MARK: - Session Duration

enum SessionDuration: String, CaseIterable, Codable {
    case thirtyMinutes = "30min"
    case oneHour = "1hr"
    case twoHours = "2hr"
    case fourHours = "4hr"
    case sixHours = "6hr"
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
}

// MARK: - Extensions for Codable support

extension ListeningEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, latitude, longitude, buildingName
        case trackName, artistName, albumName, genre, spotifyTrackId
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
        
        self.init(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            buildingName: buildingName,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            genre: genre,
            spotifyTrackId: spotifyTrackId
        )
        self.id = id
    }
}
