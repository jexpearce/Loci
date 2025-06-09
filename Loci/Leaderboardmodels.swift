import Foundation
import CoreLocation

// MARK: - Leaderboard Privacy Models

enum LeaderboardPrivacyLevel: String, CaseIterable, Codable {
    case publicGlobal = "public_global"      // All leaderboards with real name
    case publicRegional = "public_regional"  // Only regional leaderboards with real name
    case anonymous = "anonymous"       // On leaderboards but username hidden
    case privateMode = "private"       // Not on any leaderboards
    
    var displayName: String {
        switch self {
        case .publicGlobal: return "Public"
        case .publicRegional: return "Regional Only"
        case .anonymous: return "Anonymous"
        case .privateMode: return "Private"
        }
    }
    
    var description: String {
        switch self {
        case .publicGlobal: return "Share your name on all leaderboards"
        case .publicRegional: return "Share your name in regional leaderboards only"
        case .anonymous: return "Appear on leaderboards without your name"
        case .privateMode: return "Your data stays completely private"
        }
    }
    
    var includesScope: (LocationScope) -> Bool {
        return { scope in
            switch self {
            case .publicGlobal: return true
            case .publicRegional: return scope != .global
            case .anonymous: return true
            case .privateMode: return false
            }
        }
    }
    
    var showsRealName: Bool {
        switch self {
        case .publicGlobal, .publicRegional: return true
        case .anonymous, .privateMode: return false
        }
    }
}

struct LeaderboardPrivacySettings: Codable {
    var privacyLevel: LeaderboardPrivacyLevel
    var shareArtistData: Bool
    var shareTotalTime: Bool
    var hasGivenConsent: Bool
    var consentDate: Date?
    
    static let `default` = LeaderboardPrivacySettings(
        privacyLevel: .publicGlobal,
        shareArtistData: true,
        shareTotalTime: true,
        hasGivenConsent: false,
        consentDate: nil
    )
}

struct LeaderboardConsentInfo {
    let title: String
    let description: String
    let dataTypes: [LeaderboardDataType]
    let privacyLevels: [LeaderboardPrivacyLevel]
}

enum LeaderboardDataType: String, CaseIterable, Identifiable {
    case totalListeningTime = "total_time"
    case topArtists = "top_artists"
    case location = "location"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .totalListeningTime: return "Total Listening Time"
        case .topArtists: return "Top Artists"
        case .location: return "General Location"
        }
    }
    
    var description: String {
        switch self {
        case .totalListeningTime: return "How many minutes you've listened to music"
        case .topArtists: return "Your most played artists and listening time per artist"
        case .location: return "Your general region/building (never exact location)"
        }
    }
    
    var icon: String {
        switch self {
        case .totalListeningTime: return "clock"
        case .topArtists: return "music.note"
        case .location: return "location.circle"
        }
    }
}

// MARK: - Simplified Leaderboard Models

enum LocationScope: String, CaseIterable, Identifiable {
    case building = "building"
    case region = "region"
    case global = "global"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .building: return "Building"
        case .region: return "Region"
        case .global: return "Global"
        }
    }
    
    var icon: String {
        switch self {
        case .building: return "building.2"
        case .region: return "map"
        case .global: return "globe"
        }
    }
}

enum LeaderboardType: String, CaseIterable, Identifiable {
    case artistMinutes = "artist_minutes"
    case totalMinutes = "total_minutes"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .artistMinutes: return "Top Artist"
        case .totalMinutes: return "Total Time"
        }
    }
    
    var description: String {
        switch self {
        case .artistMinutes: return "Most listened artist"
        case .totalMinutes: return "Total listening time"
        }
    }
}

struct LeaderboardEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let profileImageURL: String?
    let rank: Int
    let minutes: Double
    let artistName: String? // Only for artist leaderboards
    let location: String
    let lastUpdated: Date
    let isAnonymous: Bool
    
    var displayName: String {
        isAnonymous ? "Anonymous User" : username
    }
    
    var formattedMinutes: String {
        let hours = Int(minutes) / 60
        let remainingMinutes = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(Int(minutes))m"
        }
    }
}

struct LeaderboardData: Identifiable {
    let id: String
    let scope: LocationScope
    let type: LeaderboardType
    let entries: [LeaderboardEntry]
    let userRank: Int?
    let userEntry: LeaderboardEntry?
    let totalParticipants: Int
    let lastUpdated: Date
    
    var isEmpty: Bool { entries.isEmpty }
}

struct UserLeaderboardSummary {
    let bestRanking: BestRanking?
    let totalLeaderboards: Int
}

struct BestRanking {
    let scope: LocationScope
    let type: LeaderboardType
    let rank: Int
    let totalParticipants: Int
    let location: String
    let artistName: String?
    
    var displayText: String {
        switch type {
        case .totalMinutes:
            return "#\(rank) in \(location)"
        case .artistMinutes:
            if let artist = artistName {
                return "#\(rank) for \(artist)"
            } else {
                return "#\(rank) artist listener"
            }
        }
    }
}

// MARK: - Location Context

struct LocationContext {
    let building: String?
    let region: String?
    let coordinate: CLLocationCoordinate2D?
    
    func getLocationName(for scope: LocationScope) -> String {
        switch scope {
        case .building: return building ?? "Your Building"
        case .region: return region ?? "Your Region"
        case .global: return "Global"
        }
    }
}

// MARK: - Firebase Leaderboard Models

struct FirebaseLeaderboardEntry: Codable {
    let userId: String
    let username: String
    let profileImageURL: String?
    let totalMinutes: Double
    let artistMinutes: [String: Double]
    let location: String
    let isAnonymous: Bool
    let lastUpdated: Date
    
    // Location context for proper filtering
    let building: String?
    let region: String?
    let coordinate: [String: Double]? // lat/lng for distance calculations
}
