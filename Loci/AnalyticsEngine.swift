import Foundation
import CoreLocation
import Combine

class AnalyticsEngine: ObservableObject {
    static let shared = AnalyticsEngine()
    
    // MARK: - Published Properties
    @Published var globalHeatmap: [LocationCluster: LocationMetrics] = [:]
    @Published var buildingCharts: [String: BuildingChart] = [:]
    @Published var genreDistribution: [String: GenreMetrics] = [:]
    
    private let dataStore = DataStore.shared
    private let locationClustering = LocationClusteringService()
    
    // Cache for expensive computations
    private var analyticsCache = AnalyticsCache()
    
    private init() {}
    
    // MARK: - Real-time Analytics
    
    func processNewEvent(_ event: ListeningEvent) {
        // Update building-specific metrics
        updateBuildingMetrics(for: event)
        
        // Update genre distribution
        updateGenreMetrics(for: event)
        
        // Update location clustering
        updateLocationClusters(for: event)
        
        // Update time-based patterns
        updateTimePatterns(for: event)
    }
    
    // MARK: - Session Analytics
        
    func generateSessionAnalytics(for events: [ListeningEvent]) -> SessionAnalytics {
        guard !events.isEmpty else {
            return SessionAnalytics(
                sessionId: UUID(),
                mode: .unknown,
                totalTracks: 0,
                uniqueTracks: 0,
                uniqueArtists: 0,
                uniqueLocations: 0,
                totalDuration: 0,
                topArtist: nil,
                topTrack: nil,
                topGenre: nil,
                locationBreakdown: [:],
                genreDistribution: [:],
                timeDistribution: TimeDistribution(morning: 0, afternoon: 0, evening: 0, lateNight: 0),
                diversityScore: 0
            )
        }
        
        // Basic counts
        let uniqueTracks = Set(events.map { $0.trackName }).count
        let uniqueArtists = Set(events.map { $0.artistName }).count
        let uniqueLocations = Set(events.compactMap { $0.buildingName }).count
        
        // Duration calculation (90 seconds per event)
        let totalDuration = events.count * 90
        
        // Top items
        let artistCounts = Dictionary(grouping: events) { $0.artistName }
            .mapValues { $0.count }
        let topArtist = artistCounts.max { $0.value < $1.value }?.key
        
        let trackCounts = Dictionary(grouping: events) { $0.trackName }
            .mapValues { $0.count }
        let topTrack = trackCounts.max { $0.value < $1.value }?.key
        
        let genreCounts = Dictionary(grouping: events.compactMap { $0.genre }) { $0 }
            .mapValues { $0.count }
        let topGenre = genreCounts.max { $0.value < $1.value }?.key
        
        // Location breakdown
        let locationBreakdown = Dictionary(grouping: events) { $0.buildingName ?? "Unknown" }
            .mapValues { events in
                LocationStats(
                    totalPlays: events.count,
                    uniqueTracks: Set(events.map { $0.trackName }).count,
                    topArtist: Dictionary(grouping: events) { $0.artistName }
                        .max { $0.value.count < $1.value.count }?.key,
                    timeSpent: events.count * 90
                )
            }
        
        // Genre distribution (percentages)
        let totalGenreEvents = events.compactMap { $0.genre }.count
        let genreDistribution = genreCounts.mapValues { count in
            Double(count) / Double(totalGenreEvents)
        }
        
        // Time distribution
        let timeDistribution = calculateTimeDistribution(from: events)
        
        // Diversity score (0-1, based on Shannon entropy)
        let diversityScore = calculateSessionDiversity(
            tracks: trackCounts,
            artists: artistCounts,
            genres: genreCounts
        )
        
        return SessionAnalytics(
            sessionId: UUID(),
            mode: .unknown,
            totalTracks: events.count,
            uniqueTracks: uniqueTracks,
            uniqueArtists: uniqueArtists,
            uniqueLocations: uniqueLocations,
            totalDuration: totalDuration,
            topArtist: topArtist,
            topTrack: topTrack,
            topGenre: topGenre,
            locationBreakdown: locationBreakdown,
            genreDistribution: genreDistribution,
            timeDistribution: timeDistribution,
            diversityScore: diversityScore
        )
    }
    
    // MARK: - Building Analytics
    
