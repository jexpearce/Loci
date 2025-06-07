import Foundation
import CoreLocation
import Combine

class AnalyticsEngine: ObservableObject {
    static let shared = AnalyticsEngine()
    
    // MARK: - Published Properties
    @Published var globalHeatmap: [LocationCluster: LocationMetrics] = [:]
    @Published var buildingCharts: [String: BuildingChart] = [:]
    @Published var genreDistribution: [String: GenreMetrics] = [:]
    @Published var sessionModeAnalytics: SessionModeAnalytics = SessionModeAnalytics()
    
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
        
        // Update session mode analytics
        updateSessionModeAnalytics(for: event)
        
        // Update time-based patterns
        updateTimePatterns(for: event)
    }
    
    // MARK: - Session Mode Analytics (New)
    
    @MainActor func generateSessionModeComparison() -> SessionModeComparison {
        let sessions = dataStore.sessionHistory
        
        let onePlaceSessions = sessions.filter { $0.mode == .onePlace }
        let onTheMoveSessions = sessions.filter { $0.mode == .onTheMove }
        
        let onePlaceStats = generateModeStatistics(sessions: onePlaceSessions, mode: .onePlace)
        let onTheMoveStats = generateModeStatistics(sessions: onTheMoveSessions, mode: .onTheMove)
        
        return SessionModeComparison(
            onePlace: onePlaceStats,
            onTheMove: onTheMoveStats,
            totalSessions: sessions.count,
            generatedAt: Date()
        )
    }
    
    private func generateModeStatistics(sessions: [Session], mode: SessionMode) -> ModeStatistics {
        guard !sessions.isEmpty else {
            return ModeStatistics(
                mode: mode,
                totalSessions: 0,
                totalEvents: 0,
                averageDuration: 0,
                uniqueBuildings: 0,
                topBuildings: [],
                averageTracksPerSession: 0,
                buildingChanges: 0,
                batteryEfficiencyScore: 0
            )
        }
        
        let totalEvents = sessions.reduce(0) { $0 + $1.events.count }
        let totalDuration = sessions.reduce(0) { total, session in
            total + session.endTime.timeIntervalSince(session.startTime)
        }
        
        let allBuildings = sessions.flatMap { session in
            session.events.compactMap { $0.buildingName } +
            session.buildingChanges.map { $0.toBuildingName }
        }
        
        let uniqueBuildings = Set(allBuildings).count
        let buildingCounts = Dictionary(grouping: allBuildings) { $0 }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        let topBuildings = buildingCounts.prefix(5).map { building, count in
            BuildingRanking(name: building, visitCount: count, sessionCount: 0)
        }
        
        let totalBuildingChanges = sessions.reduce(0) { $0 + $1.buildingChanges.count }
        
        // Battery efficiency score (0-100)
        let batteryScore = calculateBatteryEfficiency(mode: mode, sessions: sessions)
        
        return ModeStatistics(
            mode: mode,
            totalSessions: sessions.count,
            totalEvents: totalEvents,
            averageDuration: totalDuration / Double(sessions.count),
            uniqueBuildings: uniqueBuildings,
            topBuildings: topBuildings,
            averageTracksPerSession: Double(totalEvents) / Double(sessions.count),
            buildingChanges: totalBuildingChanges,
            batteryEfficiencyScore: batteryScore
        )
    }
    
    private func calculateBatteryEfficiency(mode: SessionMode, sessions: [Session]) -> Double {
        switch mode {
        case .onePlace:
            // One-place sessions are more battery efficient due to significant location changes
            let averageDuration = sessions.reduce(0) { total, session in
                total + session.endTime.timeIntervalSince(session.startTime)
            } / Double(sessions.count)
            
            // Longer sessions in one-place mode are more efficient
            let durationScore = min(100, (averageDuration / 3600) * 20) // 20 points per hour
            return max(70, durationScore) // Minimum 70% efficiency
            
        case .onTheMove:
            // On-the-move efficiency depends on duration and frequency
            let averageDuration = sessions.reduce(0) { total, session in
                total + session.endTime.timeIntervalSince(session.startTime)
            } / Double(sessions.count)
            
            // Shorter sessions are more efficient for on-the-move
            let durationScore = max(0, 80 - ((averageDuration / 3600) * 15)) // Lose 15 points per hour
            return max(30, durationScore) // Minimum 30% efficiency
            
        case .unknown:
            return 50 // Neutral score
        }
    }
    
    // MARK: - Building Change Analytics (New)
    
    @MainActor func analyzeBuildingChangePatterns() -> BuildingChangeAnalytics {
        let sessions = dataStore.sessionHistory.filter { $0.mode == .onePlace }
        let allChanges = sessions.flatMap { $0.buildingChanges }
        
        guard !allChanges.isEmpty else {
            return BuildingChangeAnalytics(
                totalChanges: 0,
                averageChangesPerSession: 0,
                mostCommonTransitions: [],
                timeBasedPatterns: [:],
                autoDetectionRate: 0
            )
        }
        
        // Calculate common transitions
        let transitions = allChanges.compactMap { change -> BuildingTransition? in
            guard let fromBuilding = change.fromBuildingName else { return nil }
            return BuildingTransition(
                from: fromBuilding,
                to: change.toBuildingName,
                timestamp: change.timestamp,
                wasAutoDetected: change.wasAutoDetected
            )
        }
        
        let transitionCounts = Dictionary(grouping: transitions) { 
            "\($0.from) → \($0.to)" 
        }.mapValues { $0.count }
        
        let mostCommonTransitions = transitionCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { transition, count in
                (transition: transition, count: count)
            }
        
        // Time-based patterns
        let hourlyChanges = Dictionary(grouping: allChanges) { change in
            Calendar.current.component(.hour, from: change.timestamp)
        }.mapValues { $0.count }
        
        // Auto-detection rate
        let autoDetectedCount = allChanges.filter { $0.wasAutoDetected }.count
        let autoDetectionRate = Double(autoDetectedCount) / Double(allChanges.count)
        
        return BuildingChangeAnalytics(
            totalChanges: allChanges.count,
            averageChangesPerSession: Double(allChanges.count) / Double(sessions.count),
            mostCommonTransitions: mostCommonTransitions,
            timeBasedPatterns: hourlyChanges,
            autoDetectionRate: autoDetectionRate
        )
    }
    
    // MARK: - Enhanced Session Analytics
    
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
                diversityScore: 0,
                buildingTransitions: [],
                efficiencyScore: 0
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
        
        // Location breakdown with enhanced info
        let locationBreakdown = Dictionary(grouping: events) { $0.buildingName ?? "Unknown" }
            .mapValues { events in
                LocationStats(
                    totalPlays: events.count,
                    uniqueTracks: Set(events.map { $0.trackName }).count,
                    topArtist: Dictionary(grouping: events) { $0.artistName }
                        .max { $0.value.count < $1.value.count }?.key,
                    timeSpent: events.count * 90,
                    sessionMode: events.first?.sessionMode ?? .unknown,
                    firstVisit: events.min { $0.timestamp < $1.timestamp }?.timestamp,
                    lastVisit: events.max { $0.timestamp < $1.timestamp }?.timestamp
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
        
        // Building transitions (for analysis)
        let buildingTransitions = calculateBuildingTransitions(from: events)
        
        // Efficiency score based on session mode
        let efficiencyScore = calculateSessionEfficiency(events: events)
        
        return SessionAnalytics(
            sessionId: UUID(),
            mode: events.first?.sessionMode ?? .unknown,
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
            diversityScore: diversityScore,
            buildingTransitions: buildingTransitions,
            efficiencyScore: efficiencyScore
        )
    }
    
    private func calculateBuildingTransitions(from events: [ListeningEvent]) -> [BuildingTransition] {
        var transitions: [BuildingTransition] = []
        var lastBuilding: String?
        
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let currentBuilding = event.buildingName,
               let previousBuilding = lastBuilding,
               currentBuilding != previousBuilding {
                
                transitions.append(BuildingTransition(
                    from: previousBuilding,
                    to: currentBuilding,
                    timestamp: event.timestamp,
                    wasAutoDetected: true // Assume auto-detected from events
                ))
            }
            lastBuilding = event.buildingName
        }
        
        return transitions
    }
    
    private func calculateSessionEfficiency(events: [ListeningEvent]) -> Double {
        guard !events.isEmpty else { return 0 }
        
        let sessionMode = events.first?.sessionMode ?? .unknown
        let duration = events.count * 90 // seconds
        let uniqueLocations = Set(events.compactMap { $0.buildingName }).count
        
        switch sessionMode {
        case .onePlace:
            // Efficiency based on duration and consistency
            let locationConsistency = uniqueLocations <= 2 ? 1.0 : max(0.5, 2.0 / Double(uniqueLocations))
            let durationScore = min(1.0, Double(duration) / 7200) // 2 hours = perfect
            return (locationConsistency * 0.7) + (durationScore * 0.3)
            
        case .onTheMove:
            // Efficiency based on variety and duration
            let varietyScore = min(1.0, Double(uniqueLocations) / 5) // 5 locations = perfect
            let durationScore = duration < 21600 ? 1.0 : max(0.5, 21600.0 / Double(duration)) // 6 hours max
            return (varietyScore * 0.6) + (durationScore * 0.4)
            
        case .unknown:
            return 0.5
        }
    }
    
    // MARK: - Building Analytics (Enhanced)
    
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
        // Generate comprehensive building chart
        let trackCounts = Dictionary(grouping: events) { $0.trackName }
            .mapValues { $0.count }
        let topTracks = trackCounts.sorted { $0.value > $1.value }
            .prefix(20)
            .map { track, count in
                TrackRanking(
                    trackName: track,
                    artistName: events.first { $0.trackName == track }?.artistName ?? "Unknown",
                    playCount: count,
                    lastPlayed: events.filter { $0.trackName == track }.max { $0.timestamp < $1.timestamp }?.timestamp ?? Date()
                )
            }
        
        let artistCounts = Dictionary(grouping: events) { $0.artistName }
            .mapValues { $0.count }
        let topArtists = artistCounts.sorted { $0.value > $1.value }
            .prefix(20)
            .map { artist, count in
                ArtistRanking(
                    artistName: artist,
                    playCount: count,
                    uniqueTracks: Set(events.filter { $0.artistName == artist }.map { $0.trackName }).count,
                    lastPlayed: events.filter { $0.artistName == artist }.max { $0.timestamp < $1.timestamp }?.timestamp ?? Date()
                )
            }
        
        let genreCounts = Dictionary(grouping: events.compactMap { $0.genre }) { $0 }
            .mapValues { $0.count }
        let topGenres = genreCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { genre, count in
                GenreRanking(
                    genre: genre,
                    playCount: count,
                    percentage: Double(count) / Double(events.count)
                )
            }
        
        // Calculate peak hours
        let hourlyActivity = Dictionary(grouping: events) { event in
            Calendar.current.component(.hour, from: event.timestamp)
        }.mapValues { $0.count }
        
        let peakHours = hourlyActivity
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        
        return BuildingChart(
            buildingName: building,
            lastUpdated: Date(),
            topArtists: Array(topArtists),
            topTracks: Array(topTracks),
            topGenres: Array(topGenres),
            totalListeners: 1, // Placeholder for single user
            totalPlays: events.count,
            peakHours: Array(peakHours),
            sessionModeBreakdown: calculateSessionModeBreakdown(events: events),
            averageSessionLength: calculateAverageSessionLength(events: events),
            buildingCategory: categorizeBuildingFromEvents(events: events)
        )
    }
    
    private func calculateSessionModeBreakdown(events: [ListeningEvent]) -> [SessionMode: Int] {
        return Dictionary(grouping: events) { $0.sessionMode }
            .mapValues { $0.count }
    }
    
    private func calculateAverageSessionLength(events: [ListeningEvent]) -> TimeInterval {
        // Group events by session (approximate based on timestamp gaps)
        var sessions: [[ListeningEvent]] = []
        var currentSession: [ListeningEvent] = []
        
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        
        for event in sortedEvents {
            if let lastEvent = currentSession.last,
               event.timestamp.timeIntervalSince(lastEvent.timestamp) > 1800 { // 30 minute gap = new session
                if !currentSession.isEmpty {
                    sessions.append(currentSession)
                }
                currentSession = [event]
            } else {
                currentSession.append(event)
            }
        }
        
        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }
        
        guard !sessions.isEmpty else { return 0 }
        
        let totalDuration = sessions.reduce(0) { total, session in
            guard let first = session.first, let last = session.last else { return total }
            return total + last.timestamp.timeIntervalSince(first.timestamp)
        }
        
        return totalDuration / Double(sessions.count)
    }
    
    private func categorizeBuildingFromEvents(events: [ListeningEvent]) -> BuildingCategory {
        // Analyze listening patterns to categorize building
        let timeDistribution = calculateTimeDistribution(from: events)
        let averageDuration = events.count * 90 / 60 // minutes
        
        // Morning/daytime heavy + long sessions = office
        if timeDistribution.morning > 0.4 && timeDistribution.afternoon > 0.3 && averageDuration > 120 {
            return .office
        }
        
        // Evening heavy + moderate sessions = home
        if timeDistribution.evening > 0.4 && averageDuration > 60 {
            return .residential
        }
        
        // Short sessions + varied times = cafe/retail
        if averageDuration < 90 {
            return .cafe
        }
        
        return .other
    }
    
    // MARK: - Trend Detection (Enhanced)
    
    @MainActor func detectTrends(timeRange: TimeRange = .today) -> TrendReport {
        let currentEvents = filterEvents(timeRange: timeRange)
        let previousEvents = filterEvents(timeRange: previousTimeRange(for: timeRange))
        
        // Enhanced trend detection with session mode awareness
        let risingArtists = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.artistName },
            previous: Dictionary(grouping: previousEvents) { $0.artistName }
        ).map { artist, growth in
            TrendingItem(
                name: artist,
                type: .artist,
                growthRate: growth,
                playCount: currentEvents.filter { $0.artistName == artist }.count,
                rank: 0,
                sessionModes: getSessionModes(for: artist, in: currentEvents)
            )
        }
        
        let risingTracks = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.trackName },
            previous: Dictionary(grouping: previousEvents) { $0.trackName }
        ).map { track, growth in
            TrendingItem(
                name: track,
                type: .track,
                growthRate: growth,
                playCount: currentEvents.filter { $0.trackName == track }.count,
                rank: 0,
                sessionModes: getSessionModes(for: track, in: currentEvents, isTrack: true)
            )
        }
        
        let risingGenres = findRisingItems(
            current: Dictionary(grouping: currentEvents) { $0.genre ?? "Unknown" },
            previous: Dictionary(grouping: previousEvents) { $0.genre ?? "Unknown" }
        ).map { genre, growth in
            TrendingItem(
                name: genre,
                type: .genre,
                growthRate: growth,
                playCount: currentEvents.filter { $0.genre == genre }.count,
                rank: 0,
                sessionModes: getSessionModes(for: genre, in: currentEvents, isGenre: true)
            )
        }
        
        let hotLocations = Dictionary(grouping: currentEvents) { $0.buildingName ?? "Unknown" }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .enumerated()
            .map { index, location in
                HotLocation(
                    buildingName: location.key,
                    activityLevel: Double(location.value) / Double(currentEvents.count),
                    uniqueListeners: 1,
                    rank: index + 1,
                    sessionModeBreakdown: getLocationSessionModes(for: location.key, in: currentEvents)
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
    
    private func getSessionModes(for item: String, in events: [ListeningEvent], isTrack: Bool = false, isGenre: Bool = false) -> [SessionMode] {
        let relevantEvents: [ListeningEvent]
        
        if isTrack {
            relevantEvents = events.filter { $0.trackName == item }
        } else if isGenre {
            relevantEvents = events.filter { $0.genre == item }
        } else {
            relevantEvents = events.filter { $0.artistName == item }
        }
        
        return Array(Set(relevantEvents.map { $0.sessionMode }))
    }
    
    private func getLocationSessionModes(for location: String, in events: [ListeningEvent]) -> [SessionMode: Int] {
        let locationEvents = events.filter { $0.buildingName == location }
        return Dictionary(grouping: locationEvents) { $0.sessionMode }
            .mapValues { $0.count }
    }
    
    // MARK: - Helper Methods (Enhanced)
    
    private func updateSessionModeAnalytics(for event: ListeningEvent) {
        DispatchQueue.main.async {
            switch event.sessionMode {
            case .onePlace:
                self.sessionModeAnalytics.onePlaceEvents += 1
            case .onTheMove:
                self.sessionModeAnalytics.onTheMoveEvents += 1
            case .unknown:
                self.sessionModeAnalytics.unknownEvents += 1
            }
        }
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
            peakHours: [],
            sessionModeBreakdown: [:],
            averageSessionLength: 0,
            buildingCategory: .unknown
        )
        
        chart.totalPlays += 1
        chart.lastUpdated = Date()
        
        // Update session mode breakdown
        chart.sessionModeBreakdown[event.sessionMode, default: 0] += 1
        
        buildingCharts[building] = chart
    }
    
    @MainActor private func filterEvents(building: String? = nil, timeRange: TimeRange) -> [ListeningEvent] {
        let cutoffDate = timeRange.startDate
        
        return dataStore.currentSessionEvents.filter { event in
            if let building = building, event.buildingName != building {
                return false
            }
            return event.timestamp >= cutoffDate
        }
    }
    
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
        let trackDiversity = calculateShannonDiversity(tracks)
        let artistDiversity = calculateShannonDiversity(artists)
        let genreDiversity = calculateShannonDiversity(genres)
        
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
        
        let maxEntropy = log2(Double(counts.count))
        return maxEntropy > 0 ? entropy / maxEntropy : 0
    }

    private func findRisingItems(current: [String: [ListeningEvent]], previous: [String: [ListeningEvent]]) -> [(String, Double)] {
        var risingItems: [(String, Double)] = []
        
        for (item, currentEvents) in current {
            let currentCount = currentEvents.count
            let previousCount = previous[item]?.count ?? 0
            
            let growth = calculateGrowthRate(current: currentCount, previous: previousCount)
            
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
        switch timeRange {
        case .today: return .today
        case .thisWeek: return .thisWeek
        case .thisMonth: return .thisMonth
        case .allTime: return .allTime
        }
    }
    
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
        
        let hour = Calendar.current.component(.hour, from: event.timestamp)
        metrics.hourlyDistribution[hour, default: 0] += 1
        
        genreDistribution[genre] = metrics
    }
    
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
        metrics.activityLevel = calculateActivityLevel(for: metrics)
        
        globalHeatmap[cluster] = metrics
    }
    
    private func calculateActivityLevel(for metrics: LocationMetrics) -> Double {
        guard let lastActivity = metrics.lastActivity else { return 0 }
        
        let hoursSinceLastActivity = Date().timeIntervalSince(lastActivity) / 3600
        let recencyScore = max(0, 1 - (hoursSinceLastActivity / 24))
        let frequencyScore = min(1, Double(metrics.totalPlays) / 100)
        
        return (recencyScore * 0.7) + (frequencyScore * 0.3)
    }
    
    private func updateTimePatterns(for event: ListeningEvent) {
        // Time-based pattern tracking for session mode analytics
    }
}

