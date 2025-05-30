//
//  Matching.swift
//  Loci
//
//  Created by Jex Pearce on 30/05/2025.
//

import Foundation
import CoreLocation

class MatchingEngine: ObservableObject {
    static let shared = MatchingEngine()
    
    private let analyticsEngine = AnalyticsEngine.shared
    
    // Matching thresholds
    private let minimumOverlapThreshold = 0.3 // 30% similarity for basic match
    private let strongMatchThreshold = 0.7     // 70% for strong match
    private let locationProximityWeight = 0.25
    private let musicTasteWeight = 0.5
    private let timePatternWeight = 0.25
    
    private init() {}
    
    // MARK: - Matching Core
    
    func findMatches(for userFingerprint: ListeningFingerprint,
                     from candidates: [ListeningFingerprint],
                     filters: MatchFilters = MatchFilters()) -> [Match] {
        
        var matches: [Match] = []
        
        for candidate in candidates {
            guard candidate.id != userFingerprint.id else { continue }
            
            // Apply filters
            if !passesFilters(candidate, filters: filters) {
                continue
            }
            
            // Calculate match score
            let score = calculateMatchScore(userFingerprint, candidate)
            
            if score.overall >= minimumOverlapThreshold {
                let match = Match(
                    userId: candidate.id,
                    score: score,
                    matchType: categorizeMatch(score),
                    sharedInterests: findSharedInterests(userFingerprint, candidate),
                    timestamp: Date()
                )
                matches.append(match)
            }
        }
        
        // Sort by score and limit results
        return matches
            .sorted { $0.score.overall > $1.score.overall }
            .prefix(filters.maxResults)
            .map { $0 }
    }
    
    // MARK: - Score Calculation
    
    private func calculateMatchScore(_ user: ListeningFingerprint, _ candidate: ListeningFingerprint) -> MatchScore {
        // Music taste similarity (artists + genres)
        let artistSimilarity = cosineSimilarity(user.artistVector, candidate.artistVector)
        let genreSimilarity = cosineSimilarity(user.genreVector, candidate.genreVector)
        let musicScore = (artistSimilarity * 0.6) + (genreSimilarity * 0.4)
        
        // Location overlap
        let locationScore = cosineSimilarity(user.locationVector, candidate.locationVector)
        
        // Time pattern similarity
        let timeScore = cosineSimilarity(user.timeVector, candidate.timeVector)
        
        // Diversity compatibility
        let diversityDiff = abs(user.diversityScore - candidate.diversityScore)
        let diversityScore = 1.0 - min(diversityDiff, 1.0)
        
        // Calculate weighted overall score
        let overall = (musicScore * musicTasteWeight) +
                     (locationScore * locationProximityWeight) +
                     (timeScore * timePatternWeight)
        
        return MatchScore(
            overall: overall,
            musicTaste: musicScore,
            locationOverlap: locationScore,
            timeAlignment: timeScore,
            diversityMatch: diversityScore
        )
    }
    
    // MARK: - Overlap Detection
    
    func detectOverlappingSessions(user: SessionData, others: [SessionData]) -> [SessionOverlap] {
        var overlaps: [SessionOverlap] = []
        
        for other in others {
            guard other.id != user.id else { continue }
            
            // Check time overlap
            let timeOverlap = calculateTimeOverlap(user: user, other: other)
            guard timeOverlap > 0 else { continue }
            
            // Find location overlaps
            let locationOverlaps = findLocationOverlaps(user: user, other: other)
            guard !locationOverlaps.isEmpty else { continue }
            
            // Find music overlaps
            let musicOverlaps = findMusicOverlaps(user: user, other: other)
            
            let overlap = SessionOverlap(
                otherSessionId: other.id,
                timeOverlapMinutes: Int(timeOverlap / 60),
                sharedLocations: locationOverlaps,
                sharedArtists: musicOverlaps.artists,
                sharedTracks: musicOverlaps.tracks,
                overlapScore: calculateOverlapScore(timeOverlap: timeOverlap,
                                                   locationCount: locationOverlaps.count,
                                                   musicCount: musicOverlaps.artists.count + musicOverlaps.tracks.count)
            )
            
            overlaps.append(overlap)
        }
        
        return overlaps.sorted { $0.overlapScore > $1.overlapScore }
    }
    
    private func calculateTimeOverlap(user: SessionData, other: SessionData) -> TimeInterval {
        let userRange = user.startTime...user.endTime
        let otherRange = other.startTime...other.endTime
        
        // Check if ranges overlap
        guard userRange.overlaps(otherRange) else { return 0 }
        
        let overlapStart = max(user.startTime, other.startTime)
        let overlapEnd = min(user.endTime, other.endTime)
        
        return overlapEnd.timeIntervalSince(overlapStart)
    }
    
    private func findLocationOverlaps(user: SessionData, other: SessionData) -> [SharedLocation] {
        var sharedLocations: [SharedLocation] = []
        let threshold: TimeInterval = 600 // 10 minutes
        
        for userEvent in user.events {
            guard let userBuilding = userEvent.buildingName else { continue }
            
            for otherEvent in other.events {
                guard let otherBuilding = otherEvent.buildingName,
                      userBuilding == otherBuilding else { continue }
                
                let timeDiff = abs(userEvent.timestamp.timeIntervalSince(otherEvent.timestamp))
                if timeDiff <= threshold {
                    sharedLocations.append(SharedLocation(
                        buildingName: userBuilding,
                        userTimestamp: userEvent.timestamp,
                        otherTimestamp: otherEvent.timestamp,
                        timeDifference: Int(timeDiff)
                    ))
                }
            }
        }
        
        // Remove duplicates and return
        return Array(Set(sharedLocations))
    }
    
