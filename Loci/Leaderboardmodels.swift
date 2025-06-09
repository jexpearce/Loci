import Foundation
import CoreLocation

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
