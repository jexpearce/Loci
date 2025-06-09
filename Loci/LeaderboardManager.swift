import Foundation
import Combine
import CoreLocation

@MainActor
class LeaderboardManager: ObservableObject {
    static let shared = LeaderboardManager()
    
    @Published var currentLeaderboards: [LocationScope: [LeaderboardType: LeaderboardData]] = [:]
    @Published var userSummary: UserLeaderboardSummary?
    @Published var isLoading = false
    @Published var topArtist: String?
    
    private let dataStore = DataStore.shared
    private let firebaseManager = FirebaseManager.shared
    private let locationManager = LocationManager.shared
    
    // Cache
    private var lastLocationContext: LocationContext?
    private var lastRefresh: Date?
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    
    private init() {
        loadTopArtist()
        
        // Listen for data updates
        NotificationCenter.default.addObserver(
            forName: .leaderboardDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadLeaderboards(forceRefresh: true)
                self?.loadTopArtist()
            }
        }
    }
    
    // MARK: - Public Interface
    
    func loadLeaderboards(forceRefresh: Bool = false) async {
        guard shouldRefresh(forceRefresh: forceRefresh) else { return }
        
        isLoading = true
        
        let locationContext = await getCurrentLocationContext()
        var newLeaderboards: [LocationScope: [LeaderboardType: LeaderboardData]] = [:]
        
        // Load leaderboards for each scope and type
        for scope in LocationScope.allCases {
            newLeaderboards[scope] = [:]
            
            // Total minutes leaderboard
            if let totalData = await loadLeaderboard(scope: scope, type: .totalMinutes, context: locationContext) {
                newLeaderboards[scope]?[.totalMinutes] = totalData
            }
            
            // Artist minutes leaderboard (only if we have a top artist)
            if let artist = topArtist,
               let artistData = await loadLeaderboard(scope: scope, type: .artistMinutes, context: locationContext, artistName: artist) {
                newLeaderboards[scope]?[.artistMinutes] = artistData
            }
        }
        
        currentLeaderboards = newLeaderboards
        userSummary = calculateUserSummary(from: newLeaderboards)
        lastLocationContext = locationContext
        lastRefresh = Date()
        
        print("✅ Loaded simplified leaderboards")
        
        isLoading = false
    }
    
    func getBestUserRanking() -> BestRanking? {
        return userSummary?.bestRanking
    }
    
    func getLeaderboard(scope: LocationScope, type: LeaderboardType) -> LeaderboardData? {
        return currentLeaderboards[scope]?[type]
    }
    
    // MARK: - Data Loading
    
    private func loadLeaderboard(scope: LocationScope, type: LeaderboardType, context: LocationContext, artistName: String? = nil) async -> LeaderboardData? {
        // Get user data directly from DataStore using a simplified approach
        let userData = getSimplifiedLeaderboardData(scope: scope, type: type, context: context, artistName: artistName)
        guard !userData.isEmpty else { return nil }
        
        let userStats = userData.compactMap { (user: UserListeningData) -> UserStats? in
            let minutes: Double
            
            switch type {
            case .totalMinutes:
                minutes = user.totalMinutes
            case .artistMinutes:
                guard let artist = artistName else { return nil }
                minutes = user.artistMinutes[artist] ?? 0
                if minutes == 0 { return nil }
            }
            
            return UserStats(
                userId: user.userId,
                username: user.username,
                profileImageURL: user.profileImageURL,
                minutes: minutes,
                artistName: artistName
            )
        }.sorted { (a: UserStats, b: UserStats) -> Bool in
            a.minutes > b.minutes
        }
        
        let entries = userStats.enumerated().map { index, stat in
            LeaderboardEntry(
                id: stat.userId,
                userId: stat.userId,
                username: stat.username,
                profileImageURL: stat.profileImageURL,
                rank: index + 1,
                minutes: stat.minutes,
                artistName: stat.artistName,
                location: context.getLocationName(for: scope),
                lastUpdated: Date()
            )
        }
        
        let currentUserId = firebaseManager.currentUser?.id ?? "current-user"
        let userRank = entries.firstIndex { $0.userId == currentUserId }.map { $0 + 1 }
        let userEntry = entries.first { $0.userId == currentUserId }
        
        return LeaderboardData(
            id: "\(scope.rawValue)-\(type.rawValue)",
            scope: scope,
            type: type,
            entries: Array(entries.prefix(20)), // Top 20
            userRank: userRank,
            userEntry: userEntry,
            totalParticipants: userStats.count,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Helper Methods
    
    private func getSimplifiedLeaderboardData(scope: LocationScope, type: LeaderboardType, context: LocationContext, artistName: String?) -> [UserListeningData] {
        // Get all user data by aggregating sessions and imports directly
        var userDataMap: [String: UserListeningData] = [:]
        
        // Get sessions based on scope
        let sessions: [Session]
        switch scope {
        case .building:
            guard let building = context.building else { return [] }
            sessions = dataStore.sessionHistory.filter { session in
                session.events.contains { $0.buildingName == building }
            }
        case .region:
            // For now, use all sessions as regional data
            sessions = dataStore.sessionHistory
        case .global:
            sessions = dataStore.sessionHistory
        }
        
        // Get imports based on scope
        let imports: [ImportBatch]
        switch scope {
        case .building:
            guard let building = context.building else { return [] }
            imports = dataStore.importBatches.filter { $0.location == building && $0.assignmentType == .building }
        case .region:
            imports = dataStore.importBatches.filter { $0.assignmentType == .region }
        case .global:
            imports = dataStore.importBatches
        }
        
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
            
            userDataMap[userId]?.addSession(session)
        }
        
        // Process imports
        for importBatch in imports {
            let userId = "current-user"
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
            
            userDataMap[userId]?.addImportBatch(importBatch)
        }
        
        // Add demo users for testing
        if let currentUser = userDataMap["current-user"] {
            addDemoUsers(to: &userDataMap, basedOn: currentUser)
        }
        
        return Array(userDataMap.values)
    }
    
    private func addDemoUsers(to userDataMap: inout [String: UserListeningData], basedOn currentUser: UserListeningData) {
        let demoUsers = [
            ("demo-user-1", "Alex Chen", 1.2),
            ("demo-user-2", "Jordan Smith", 0.8),
            ("demo-user-3", "Taylor Kim", 1.5),
            ("demo-user-4", "Casey Wong", 0.6),
            ("demo-user-5", "Sam Rivera", 2.0)
        ]
        
        for (userId, username, multiplier) in demoUsers {
            let demoData = UserListeningData(
                userId: userId,
                username: username,
                profileImageURL: nil,
                totalMinutes: currentUser.totalMinutes * multiplier,
                totalSongs: currentUser.totalSongs * multiplier,
                artistMinutes: currentUser.artistMinutes.mapValues { $0 * multiplier },
                artistSongs: currentUser.artistSongs.mapValues { $0 * multiplier },
                genreMinutes: currentUser.genreMinutes.mapValues { $0 * multiplier },
                genreSongs: currentUser.genreSongs.mapValues { $0 * multiplier }
            )
            
            userDataMap[userId] = demoData
        }
    }
    
    private func shouldRefresh(forceRefresh: Bool) -> Bool {
        if forceRefresh { return true }
        guard let lastRefresh = lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
    
    private func getCurrentLocationContext() async -> LocationContext {
        if let cached = lastLocationContext,
           let lastRefresh = lastRefresh,
           Date().timeIntervalSince(lastRefresh) < 3600 {
            return cached
        }
        
        var context = LocationContext(building: nil, region: nil, coordinate: nil)
        
        if let location = locationManager.currentLocation {
            context = LocationContext(
                building: "Sample Building",
                region: "Sample City",
                coordinate: location.coordinate
            )
        }
        
        return context
    }
    
    private func calculateUserSummary(from leaderboards: [LocationScope: [LeaderboardType: LeaderboardData]]) -> UserLeaderboardSummary {
        var bestRanking: BestRanking?
        var bestRankValue = Int.max
        
        for (scope, typeDict) in leaderboards {
            for (type, data) in typeDict {
                if let userRank = data.userRank, userRank < bestRankValue {
                    bestRankValue = userRank
                    bestRanking = BestRanking(
                        scope: scope,
                        type: type,
                        rank: userRank,
                        totalParticipants: data.totalParticipants,
                        location: data.entries.first?.location ?? scope.displayName,
                        artistName: data.entries.first?.artistName
                    )
                }
            }
        }
        
        let totalLeaderboards = leaderboards.values.reduce(0) { $0 + $1.count }
        
        return UserLeaderboardSummary(
            bestRanking: bestRanking,
            totalLeaderboards: totalLeaderboards
        )
    }
    
    private func loadTopArtist() {
        // Get user's most listened artist across all data
        let allUserData = dataStore.getLeaderboardData(
            scope: .global,
            type: .totalMinutes,
            context: LocationContext(building: nil, region: nil, coordinate: nil)
        )
        
        guard let currentUserData = allUserData.first(where: { $0.userId == "current-user" }) else {
            topArtist = "Taylor Swift" // Fallback
            return
        }
        
        topArtist = currentUserData.artistMinutes
            .max { $0.value < $1.value }?.key ?? "Taylor Swift"
    }
}

// MARK: - Supporting Types

private struct UserStats {
    let userId: String
    let username: String
    let profileImageURL: String?
    let minutes: Double
    let artistName: String?
}
