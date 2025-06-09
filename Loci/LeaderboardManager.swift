import Foundation
import Combine
import CoreLocation
import FirebaseFirestore

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
    private let privacyManager = PrivacyManager.shared
    
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
                // Auto-sync user data if they've consented and aren't private
                await self?.autoSyncUserDataIfNeeded()
                await self?.loadLeaderboards(forceRefresh: true)
                self?.loadTopArtist()
            }
        }
        
        // Listen for privacy setting changes
        NotificationCenter.default.addObserver(
            forName: .leaderboardPrivacyUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let settings = notification.object as? LeaderboardPrivacySettings {
                    if settings.privacyLevel != .privateMode {
                        await self?.syncUserDataToFirebase()
                    } else {
                        await self?.removeUserDataFromFirebase()
                    }
                    await self?.loadLeaderboards(forceRefresh: true)
                }
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
        // Check if user has consented to leaderboards
        guard privacyManager.leaderboardPrivacySettings.hasGivenConsent,
              privacyManager.leaderboardPrivacySettings.privacyLevel != .privateMode else {
            return nil
        }
        
        // Check if user's privacy level includes this scope
        guard privacyManager.leaderboardPrivacySettings.privacyLevel.includesScope(scope) else {
            return nil
        }
        
        // Try to load real multi-user data from Firebase
        if let firebaseData = await loadFirebaseLeaderboardData(scope: scope, type: type, context: context, artistName: artistName) {
            return firebaseData
        }
        
        // Fallback to local data with demo users
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
                lastUpdated: Date(),
                isAnonymous: false // Local entries are not anonymous
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
        
        // Get sessions based on scope (be more permissive for building/regional)
        let sessions: [Session]
        switch scope {
        case .building:
            // For building scope, include all sessions for now
            // In production, filter by actual building location
            sessions = dataStore.sessionHistory
        case .region:
            // For regional scope, include all sessions for now  
            // In production, filter by actual regional boundaries
            sessions = dataStore.sessionHistory
        case .global:
            sessions = dataStore.sessionHistory
        }
        
        // Get imports based on scope (more permissive)
        let imports: [ImportBatch]
        switch scope {
        case .building:
            // For building leaderboards, include all imports if no building-specific ones exist
            let buildingImports = dataStore.importBatches.filter { $0.assignmentType == .building }
            imports = buildingImports.isEmpty ? dataStore.importBatches : buildingImports
        case .region:
            // For regional leaderboards, include all imports if no regional-specific ones exist
            let regionalImports = dataStore.importBatches.filter { $0.assignmentType == .region }
            imports = regionalImports.isEmpty ? dataStore.importBatches : regionalImports
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
        
        // Ensure current user always exists in the data, even with 0 minutes
        if userDataMap["current-user"] == nil {
            userDataMap["current-user"] = UserListeningData(
                userId: "current-user",
                username: "You",
                profileImageURL: nil,
                totalMinutes: 0,
                totalSongs: 0,
                artistMinutes: [:],
                artistSongs: [:],
                genreMinutes: [:],
                genreSongs: [:]
            )
        }
        
        // Only add demo users for global leaderboards
        if scope == .global, let currentUser = userDataMap["current-user"] {
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
        
        // Ensure we have some baseline data for demo users
        let baseMinutes = max(currentUser.totalMinutes, 45.0) // At least 45 minutes
        let baseSongs = max(currentUser.totalSongs, 15.0) // At least 15 songs
        
        // Create base artist data if user doesn't have much
        var baseArtistMinutes = currentUser.artistMinutes
        if baseArtistMinutes.isEmpty || baseArtistMinutes.values.max() ?? 0 < 15 {
            baseArtistMinutes = [
                "Taylor Swift": 25.0,
                "The Weeknd": 20.0,
                "Drake": 18.0,
                "Billie Eilish": 15.0,
                "Post Malone": 12.0
            ]
        }
        
        for (userId, username, multiplier) in demoUsers {
            let demoData = UserListeningData(
                userId: userId,
                username: username,
                profileImageURL: nil,
                totalMinutes: baseMinutes * multiplier,
                totalSongs: baseSongs * multiplier,
                artistMinutes: baseArtistMinutes.mapValues { $0 * multiplier },
                artistSongs: baseArtistMinutes.mapValues { $0 * multiplier / 3.5 }, // Rough songs per minute conversion
                genreMinutes: currentUser.genreMinutes.isEmpty ? 
                    ["Pop": baseMinutes * multiplier * 0.4, "Hip-Hop": baseMinutes * multiplier * 0.3, "Electronic": baseMinutes * multiplier * 0.3] :
                    currentUser.genreMinutes.mapValues { $0 * multiplier },
                genreSongs: currentUser.genreSongs.isEmpty ?
                    ["Pop": baseSongs * multiplier * 0.4, "Hip-Hop": baseSongs * multiplier * 0.3, "Electronic": baseSongs * multiplier * 0.3] :
                    currentUser.genreSongs.mapValues { $0 * multiplier }
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
            // Use ReverseGeocoding to get actual location data
            let buildingInfo = await ReverseGeocoding.shared.reverseGeocodeAsync(location: location)
            
            context = LocationContext(
                building: buildingInfo?.name,
                region: buildingInfo?.city ?? buildingInfo?.neighborhood ?? "Your Area",
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
    
    // MARK: - Firebase Integration
    
    func syncUserDataToFirebase() async {
        guard privacyManager.leaderboardPrivacySettings.hasGivenConsent,
              privacyManager.leaderboardPrivacySettings.privacyLevel != .privateMode,
              let currentUser = firebaseManager.currentUser else {
            return
        }
        
        let settings = privacyManager.leaderboardPrivacySettings
        let locationContext = await getCurrentLocationContext()
        let userData = aggregateUserData()
        
        let firebaseEntry = FirebaseLeaderboardEntry(
            userId: currentUser.id,
            username: settings.privacyLevel.showsRealName ? currentUser.username : "Anonymous User",
            profileImageURL: settings.privacyLevel.showsRealName ? currentUser.profileImageURL : nil,
            totalMinutes: settings.shareTotalTime ? userData.totalMinutes : 0,
            artistMinutes: settings.shareArtistData ? userData.artistMinutes : [:],
            location: locationContext.region ?? "Unknown",
            isAnonymous: !settings.privacyLevel.showsRealName,
            lastUpdated: Date(),
            building: locationContext.building,
            region: locationContext.region,
            coordinate: locationContext.coordinate.map { ["lat": $0.latitude, "lng": $0.longitude] }
        )
        
        // Upload to different scopes based on privacy settings
        for scope in LocationScope.allCases {
            guard settings.privacyLevel.includesScope(scope) else { continue }
            
            let path = getFirebasePath(for: scope, context: locationContext)
            await setLeaderboardDocument(path: "\(path)/\(currentUser.id)", data: firebaseEntry)
        }
        
        print("✅ Synced user data to Firebase leaderboards")
        
        // Show success notification to user
        NotificationManager.shared.showLeaderboardSyncNotification(
            privacyLevel: settings.privacyLevel,
            scopes: LocationScope.allCases.filter { settings.privacyLevel.includesScope($0) }
        )
    }
    
    func removeUserDataFromFirebase() async {
        guard let currentUser = firebaseManager.currentUser else { return }
        
        let locationContext = await getCurrentLocationContext()
        
        // Remove from all scopes
        for scope in LocationScope.allCases {
            let path = getFirebasePath(for: scope, context: locationContext)
            await deleteLeaderboardDocument(path: "\(path)/\(currentUser.id)")
        }
        
        print("✅ Removed user data from Firebase leaderboards")
    }
    
    private func loadFirebaseLeaderboardData(scope: LocationScope, type: LeaderboardType, context: LocationContext, artistName: String?) async -> LeaderboardData? {
        let path = getFirebasePath(for: scope, context: context)
        
        do {
            let entries = try await getLeaderboardCollection(path: path)
            let leaderboardEntries = processFirebaseEntries(entries, type: type, artistName: artistName, scope: scope, context: context)
            
            guard !leaderboardEntries.isEmpty else { return nil }
            
            let currentUserId = firebaseManager.currentUser?.id ?? "current-user"
            let userRank = leaderboardEntries.firstIndex { $0.userId == currentUserId }.map { $0 + 1 }
            let userEntry = leaderboardEntries.first { $0.userId == currentUserId }
            
            return LeaderboardData(
                id: "\(scope.rawValue)-\(type.rawValue)",
                scope: scope,
                type: type,
                entries: Array(leaderboardEntries.prefix(20)),
                userRank: userRank,
                userEntry: userEntry,
                totalParticipants: leaderboardEntries.count,
                lastUpdated: Date()
            )
        } catch {
            // Silently return nil for permissions errors - we'll fall back to local data
            if error.localizedDescription.contains("permissions") {
                print("ℹ️ Firebase leaderboards not configured yet - using local data for \(scope.displayName)")
            } else {
                print("❌ Failed to load Firebase leaderboard data: \(error)")
            }
            return nil
        }
    }
    
    private func processFirebaseEntries(_ entries: [FirebaseLeaderboardEntry], type: LeaderboardType, artistName: String?, scope: LocationScope, context: LocationContext) -> [LeaderboardEntry] {
        let filteredEntries: [LeaderboardEntry] = entries.compactMap { firebaseEntry in
            let minutes: Double
            
            switch type {
            case .totalMinutes:
                minutes = firebaseEntry.totalMinutes
            case .artistMinutes:
                guard let artist = artistName else { return nil }
                minutes = firebaseEntry.artistMinutes[artist] ?? 0
                if minutes == 0 { return nil }
            }
            
            return LeaderboardEntry(
                id: firebaseEntry.userId,
                userId: firebaseEntry.userId,
                username: firebaseEntry.username,
                profileImageURL: firebaseEntry.profileImageURL,
                rank: 0, // Will be set after sorting
                minutes: minutes,
                artistName: artistName,
                location: firebaseEntry.location,
                lastUpdated: firebaseEntry.lastUpdated,
                isAnonymous: firebaseEntry.isAnonymous
            )
        }
        
        // Sort by minutes and assign ranks
        let sortedEntries = filteredEntries.sorted { $0.minutes > $1.minutes }
        return sortedEntries.enumerated().map { index, entry in
            LeaderboardEntry(
                id: entry.id,
                userId: entry.userId,
                username: entry.username,
                profileImageURL: entry.profileImageURL,
                rank: index + 1,
                minutes: entry.minutes,
                artistName: entry.artistName,
                location: entry.location,
                lastUpdated: entry.lastUpdated,
                isAnonymous: entry.isAnonymous
            )
        }
    }
    
    private func getFirebasePath(for scope: LocationScope, context: LocationContext) -> String {
        switch scope {
        case .building:
            if let building = context.building {
                return "leaderboards/building/\(building.replacingOccurrences(of: " ", with: "_").lowercased())"
            } else {
                return "leaderboards/building/unknown"
            }
        case .region:
            if let region = context.region {
                return "leaderboards/region/\(region.replacingOccurrences(of: " ", with: "_").lowercased())"
            } else {
                return "leaderboards/region/unknown"
            }
        case .global:
            return "leaderboards/global/all"
        }
    }
    
    private func aggregateUserData() -> UserListeningData {
        var userData = UserListeningData(
            userId: "current-user",
            username: "You",
            profileImageURL: nil,
            totalMinutes: 0,
            totalSongs: 0,
            artistMinutes: [:],
            artistSongs: [:],
            genreMinutes: [:],
            genreSongs: [:]
        )
        
        // Add session data
        for session in dataStore.sessionHistory {
            userData.addSession(session)
        }
        
        // Add import data
        for importBatch in dataStore.importBatches {
            userData.addImportBatch(importBatch)
        }
        
        return userData
    }
    
    // MARK: - Firebase Helper Methods
    
    private func setLeaderboardDocument(path: String, data: FirebaseLeaderboardEntry) async {
        do {
            let db = Firestore.firestore()
            let encodedData = try Firestore.Encoder().encode(data)
            try await db.document(path).setData(encodedData)
        } catch {
            print("❌ Failed to set leaderboard document at \(path): \(error)")
        }
    }
    
    private func deleteLeaderboardDocument(path: String) async {
        do {
            let db = Firestore.firestore()
            try await db.document(path).delete()
        } catch {
            print("❌ Failed to delete leaderboard document at \(path): \(error)")
        }
    }
    
    private func getLeaderboardCollection(path: String) async throws -> [FirebaseLeaderboardEntry] {
        let db = Firestore.firestore()
        let collection = db.collection(path)
        let snapshot = try await collection.getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try Firestore.Decoder().decode(FirebaseLeaderboardEntry.self, from: document.data())
        }
    }
    
    // MARK: - Auto-Sync
    
    func autoSyncUserDataIfNeeded() async {
        let settings = privacyManager.leaderboardPrivacySettings
        
        // Only auto-sync if user has consented and isn't private
        guard settings.hasGivenConsent,
              settings.privacyLevel != .privateMode else {
            return
        }
        
        // Auto-sync to Firebase
        await syncUserDataToFirebase()
        print("🔄 Auto-synced user data to Firebase leaderboards")
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