// MARK: - Enhanced Supporting Types

struct SessionModeAnalytics {
    var onePlaceEvents: Int = 0
    var onTheMoveEvents: Int = 0
    var unknownEvents: Int = 0
    
    var totalEvents: Int {
        onePlaceEvents + onTheMoveEvents + unknownEvents
    }
    
    var onePlacePercentage: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(onePlaceEvents) / Double(totalEvents)
    }
    
    var onTheMovePercentage: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(onTheMoveEvents) / Double(totalEvents)
    }
}

struct SessionModeComparison {
    let onePlace: ModeStatistics
    let onTheMove: ModeStatistics
    let totalSessions: Int
    let generatedAt: Date
}

struct ModeStatistics {
    let mode: SessionMode
    let totalSessions: Int
    let totalEvents: Int
    let averageDuration: TimeInterval
    let uniqueBuildings: Int
    let topBuildings: [BuildingRanking]
    let averageTracksPerSession: Double
    let buildingChanges: Int
    let batteryEfficiencyScore: Double
}

struct BuildingRanking {
    let name: String
    let visitCount: Int
    let sessionCount: Int
}

struct BuildingChangeAnalytics {
    let totalChanges: Int
    let averageChangesPerSession: Double
    let mostCommonTransitions: [(transition: String, count: Int)]
    let timeBasedPatterns: [Int: Int] // Hour -> Count
    let autoDetectionRate: Double
}

