import Foundation
import Combine

class DataStore: ObservableObject {
    static let shared = DataStore()
    
    @Published var currentSessionEvents: [ListeningEvent] = []
    @Published var sessionHistory: [SessionData] = []
    
    private let userDefaults = UserDefaults.standard
    private let sessionHistoryKey = "com.loci.sessionHistory"
    private let maxHistorySessions = 50
    
    private init() {
        loadSessionHistory()
    }
    
    // MARK: - Current Session Management
    
    func addEvent(_ event: ListeningEvent) {
        DispatchQueue.main.async {
            self.currentSessionEvents.append(event)
            print("💾 Event stored: \(event.trackName) at \(event.buildingName ?? "Unknown")")
        }
    }
    
    func clearCurrentSession() {
        DispatchQueue.main.async {
            self.currentSessionEvents.removeAll()
        }
    }
    
    // MARK: - Session History Management
    
    func saveSession(_ session: SessionData) {
        DispatchQueue.main.async {
            self.sessionHistory.insert(session, at: 0)
            
            // Limit history size
            if self.sessionHistory.count > self.maxHistorySessions {
                self.sessionHistory = Array(self.sessionHistory.prefix(self.maxHistorySessions))
            }
            
            self.persistSessionHistory()
            print("💾 Session saved to history. Total sessions: \(self.sessionHistory.count)")
        }
    }
    
    private func loadSessionHistory() {
        guard let data = userDefaults.data(forKey: sessionHistoryKey),
              let decoded = try? JSONDecoder().decode([SessionData].self, from: data) else {
            print("📱 No session history found")
            return
        }
        
        sessionHistory = decoded
        print("📱 Loaded \(sessionHistory.count) sessions from history")
    }
    
    private func persistSessionHistory() {
        guard let encoded = try? JSONEncoder().encode(sessionHistory) else {
            print("❌ Failed to encode session history")
            return
        }
        
        userDefaults.set(encoded, forKey: sessionHistoryKey)
    }
    
    // MARK: - Analytics
    
    func getSessionAnalytics(for session: SessionData) -> SessionAnalytics {
        let uniqueArtists = Set(session.events.map { $0.artistName })
        let uniqueTracks = Set(session.events.map { $0.trackName })
        let uniqueLocations = Set(session.events.compactMap { $0.buildingName })
        
        // Count tracks per artist
        var artistCounts: [String: Int] = [:]
        for event in session.events {
            artistCounts[event.artistName, default: 0] += 1
        }
        
        let topArtist = artistCounts.max(by: { $0.value < $1.value })?.key
        
        // Count tracks per location
        var locationCounts: [String: Int] = [:]
        for event in session.events {
            if let building = event.buildingName {
                locationCounts[building, default: 0] += 1
            }
        }
        
        let topLocation = locationCounts.max(by: { $0.value < $1.value })?.key
        
        // Genre distribution (when available)
        var genreCounts: [String: Int] = [:]
        for event in session.events {
            if let genre = event.genre {
                genreCounts[genre, default: 0] += 1
            }
        }
        
        return SessionAnalytics(
            totalTracks: session.events.count,
            uniqueArtists: uniqueArtists.count,
            uniqueTracks: uniqueTracks.count,
            uniqueLocations: uniqueLocations.count,
            topArtist: topArtist,
            topLocation: topLocation,
            genreDistribution: genreCounts
        )
    }
    
    // MARK: - Export Functions
    
    func exportSessionAsJSON(_ session: SessionData) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        return try? encoder.encode(session)
    }
    
    func exportSessionAsCSV(_ session: SessionData) -> String {
        var csv = "Timestamp,Latitude,Longitude,Building,Track,Artist,Album,Genre\n"
        
        for event in session.events {
            let row = [
                event.timestamp.ISO8601Format(),
                String(event.latitude),
                String(event.longitude),
                event.buildingName ?? "",
                event.trackName,
                event.artistName,
                event.albumName ?? "",
                event.genre ?? ""
            ]
            
            csv += row.map { field in
                // Escape quotes and wrap in quotes if contains comma
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return field.contains(",") ? "\"\(escaped)\"" : escaped
            }.joined(separator: ",") + "\n"
        }
        
        return csv
    }
}

// MARK: - Models

struct ListeningEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let buildingName: String?
    let trackName: String
    let artistName: String
    let albumName: String?
    let genre: String?
    let spotifyTrackId: String
}

struct SessionData: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let duration: SessionDuration
    let events: [ListeningEvent]
    
    // Computed properties for UI
    var uniqueLocations: Int {
        Set(events.compactMap { $0.buildingName }).count
    }
    
    var topArtist: String? {
        let artistCounts = events.reduce(into: [String: Int]()) { counts, event in
            counts[event.artistName, default: 0] += 1
        }
        return artistCounts.max(by: { $0.value < $1.value })?.key
    }
}

struct SessionAnalytics {
    let totalTracks: Int
    let uniqueArtists: Int
    let uniqueTracks: Int
    let uniqueLocations: Int
    let topArtist: String?
    let topLocation: String?
    let genreDistribution: [String: Int]
}

// MARK: - Extensions for Codable

extension SessionDuration: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue {
        case "thirtyMinutes": self = .thirtyMinutes
        case "oneHour": self = .oneHour
        case "twoHours": self = .twoHours
        case "fourHours": self = .fourHours
        case "eightHours": self = .eightHours
        case "twelveHours": self = .twelveHours
        case "sixteenHours": self = .sixteenHours
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid session duration: \(rawValue)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: String
        
        switch self {
        case .thirtyMinutes: rawValue = "thirtyMinutes"
        case .oneHour: rawValue = "oneHour"
        case .twoHours: rawValue = "twoHours"
        case .fourHours: rawValue = "fourHours"
        case .eightHours: rawValue = "eightHours"
        case .twelveHours: rawValue = "twelveHours"
        case .sixteenHours: rawValue = "sixteenHours"
        }
        
        try container.encode(rawValue)
    }
}
