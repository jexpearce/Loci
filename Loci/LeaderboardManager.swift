import Foundation
import Combine
import CoreLocation

@MainActor
class LeaderboardManager: ObservableObject {
    static let shared = LeaderboardManager()
    
    
    @Published var currentLeaderboards: [LocationScope: [LeaderboardType: LeaderboardData]] = [:]
    @Published var userSummary: UserLeaderboardSummary?
    @Published var isLoading = false
    @Published var availableArtists: [String] = []
    @Published var availableGenres: [String] = []
    
    private let dataStore = DataStore.shared
    let firebaseManager = FirebaseManager.shared
    private let locationManager = LocationManager.shared
    
    // Cache
    private var lastLocationContext: LocationContext?
    private var lastRefresh: Date?
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    
    private init() {
        loadAvailableOptions()
        
        // Listen for data updates
        NotificationCenter.default.addObserver(
            forName: .leaderboardDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadLeaderboards(forceRefresh: true)
                self?.loadAvailableOptions()
            }
        }
    }
    
    // MARK: - Public Interface
    
    func loadLeaderboards(forceRefresh: Bool = false) async {
        guard shouldRefresh(forceRefresh: forceRefresh) else { return }
        
        isLoading = true
        
        // Get current location context
        let locationContext = await getCurrentLocationContext()
        
        // Load all leaderboards for each scope
        var newLeaderboards: [LocationScope: [LeaderboardType: LeaderboardData]] = [:]
        
        for scope in LocationScope.allCases {
            newLeaderboards[scope] = [:]
            
            // Overall leaderboard for all scopes
            if let overallData = await loadLeaderboard(scope: scope, type: .overall, context: locationContext) {
                newLeaderboards[scope]?[.overall] = overallData
            }
            
            // Artist and genre leaderboards for non-building scopes
            if scope != .building {
                for artist in availableArtists.prefix(10) { // Top 10 artists
                    if let artistData = await loadLeaderboard(scope: scope, type: .artist(artist), context: locationContext) {
                        newLeaderboards[scope]?[.artist(artist)] = artistData
                    }
                }
                
                for genre in availableGenres.prefix(8) { // Top 8 genres
                    if let genreData = await loadLeaderboard(scope: scope, type: .genre(genre), context: locationContext) {
                        newLeaderboards[scope]?[.genre(genre)] = genreData
                    }
                }
            }
        }
        
        // Update published properties
        currentLeaderboards = newLeaderboards
        userSummary = calculateUserSummary(from: newLeaderboards)
        lastLocationContext = locationContext
        lastRefresh = Date()
        
        print("✅ Loaded \(newLeaderboards.count) leaderboard scopes with data")
        
        isLoading = false
    }
    
    func getBestUserRanking() -> BestRanking? {
        return userSummary?.bestRanking
    }
    
    func getLeaderboard(scope: LocationScope, type: LeaderboardType) -> LeaderboardData? {
        return currentLeaderboards[scope]?[type]
    }
    
    // MARK: - Data Loading
    
    private func loadLeaderboard(scope: LocationScope, type: LeaderboardType, context: LocationContext) async -> LeaderboardData? {
        // Get user data from DataStore (which aggregates sessions and imports)
        let userData = dataStore.getLeaderboardData(scope: scope, type: type, context: context)
        guard !userData.isEmpty else { 
            print("⚠️ No user data found for \(scope.displayName) - \(type.displayName)")
            return nil 
        }
        
        print("✅ Found \(userData.count) users for \(scope.displayName) - \(type.displayName)")
        
        // Convert to UserStats for leaderboard display
        let scoreType: ScoreType = (type == .overall && scope == .building) ? .songCount : .minutes
        let userStats = userData.map { user in
            UserStats(
                userId: user.userId,
                username: user.username,
                profileImageURL: user.profileImageURL,
                score: user.getScore(for: type, scoreType: scoreType)
            )
        }.sorted { $0.score > $1.score }
        
        // Convert to leaderboard entries
        let entries = userStats.enumerated().map { index, stat in
            LeaderboardEntry(
                id: stat.userId,
                userId: stat.userId,
                username: stat.username,
                profileImageURL: stat.profileImageURL,
                rank: index + 1,
                score: stat.score,
                scoreType: type == .overall && scope == .building ? .songCount : .minutes,
                location: context.getLocationName(for: scope),
                lastUpdated: Date()
            )
        }
        
        // Find current user rank
        let currentUserId = firebaseManager.currentUser?.id ?? "current-user"
        let userRank = entries.firstIndex { $0.userId == currentUserId }.map { $0 + 1 }
        let userEntry = entries.first { $0.userId == currentUserId }
        
        return LeaderboardData(
            id: "\(scope.rawValue)-\(type.id)",
            scope: scope,
            type: type,
            entries: Array(entries.prefix(20)), // Top 20
            userRank: userRank,
            userEntry: userEntry,
            totalParticipants: userStats.count,
            lastUpdated: Date()
        )
    }
    
    private func getRelevantSessions(for scope: LocationScope, context: LocationContext) -> [Session] {
        let allSessions = dataStore.sessionHistory
        
        switch scope {
        case .building:
            guard let building = context.building else { return [] }
            return allSessions.filter { session in
                session.events.contains { $0.buildingName == building }
            }
            
        case .region:
            guard let region = context.region else { return allSessions }
            return allSessions.filter { session in
                // This would need more sophisticated region matching
                // For now, return all sessions
                return true
            }
            
        case .state, .country, .global:
            // For broader scopes, return all sessions
            // In production, you'd filter by state/country from user profiles
            return allSessions
        }
    }
    

    
    private func calculateScore(sessions: [Session], type: LeaderboardType, userId: String) -> Double {
        // For demo, add some randomness for fake users
        let baseScore: Double
        
        switch type {
        case .overall:
            baseScore = Double(sessions.reduce(0) { $0 + $1.events.count })
            
        case .artist(let artistName):
            baseScore = Double(sessions.reduce(0) { total, session in
                total + session.events.filter { $0.artistName.lowercased().contains(artistName.lowercased()) }.count
            })
            
        case .genre(let genreName):
            baseScore = Double(sessions.reduce(0) { total, session in
                total + session.events.filter { $0.genre?.lowercased().contains(genreName.lowercased()) == true }.count
            })
        }
        
        // Add some fake variance for demo users
        if userId != "current-user" {
            let variance = Double.random(in: 0.5...2.0)
            return max(baseScore * variance, 1)
        }
        
        return baseScore
    }
    
    // MARK: - Helper Methods
    
    private func shouldRefresh(forceRefresh: Bool) -> Bool {
        if forceRefresh { return true }
        
        guard let lastRefresh = lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
    
    private func getCurrentLocationContext() async -> LocationContext {
        // Use cached context if recent
        if let cached = lastLocationContext,
           let lastRefresh = lastRefresh,
           Date().timeIntervalSince(lastRefresh) < 3600 { // 1 hour cache
            return cached
        }
        
        // Get current location
        var context = LocationContext(building: nil, region: nil, state: nil, country: nil, coordinate: nil)
        
        if let location = locationManager.currentLocation {
            context = LocationContext(
                building: "Sample Building", // Would use reverse geocoding
                region: "Sample City",
                state: "Sample State",
                country: "Sample Country",
                coordinate: location.coordinate
            )
        }
        
        return context
    }
    
    private func calculateUserSummary(from leaderboards: [LocationScope: [LeaderboardType: LeaderboardData]]) -> UserLeaderboardSummary {
        var bestRanking: BestRanking?
        var bestRankValue = Int.max
        
        // Find best ranking across all leaderboards
        for (scope, typeDict) in leaderboards {
            for (type, data) in typeDict {
                if let userRank = data.userRank, userRank < bestRankValue {
                    bestRankValue = userRank
                    bestRanking = BestRanking(
                        scope: scope,
                        type: type,
                        rank: userRank,
                        totalParticipants: data.totalParticipants,
                        location: data.entries.first?.location ?? scope.displayName
                    )
                }
            }
        }
        
        return UserLeaderboardSummary(
            bestRanking: bestRanking,
            recentChanges: [], // TODO: Track changes over time
            availableLeaderboards: [] // TODO: Calculate availability
        )
    }
    
    private func loadAvailableOptions() {
        // Get available artists and genres from real data
        let allUserData = dataStore.getLeaderboardData(
            scope: .global,
            type: .overall,
            context: LocationContext(building: nil, region: nil, state: nil, country: nil, coordinate: nil)
        )
        
        // Aggregate all artists and genres across users
        var allArtistScores: [String: Double] = [:]
        var allGenreScores: [String: Double] = [:]
        
        for userData in allUserData {
            for (artist, score) in userData.artistMinutes {
                allArtistScores[artist, default: 0] += score
            }
            for (genre, score) in userData.genreMinutes {
                allGenreScores[genre, default: 0] += score
            }
        }
        
        // Sort by total listening time across all users
        availableArtists = allArtistScores
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { $0.key }
        
        availableGenres = allGenreScores
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
}

// MARK: - Supporting Types

private struct UserStats {
    let userId: String
    let username: String
    let profileImageURL: String?
    let score: Double
}
