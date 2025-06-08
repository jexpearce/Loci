import Foundation
import CoreLocation

// MARK: - Leaderboard Models

enum LocationScope: String, CaseIterable, Identifiable {
    case building = "building"
    case region = "region"
    case state = "state"
    case country = "country"
    case global = "global"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .building: return "Building"
        case .region: return "Region"
        case .state: return "State"
        case .country: return "Country"
        case .global: return "Global"
        }
    }
    
    var icon: String {
        switch self {
        case .building: return "building.2"
        case .region: return "map"
        case .state: return "map.fill"
        case .country: return "globe.americas"
        case .global: return "globe"
        }
    }
}

enum LeaderboardType: Identifiable, Hashable {
    case overall
    case artist(String)
    case genre(String)
    
    var id: String {
        switch self {
        case .overall: return "overall"
        case .artist(let name): return "artist-\(name)"
        case .genre(let name): return "genre-\(name)"
        }
    }
    
    var displayName: String {
        switch self {
        case .overall: return "Overall Listening"
        case .artist(let name): return name
        case .genre(let name): return "\(name) Music"
        }
    }
    
    var category: LeaderboardCategory {
        switch self {
        case .overall: return .overall
        case .artist: return .artist
        case .genre: return .genre
        }
    }
}

enum LeaderboardCategory: String, CaseIterable {
    case overall = "overall"
    case artist = "artist"
    case genre = "genre"
    
    var displayName: String {
        switch self {
        case .overall: return "Overall"
        case .artist: return "Artists"
        case .genre: return "Genres"
        }
    }
}

struct LeaderboardEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let profileImageURL: String?
    let rank: Int
    let score: Double // minutes listened or song count
    let scoreType: ScoreType
    let location: String
    let lastUpdated: Date
    
    var formattedScore: String {
        switch scoreType {
        case .minutes:
            let hours = Int(score) / 60
            let minutes = Int(score) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(Int(score))m"
            }
        case .songCount:
            return "\(Int(score)) songs"
        }
    }
}

enum ScoreType: String, Codable {
    case minutes = "minutes"
    case songCount = "songs"
    
    var displayUnit: String {
        switch self {
        case .minutes: return "minutes"
        case .songCount: return "songs"
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
    let recentChanges: [RankingChange]
    let availableLeaderboards: [LeaderboardAvailability]
}

struct BestRanking {
    let scope: LocationScope
    let type: LeaderboardType
    let rank: Int
    let totalParticipants: Int
    let location: String
    
    var displayText: String {
        switch type {
        case .overall:
            return "You're #\(rank) in \(location)"
        case .artist(let artist):
            return "You're #\(rank) for \(artist) in \(location)"
        case .genre(let genre):
            return "You're #\(rank) for \(genre) in \(location)"
        }
    }
}

struct RankingChange {
    let scope: LocationScope
    let type: LeaderboardType
    let previousRank: Int
    let currentRank: Int
    let change: Int // positive = went up, negative = went down
    
    var isImprovement: Bool { change > 0 }
}

struct LeaderboardAvailability {
    let scope: LocationScope
    let type: LeaderboardType
    let hasData: Bool
    let participantCount: Int
}

// MARK: - Location Context

struct LocationContext {
    let building: String?
    let region: String?
    let state: String?
    let country: String?
    let coordinate: CLLocationCoordinate2D?
    
    func getLocationName(for scope: LocationScope) -> String {
        switch scope {
        case .building: return building ?? "Your Building"
        case .region: return region ?? "Your Region"
        case .state: return state ?? "Your State"
        case .country: return country ?? "Your Country"
        case .global: return "Global"
        }
    }
}