    @MainActor func getBuildingChart(for building: String, timeRange: TimeRange = .today) -> BuildingChart {
        let cacheKey = "\(building)-\(timeRange.rawValue)"
        
        if let cached = analyticsCache.getChart(key: cacheKey) {
            return cached
        }
        
        // Calculate fresh data
        let events = filterEvents(building: building, timeRange: timeRange)
        let chart = generateBuildingChart(building: building, events: events)
        
        analyticsCache.storeChart(chart, key: cacheKey)
        return chart
    }
    private func generateBuildingChart(building: String, events: [ListeningEvent]) -> BuildingChart {
        // PLACEHOLDER TO DO!!
        return BuildingChart(
            buildingName: building,
            lastUpdated: Date(),
            topArtists: [],
            topTracks: [],
            topGenres: [],
            totalListeners: 0,
            totalPlays: events.count,
            peakHours: []
        )
    }
    
    private func updateBuildingMetrics(for event: ListeningEvent) {
        guard let building = event.buildingName else { return }
        
        var chart = buildingCharts[building] ?? BuildingChart(
            buildingName: building,
            lastUpdated: Date(),
            topArtists: [],
            topTracks: [],
            topGenres: [],
            totalListeners: 0,
            totalPlays: 0,
            peakHours: []
        )
        
        // Update play count
        chart.totalPlays += 1
        chart.lastUpdated = Date()
        
        // Update track rankings
        chart.addTrack(TrackRanking(
            trackName: event.trackName,
            artistName: event.artistName,
            playCount: 1,
            lastPlayed: event.timestamp
        ))
        
        // Update artist rankings
        chart.addArtist(ArtistRanking(
            artistName: event.artistName,
            playCount: 1,
            uniqueTracks: 1,
            lastPlayed: event.timestamp
        ))
        
        buildingCharts[building] = chart
    }
    @MainActor func generateBuildingStats(for building: String, timeRange: TimeRange = .today) -> BuildingStats {
        let events = filterEvents(building: building, timeRange: timeRange)
        
        // User activity
        let activeUsers = Set(events.map { _ in "Anonymous" }).count // In production, use actual user IDs
        
        // Track variety
        let uniqueTracks = Set(events.map { $0.trackName }).count
        let uniqueArtists = Set(events.map { $0.artistName }).count
        
        // Genre breakdown
        let genreBreakdown = Dictionary(grouping: events.compactMap { $0.genre }) { $0 }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { GenreCount(genre: $0.key, count: $0.value) }
        
        // Hourly activity
        let hourlyActivity = Dictionary(grouping: events) { event in
            Calendar.current.component(.hour, from: event.timestamp)
        }.mapValues { $0.count }
        
        // Peak hours (top 3)
        let peakHours = hourlyActivity
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        
        // Recent trend (compare to previous period)
        let previousPeriodEvents = filterEvents(
            building: building,
            timeRange: previousTimeRange(for: timeRange)
        )
        let growthRate = calculateGrowthRate(
            current: events.count,
            previous: previousPeriodEvents.count
        )
        
        return BuildingStats(
            buildingName: building,
            timeRange: timeRange,
            totalPlays: events.count,
            activeUsers: activeUsers,
            uniqueTracks: uniqueTracks,
            uniqueArtists: uniqueArtists,
            genreBreakdown: genreBreakdown,
            hourlyActivity: hourlyActivity,
            peakHours: peakHours,
            growthRate: growthRate,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Trend Detection

    @MainActor func detectTrends(timeRange: TimeRange = .today) -> TrendReport {
        let currentEvents = filterEvents(timeRange: timeRange)
        let previousEvents = filterEvents(timeRange: previousTimeRange(for: timeRange))
        
        // Rising artists
        let risingArtists = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.artistName },
            previous: Dictionary(grouping: previousEvents) { $0.artistName }
        ).map { artist, growth in
            TrendingItem(
                name: artist,
                type: .artist,
                growthRate: growth,
                playCount: currentEvents.filter { $0.artistName == artist }.count,
                rank: 0 // Will be set after sorting
            )
        }
        
        // Rising tracks
        let risingTracks = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.trackName },
            previous: Dictionary(grouping: previousEvents) { $0.trackName }
        ).map { track, growth in
            TrendingItem(
                name: track,
                type: .track,
                growthRate: growth,
                playCount: currentEvents.filter { $0.trackName == track }.count,
                rank: 0
            )
        }
        
        // Rising genres
        let risingGenres = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.genre ?? "Unknown" },
            previous: Dictionary(grouping: previousEvents) { $0.genre ?? "Unknown" }
        ).map { genre, growth in
            TrendingItem(
                name: genre,
                type: .genre,
                growthRate: growth,
                playCount: currentEvents.filter { $0.genre == genre }.count,
                rank: 0
            )
        }
        
        // Hot locations
        let hotLocations = Dictionary(grouping: currentEvents) { $0.buildingName ?? "Unknown" }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .enumerated()
            .map { index, location in
                HotLocation(
                    buildingName: location.key,
                    activityLevel: Double(location.value) / Double(currentEvents.count),
                    uniqueListeners: 1, // Placeholder
                    rank: index + 1
                )
            }
        
        return TrendReport(
            timeRange: timeRange,
            generatedAt: Date(),
            risingArtists: Array(risingArtists.sorted { $0.growthRate > $1.growthRate }.prefix(10)),
            risingTracks: Array(risingTracks.sorted { $0.growthRate > $1.growthRate }.prefix(10)),
            risingGenres: Array(risingGenres.sorted { $0.growthRate > $1.growthRate }.prefix(5)),
            hotLocations: Array(hotLocations)
        )
    }

    // MARK: - Helper Methods for Analytics

    private func calculateTimeDistribution(from events: [ListeningEvent]) -> TimeDistribution {
        let calendar = Calendar.current
        
        var morning = 0     // 6-12
        var afternoon = 0   // 12-18
        var evening = 0     // 18-24
        var lateNight = 0   // 0-6
        
        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            switch hour {
            case 6..<12: morning += 1
            case 12..<18: afternoon += 1
            case 18..<24: evening += 1
            default: lateNight += 1
            }
        }
        
        let total = Double(events.count)
        return TimeDistribution(
            morning: total > 0 ? Double(morning) / total : 0,
            afternoon: total > 0 ? Double(afternoon) / total : 0,
            evening: total > 0 ? Double(evening) / total : 0,
            lateNight: total > 0 ? Double(lateNight) / total : 0
        )
    }

    private func calculateSessionDiversity(tracks: [String: Int], artists: [String: Int], genres: [String: Int]) -> Double {
        // Weighted diversity score
        let trackDiversity = calculateShannonDiversity(tracks)
        let artistDiversity = calculateShannonDiversity(artists)
        let genreDiversity = calculateShannonDiversity(genres)
        
        // Weighted average (tracks matter most for diversity)
        return (trackDiversity * 0.5) + (artistDiversity * 0.3) + (genreDiversity * 0.2)
    }

    private func calculateShannonDiversity(_ counts: [String: Int]) -> Double {
        guard !counts.isEmpty else { return 0 }
        
        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return 0 }
        
        let entropy = counts.values.reduce(0.0) { sum, count in
            let p = Double(count) / total
            return sum - (p * log2(p))
        }
        
        // Normalize to 0-1 range
        let maxEntropy = log2(Double(counts.count))
        return maxEntropy > 0 ? entropy / maxEntropy : 0
    }

    private func findRisingItems(current: [String: [ListeningEvent]], previous: [String: [ListeningEvent]]) -> [(String, Double)] {
        var risingItems: [(String, Double)] = []
        
        for (item, currentEvents) in current {
            let currentCount = currentEvents.count
            let previousCount = previous[item]?.count ?? 0
            
            // Calculate growth rate
            let growth = calculateGrowthRate(current: currentCount, previous: previousCount)
            
            // Only include items with positive growth and minimum threshold
            if growth > 0 && currentCount >= 3 {
                risingItems.append((item, growth))
            }
        }
        
        return risingItems.sorted { $0.1 > $1.1 }
    }

    private func calculateGrowthRate(current: Int, previous: Int) -> Double {
        guard previous > 0 else {
            return current > 0 ? 1.0 : 0.0
        }
        return Double(current - previous) / Double(previous)
    }

    private func previousTimeRange(for timeRange: TimeRange) -> TimeRange {
        // For trend comparison - this is simplified
        switch timeRange {
        case .today: return .today // Would be yesterday in production
        case .thisWeek: return .thisWeek // Would be last week
        case .thisMonth: return .thisMonth // Would be last month
        case .allTime: return .allTime
        }
    }

    
    // MARK: - Location Clustering
    
    private func updateLocationClusters(for event: ListeningEvent) {
        let location = CLLocation(latitude: event.latitude, longitude: event.longitude)
        let cluster = locationClustering.findOrCreateCluster(for: location)
        
        var metrics = globalHeatmap[cluster] ?? LocationMetrics(
            cluster: cluster,
            totalPlays: 0,
            uniqueListeners: Set(),
            dominantGenre: nil,
            activityLevel: 0
        )
        
        metrics.totalPlays += 1
        metrics.lastActivity = Date()
        
        // Update activity level (0-1 scale based on recent activity)
        metrics.activityLevel = calculateActivityLevel(for: metrics)
        
        globalHeatmap[cluster] = metrics
    }
    
    // MARK: - Genre Analytics
    
    private func updateGenreMetrics(for event: ListeningEvent) {
        guard let genre = event.genre else { return }
        
        var metrics = genreDistribution[genre] ?? GenreMetrics(
            genre: genre,
            totalPlays: 0,
            uniqueLocations: Set(),
            peakHours: [],
            growthRate: 0
        )
        
        metrics.totalPlays += 1
        if let building = event.buildingName {
            metrics.uniqueLocations.insert(building)
        }
        
        // Update hourly distribution
        let hour = Calendar.current.component(.hour, from: event.timestamp)
        metrics.hourlyDistribution[hour, default: 0] += 1
        
        genreDistribution[genre] = metrics
    }
    
    // MARK: - Time Pattern Analysis
    
    func analyzeTimePatterns(for events: [ListeningEvent]) -> TimePatternAnalysis {
        var hourlyActivity = [Int: Int]()
        var weekdayActivity = [Int: Int]()
        var genreByTimeOfDay = [TimeOfDay: [String: Int]]()
        
        for event in events {
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            let weekday = Calendar.current.component(.weekday, from: event.timestamp)
            
            hourlyActivity[hour, default: 0] += 1
            weekdayActivity[weekday, default: 0] += 1
            
            let timeOfDay = TimeOfDay.from(hour: hour)
            if let genre = event.genre {
                genreByTimeOfDay[timeOfDay, default: [:]][genre, default: 0] += 1
            }
        }
        
        return TimePatternAnalysis(
            peakHours: findPeakHours(from: hourlyActivity),
            quietHours: findQuietHours(from: hourlyActivity),
            busiestDays: findBusiestDays(from: weekdayActivity),
            genreTimePreferences: analyzeGenreTimePreferences(from: genreByTimeOfDay)
        )
    }
    
    // MARK: - Matching Preparation
    
    func generateListeningFingerprint(for events: [ListeningEvent]) -> ListeningFingerprint {
        // Create a unique fingerprint for matching users
        var artistFrequency = [String: Double]()
        var genreFrequency = [String: Double]()
        var locationFrequency = [String: Double]()
        var timePatterns = [String: Double]()
        
        let total = Double(events.count)
        
        for event in events {
            artistFrequency[event.artistName, default: 0] += 1 / total
            if let genre = event.genre {
                genreFrequency[genre, default: 0] += 1 / total
            }
            if let building = event.buildingName {
                locationFrequency[building, default: 0] += 1 / total
            }
            
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            let hourString = String(hour)
            timePatterns[hourString, default: 0] += 1 / total
        }
        
        return ListeningFingerprint(
            id: UUID(),
            artistVector: createVector(from: artistFrequency),
            genreVector: createVector(from: genreFrequency),
            locationVector: createVector(from: locationFrequency),
            timeVector: createVector(from: timePatterns),
            diversityScore: calculateDiversity(artistFrequency),
            totalEvents: events.count,
            createdAt: Date()
        )
    }
    
    // MARK: - Leaderboard Generation
    
    @MainActor func generateLeaderboards(for building: String, timeRange: TimeRange) -> BuildingLeaderboards {
        let events = filterEvents(building: building, timeRange: timeRange)
        
        // Most active listeners (by play count)
        let listenerActivity = Dictionary(grouping: events) { event in
            // In production, this would be user ID
            "Anonymous_\(event.id.uuidString.prefix(8))"
        }.mapValues { $0.count }
        
        let topListeners = listenerActivity.sorted { $0.value > $1.value }
            .prefix(10)
            .map { ListenerRanking(userId: $0.key, playCount: $0.value, badge: getBadge(for: $0.value)) }
        
        // Genre champions
        let genreChampions = Dictionary(grouping: events) { $0.genre ?? "Unknown" }
            .mapValues { events in
                Dictionary(grouping: events) { _ in "Anonymous" }.mapValues { $0.count }
            }
            .compactMap { genre, listeners in
                listeners.max { $0.value < $1.value }.map { listener in
                    GenreChampion(genre: genre, userId: listener.key, playCount: listener.value)
                }
            }
        
        return BuildingLeaderboards(
            building: building,
            timeRange: timeRange,
            topListeners: topListeners,
            genreChampions: genreChampions,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Helper Methods
    
    @MainActor private func filterEvents(building: String? = nil, timeRange: TimeRange) -> [ListeningEvent] {
        let cutoffDate = timeRange.startDate
        
        return dataStore.currentSessionEvents.filter { event in
            if let building = building, event.buildingName != building {
                return false
            }
            return event.timestamp >= cutoffDate
        }
    }
    
    private func calculateActivityLevel(for metrics: LocationMetrics) -> Double {
        guard let lastActivity = metrics.lastActivity else { return 0 }
        
        let hoursSinceLastActivity = Date().timeIntervalSince(lastActivity) / 3600
        let recencyScore = max(0, 1 - (hoursSinceLastActivity / 24)) // Decay over 24 hours
        
        let frequencyScore = min(1, Double(metrics.totalPlays) / 100) // Normalize to 100 plays
        
        return (recencyScore * 0.7) + (frequencyScore * 0.3)
    }
    
    private func createVector(from frequency: [String: Double]) -> [Double] {
        // In production, this would create consistent vectors for ML matching
        return Array(frequency.values.sorted())
    }
    
    private func calculateDiversity(_ frequency: [String: Double]) -> Double {
        // Shannon entropy for diversity score
        let total = frequency.values.reduce(0, +)
        guard total > 0 else { return 0 }
        
        let entropy = frequency.values.reduce(0) { sum, count in
            let p = count / total
            return sum - (p * log2(p))
        }
        
        return entropy / log2(Double(frequency.count)) // Normalize to 0-1
    }
    
    private func getBadge(for playCount: Int) -> String {
        switch playCount {
        case 0..<10: return "🎵"
        case 10..<50: return "🎸"
        case 50..<100: return "🎹"
        case 100..<500: return "🎼"
        default: return "🏆"
        }
    }
    
    private func findPeakHours(from hourly: [Int: Int]) -> [Int] {
        let sorted = hourly.sorted { $0.value > $1.value }
        return Array(sorted.prefix(3).map { $0.key })
    }
    
    private func findQuietHours(from hourly: [Int: Int]) -> [Int] {
        let sorted = hourly.sorted { $0.value < $1.value }
        return Array(sorted.prefix(3).map { $0.key })
    }
    
    private func findBusiestDays(from weekday: [Int: Int]) -> [String] {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = weekday.sorted { $0.value > $1.value }
        return sorted.prefix(3).compactMap { day in
            guard day.key - 1 < dayNames.count else { return nil }
            return dayNames[day.key - 1]
        }
    }
    
    private func analyzeGenreTimePreferences(from data: [TimeOfDay: [String: Int]]) -> [String: TimeOfDay] {
        var genrePreferences: [String: TimeOfDay] = [:]
        
        // Find dominant time of day for each genre
        var genreTotals: [String: [TimeOfDay: Int]] = [:]
        
        for (timeOfDay, genres) in data {
            for (genre, count) in genres {
                genreTotals[genre, default: [:]][timeOfDay, default: 0] += count
            }
        }
        
        for (genre, timeData) in genreTotals {
            if let dominantTime = timeData.max(by: { $0.value < $1.value })?.key {
                genrePreferences[genre] = dominantTime
            }
        }
        
        return genrePreferences
    }
    
    private func updateTimePatterns(for event: ListeningEvent) {
        // Additional time-based pattern tracking
        let hour = Calendar.current.component(.hour, from: event.timestamp)
        let dayOfWeek = Calendar.current.component(.weekday, from: event.timestamp)
        
        // Store patterns for later analysis
        // This would be expanded in production
    }
}

// MARK: - Analytics Cache

private class AnalyticsCache {
    private var chartCache: [String: (chart: BuildingChart, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    func getChart(key: String) -> BuildingChart? {
        guard let cached = chartCache[key] else { return nil }
        
        if Date().timeIntervalSince(cached.timestamp) > cacheExpiration {
            chartCache.removeValue(forKey: key)
            return nil
        }
        
        return cached.chart
    }
    
    func storeChart(_ chart: BuildingChart, key: String) {
        chartCache[key] = (chart, Date())
    }
}

// MARK: - Supporting Types

struct BuildingChart {
    let buildingName: String
    var lastUpdated: Date
    var topArtists: [ArtistRanking]
    var topTracks: [TrackRanking]
    var topGenres: [GenreRanking]
    var totalListeners: Int
    var totalPlays: Int
    var peakHours: [Int]
    
    mutating func addTrack(_ ranking: TrackRanking) {
        if let index = topTracks.firstIndex(where: { $0.trackName == ranking.trackName }) {
            topTracks[index].playCount += ranking.playCount
        } else {
            topTracks.append(ranking)
        }
        topTracks.sort { $0.playCount > $1.playCount }
        topTracks = Array(topTracks.prefix(50))
    }
    
    mutating func addArtist(_ ranking: ArtistRanking) {
        if let index = topArtists.firstIndex(where: { $0.artistName == ranking.artistName }) {
            topArtists[index].playCount += ranking.playCount
        } else {
            topArtists.append(ranking)
        }
        topArtists.sort { $0.playCount > $1.playCount }
        topArtists = Array(topArtists.prefix(50))
    }
}

struct ArtistRanking: Codable {
    let artistName: String
    var playCount: Int
    var uniqueTracks: Int
    var lastPlayed: Date
}

struct TrackRanking: Codable {
    let trackName: String
    let artistName: String
    var playCount: Int
    var lastPlayed: Date
}

struct GenreRanking: Codable {
    let genre: String
    var playCount: Int
    var percentage: Double
}

struct LocationMetrics {
    let cluster: LocationCluster
    var totalPlays: Int
    var uniqueListeners: Set<String>
    var dominantGenre: String?
    var activityLevel: Double
    var lastActivity: Date?
}

struct GenreMetrics {
    let genre: String
    var totalPlays: Int
    var uniqueLocations: Set<String>
    var peakHours: [Int]
    var growthRate: Double
    var hourlyDistribution: [Int: Int] = [:]
}

struct TimePatternAnalysis {
    let peakHours: [Int]
    let quietHours: [Int]
    let busiestDays: [String]
    let genreTimePreferences: [String: TimeOfDay]
}



struct BuildingLeaderboards {
    let building: String
    let timeRange: TimeRange
    let topListeners: [ListenerRanking]
    let genreChampions: [GenreChampion]
    let lastUpdated: Date
}

struct ListenerRanking: Codable {
    let userId: String
    let playCount: Int
    let badge: String
}

struct GenreChampion: Codable {
    let genre: String
    let userId: String
    let playCount: Int
}




// MARK: - New Supporting Types (add these to the bottom of AnalyticsEngine.swift)

struct SessionAnalytics {
    let sessionId: UUID
    let mode: SessionMode // Track which mode was used
    let totalTracks: Int
    let uniqueTracks: Int
    let uniqueArtists: Int
    let uniqueLocations: Int
    let totalDuration: Int // seconds
    let topArtist: String?
    let topTrack: String?
    let topGenre: String?
    let locationBreakdown: [String: LocationStats]
    let genreDistribution: [String: Double] // percentages
    let timeDistribution: TimeDistribution
    let diversityScore: Double // 0-1
}

struct LocationStats {
    let totalPlays: Int
    let uniqueTracks: Int
    let topArtist: String?
    let timeSpent: Int // seconds
}

struct TimeDistribution {
    let morning: Double    // 6-12
    let afternoon: Double  // 12-18
    let evening: Double    // 18-24
    let lateNight: Double  // 0-6
}

struct BuildingStats {
    let buildingName: String
    let timeRange: TimeRange
    let totalPlays: Int
    let activeUsers: Int
    let uniqueTracks: Int
    let uniqueArtists: Int
    let genreBreakdown: [GenreCount]
    let hourlyActivity: [Int: Int]
    let peakHours: [Int]
    let growthRate: Double
    let lastUpdated: Date
}

struct GenreCount {
    let genre: String
    let count: Int
}

struct TrendReport: Codable {
    let timeRange: TimeRange
    let generatedAt: Date
    let risingArtists: [TrendingItem]
    let risingTracks: [TrendingItem]
    let risingGenres: [TrendingItem]
    let hotLocations: [HotLocation]
}

struct TrendingItem: Codable {
    let name: String
    let type: TrendType
    let growthRate: Double
    let playCount: Int
    let rank: Int
}

enum TrendType: String, Codable {
    case artist, track, genre
}

struct HotLocation: Codable {
    let buildingName: String
    let activityLevel: Double
    let uniqueListeners: Int
    let rank: Int
}