    private func findMusicOverlaps(user: SessionData, other: SessionData) -> (artists: Set<String>, tracks: Set<String>) {
        let userArtists = Set(user.events.map { $0.artistName })
        let userTracks = Set(user.events.map { $0.trackName })
        
        let otherArtists = Set(other.events.map { $0.artistName })
        let otherTracks = Set(other.events.map { $0.trackName })
        
        return (
            artists: userArtists.intersection(otherArtists),
            tracks: userTracks.intersection(otherTracks)
        )
    }
    
    // MARK: - Interest Analysis
    
    private func findSharedInterests(_ user: ListeningFingerprint, _ candidate: ListeningFingerprint) -> SharedInterests {
        // This would analyze the fingerprints to find specific shared interests
        // For now, returning a placeholder
        return SharedInterests(
            topSharedArtists: [],
            topSharedGenres: [],
            sharedListeningTimes: [],
            sharedLocations: []
        )
    }
    
    // MARK: - Helper Methods
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    private func passesFilters(_ candidate: ListeningFingerprint, filters: MatchFilters) -> Bool {
        // Activity level filter
        if let minActivity = filters.minimumActivity {
            guard candidate.totalEvents >= minActivity else { return false }
        }
        
        // Diversity filter
        if let diversityRange = filters.diversityRange {
            guard diversityRange.contains(candidate.diversityScore) else { return false }
        }
        
        // Additional filters would be implemented here
        
        return true
    }
    
    private func categorizeMatch(_ score: MatchScore) -> MatchType {
        if score.overall >= strongMatchThreshold {
            return .strong
        } else if score.musicTaste >= strongMatchThreshold {
            return .musicTwin
        } else if score.locationOverlap >= strongMatchThreshold {
            return .neighbor
        } else if score.timeAlignment >= strongMatchThreshold {
            return .scheduleMatch
        } else {
            return .casual
        }
    }
    
    private func calculateOverlapScore(timeOverlap: TimeInterval, locationCount: Int, musicCount: Int) -> Double {
        let timeScore = min(timeOverlap / 3600, 1.0) // Normalize to 1 hour max
        let locationScore = min(Double(locationCount) / 5, 1.0) // Normalize to 5 locations
        let musicScore = min(Double(musicCount) / 10, 1.0) // Normalize to 10 shared items
        
        return (timeScore * 0.3) + (locationScore * 0.3) + (musicScore * 0.4)
    }
    
    // MARK: - Match Ranking
    
    func rankMatches(_ matches: [Match], preferences: MatchPreferences) -> [Match] {
        return matches.map { match in
            var adjustedMatch = match
            
            // Apply preference weights
            let adjustedScore = (match.score.musicTaste * preferences.musicWeight) +
                              (match.score.locationOverlap * preferences.locationWeight) +
                              (match.score.timeAlignment * preferences.timeWeight) +
                              (match.score.diversityMatch * preferences.diversityWeight)
            
            adjustedMatch.score.overall = adjustedScore
            return adjustedMatch
        }.sorted { $0.score.overall > $1.score.overall }
    }
}

// MARK: - Supporting Types

struct Match: Codable{
    let userId: UUID
    var score: MatchScore
    let matchType: MatchType
    let sharedInterests: SharedInterests
    let timestamp: Date
}

struct MatchScore: Codable {
    var overall: Double
    let musicTaste: Double
    let locationOverlap: Double
    let timeAlignment: Double
    let diversityMatch: Double
}

enum MatchType: String, Codable {
    case strong       // High overall match
    case musicTwin    // Very similar music taste
    case neighbor     // Same locations frequently
    case scheduleMatch // Similar listening times
    case casual       // Basic match
    
    var emoji: String {
        switch self {
        case .strong: return "🌟"
        case .musicTwin: return "🎵"
        case .neighbor: return "📍"
        case .scheduleMatch: return "🕐"
        case .casual: return "👋"
        }
    }
}

struct SharedInterests: Codable {
    let topSharedArtists: [String]
    let topSharedGenres: [String]
    let sharedListeningTimes: [TimeOfDay]
    let sharedLocations: [String]
}

struct MatchFilters {
    var minimumActivity: Int? = nil
    var diversityRange: ClosedRange<Double>? = nil
    var ageRange: ClosedRange<Int>? = nil // For future use
    var genres: Set<String>? = nil // Filter by specific genres
    var maxResults: Int = 50
}

struct MatchPreferences {
    var musicWeight: Double = 0.5
    var locationWeight: Double = 0.25
    var timeWeight: Double = 0.15
    var diversityWeight: Double = 0.1
}

struct SessionOverlap {
    let otherSessionId: UUID
    let timeOverlapMinutes: Int
    let sharedLocations: [SharedLocation]
    let sharedArtists: Set<String>
    let sharedTracks: Set<String>
    let overlapScore: Double
}

struct SharedLocation: Hashable {
    let buildingName: String
    let userTimestamp: Date
    let otherTimestamp: Date
    let timeDifference: Int // seconds
}
