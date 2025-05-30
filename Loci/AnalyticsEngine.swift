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
    
    // MARK: - Building Analytics
    
    func getBuildingChart(for building: String, timeRange: TimeRange = .today) -> BuildingChart {
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
        var timePatterns = [Int: Double]() // Hour -> frequency
        
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
            timePatterns[hour, default: 0] += 1 / total
        }
        
        return ListeningFingerprint(
            id: UUID(),
            artistVector: createVector(from: artistFrequency),
            genreVector: createVector(from: genreFrequency),
            locationVector: createVector(from: locationFrequency),
            timeVector: createVector(from: timePatterns),
            diversityScore: calculateDiversity(artistFrequency),
            totalEvents: events.count
        )
    }
    
    // MARK: - Leaderboard Generation
    
    func generateLeaderboards(for building: String, timeRange: TimeRange) -> BuildingLeaderboards {
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
    
    private func filterEvents(building: String? = nil, timeRange: TimeRange) -> [ListeningEvent] {
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

struct ArtistRanking {
    let artistName: String
    var playCount: Int
    var uniqueTracks: Int
    var lastPlayed: Date
}

struct TrackRanking {
    let trackName: String
    let artistName: String
    var playCount: Int
    var lastPlayed: Date
}

struct GenreRanking {
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

struct ListeningFingerprint {
    let id: UUID
    let artistVector: [Double]
    let genreVector: [Double]
    let locationVector: [Double]
    let timeVector: [Double]
    let diversityScore: Double
    let totalEvents: Int
}

struct BuildingLeaderboards {
    let building: String
    let timeRange: TimeRange
    let topListeners: [ListenerRanking]
    let genreChampions: [GenreChampion]
    let lastUpdated: Date
}

struct ListenerRanking {
    let userId: String
    let playCount: Int
    let badge: String
}

struct GenreChampion {
    let genre: String
    let userId: String
    let playCount: Int
}

enum TimeRange: String {
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

enum TimeOfDay {
    case earlyMorning // 5-8
    case morning      // 8-12
    case afternoon    // 12-17
    case evening      // 17-22
    case lateNight    // 22-5
    
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