struct BuildingTransition {
    let from: String
    let to: String
    let timestamp: Date
    let wasAutoDetected: Bool
}

// Enhanced session analytics
struct SessionAnalytics {
    let sessionId: UUID
    let mode: SessionMode
    let totalTracks: Int
    let uniqueTracks: Int
    let uniqueArtists: Int
    let uniqueLocations: Int
    let totalDuration: Int
    let topArtist: String?
    let topTrack: String?
    let topGenre: String?
    let locationBreakdown: [String: LocationStats]
    let genreDistribution: [String: Double]
    let timeDistribution: TimeDistribution
    let diversityScore: Double
    let buildingTransitions: [BuildingTransition]
    let efficiencyScore: Double
}

// Enhanced location stats
struct LocationStats {
    let totalPlays: Int
    let uniqueTracks: Int
    let topArtist: String?
    let timeSpent: Int
    let sessionMode: SessionMode
    let firstVisit: Date?
    let lastVisit: Date?
}

struct TimeDistribution {
    let morning: Double    // 6-12
    let afternoon: Double  // 12-18
    let evening: Double    // 18-24
    let lateNight: Double  // 0-6
}

// Enhanced building chart
struct BuildingChart {
    let buildingName: String
    var lastUpdated: Date
    var topArtists: [ArtistRanking]
    var topTracks: [TrackRanking]
    var topGenres: [GenreRanking]
    var totalListeners: Int
    var totalPlays: Int
    var peakHours: [Int]
    var sessionModeBreakdown: [SessionMode: Int]
    var averageSessionLength: TimeInterval
    var buildingCategory: BuildingCategory
    
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

// Enhanced trending items
struct TrendingItem: Codable {
    let name: String
    let type: TrendType
    let growthRate: Double
    let playCount: Int
    let rank: Int
    let sessionModes: [SessionMode]
}

enum TrendType: String, Codable {
    case artist, track, genre
}

// Enhanced hot locations
struct HotLocation: Codable {
    let buildingName: String
    let activityLevel: Double
    let uniqueListeners: Int
    let rank: Int
    let sessionModeBreakdown: [SessionMode: Int]
}

struct TrendReport: Codable {
    let timeRange: TimeRange
    let generatedAt: Date
    let risingArtists: [TrendingItem]
    let risingTracks: [TrendingItem]
    let risingGenres: [TrendingItem]
    let hotLocations: [HotLocation]
}

private class AnalyticsCache {
    private var chartCache: [String: (chart: BuildingChart, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 300
    
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
