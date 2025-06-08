import Foundation
import Combine

// MARK: - Enrichment Engine

class EnrichmentEngine: ObservableObject {
    static let shared = EnrichmentEngine()
    
    private let spotifyManager = SpotifyManager.shared
    private let cacheManager = CacheManager.shared
    private let apiClient = APIClient.shared
    
    // Enrichment queue
    private let enrichmentQueue = DispatchQueue(label: "com.loci.enrichment", qos: .background)
    private var pendingEnrichments = [UUID: PendingEnrichment]()
    private let pendingLock = NSLock()
    
    // Batch processing
    private var batchTimer: Timer?
    private let batchSize = 50 // Spotify's max batch size
    private let batchInterval: TimeInterval = 5.0
    
    private init() {
        startBatchProcessing()
    }
    
    // MARK: - Public Interface
    
    /// Enrich a MediaPlayer-sourced event with Spotify metadata
    func enrichEvent(_ event: PartialListeningEvent, sessionMode: SessionMode = .unknown, completion: @escaping (ListeningEvent?) -> Void) {
        // Check cache first
        if let cachedTrack = findCachedTrack(title: event.trackName, artist: event.artistName) {
            let enrichedEvent = createEnrichedEvent(from: event, spotifyTrack: cachedTrack, sessionMode: sessionMode)
            completion(enrichedEvent)
            return
        }
        
        // Add to pending queue
        let enrichment = PendingEnrichment(
            id: event.id,
            event: event,
            sessionMode: sessionMode,
            completion: completion,
            timestamp: Date()
        )
        
        pendingLock.lock()
        pendingEnrichments[event.id] = enrichment
        pendingLock.unlock()
        
        // Process immediately if we have enough pending
        if pendingEnrichments.count >= batchSize {
            processPendingBatch()
        }
    }
    
    /// Reconcile a session's partial events with Spotify's recently-played
    func reconcileSession(
        sessionStart: Date,
        sessionEnd: Date,
        partialEvents: [PartialListeningEvent],
        sessionMode: SessionMode = .onTheMove
    ) async -> [ListeningEvent] {
        
        // 1. Fetch Spotify's recently-played for the session timeframe
        let recentlyPlayed = await fetchRecentlyPlayed(from: sessionStart, to: sessionEnd)
        
        // 2. Match partial events with Spotify data
        let enrichedEvents = await matchEventsWithSpotify(
            partialEvents: partialEvents,
            spotifyTracks: recentlyPlayed,
            sessionMode: sessionMode
        )
        
        // 3. For any unmatched events, try search API
        let unmatchedEvents = partialEvents.filter { partial in
            !enrichedEvents.contains { $0.id == partial.id }
        }
        
        let searchEnriched = await enrichViaSearch(unmatchedEvents, sessionMode: sessionMode)
        
        // 4. Combine all enriched events
        return enrichedEvents + searchEnriched
    }
    
    // MARK: - Batch Processing
    
    private func startBatchProcessing() {
        batchTimer = Timer.scheduledTimer(
            withTimeInterval: batchInterval,
            repeats: true
        ) { _ in
            self.processPendingBatch()
        }
    }
    
    private func processPendingBatch() {
        enrichmentQueue.async {
            self.pendingLock.lock()
            let batch = Array(self.pendingEnrichments.values.prefix(self.batchSize))
            batch.forEach { self.pendingEnrichments.removeValue(forKey: $0.id) }
            self.pendingLock.unlock()
            
            guard !batch.isEmpty else { return }
            
            Task {
                await self.processBatch(batch)
            }
        }
    }
    
    private func processBatch(_ batch: [PendingEnrichment]) async {
        // Group by search query to optimize
        let queries = batch.map { enrichment in
            SearchQuery(
                track: enrichment.event.trackName,
                artist: enrichment.event.artistName,
                enrichmentId: enrichment.id
            )
        }
        
        // Batch search via Spotify
        let results = await batchSearchSpotify(queries: queries)
        
        // Process results
        for enrichment in batch {
            if let spotifyTrack = results[enrichment.id] {
                // Cache the result
                cacheManager.cacheSpotifyTrack(spotifyTrack)
                
                // Create enriched event
                let enrichedEvent = createEnrichedEvent(
                    from: enrichment.event,
                    spotifyTrack: spotifyTrack,
                    sessionMode: enrichment.sessionMode
                )
                
                // Call completion
                DispatchQueue.main.async {
                    enrichment.completion(enrichedEvent)
                }
            } else {
                // Couldn't enrich - return partial data as-is
                let fallbackEvent = createFallbackEvent(from: enrichment.event, sessionMode: enrichment.sessionMode)
                DispatchQueue.main.async {
                    enrichment.completion(fallbackEvent)
                }
            }
        }
    }
    
    // MARK: - Spotify API Integration
    
    func fetchRecentlyPlayed(from startTime: Date, to endTime: Date) async -> [SpotifyRecentTrack] {
        // Spotify's recently-played endpoint has limitations:
        // - Max 50 items
        // - Only goes back ~3 hours
        
        guard let accessToken = try? await spotifyManager.getValidAccessToken() else {
            print("❌ No valid access token for recently played")
            return []
        }
        
        let url = URL(string: "https://api.spotify.com/v1/me/player/recently-played")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "after", value: "\(Int(startTime.timeIntervalSince1970 * 1000))")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP status code first
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Spotify API status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    // Log the error response
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ Spotify API error response: \(errorString)")
                    }
                    return []
                }
            }
            
            // Try to decode the response
            let decoder = JSONDecoder()
            
            // First, let's see what we actually got
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Raw Spotify response: \(jsonString)")
            }
            
            let recentlyPlayedResponse = try decoder.decode(RecentlyPlayedResponse.self, from: data)
            
            return recentlyPlayedResponse.items.compactMap { item in
                SpotifyRecentTrack(
                    track: SpotifyTrack(
                        id: item.track.id,
                        name: item.track.name,
                        artist: item.track.artists.first?.name ?? "Unknown",
                        album: item.track.album.name,
                        genre: nil, // Recently-played doesn't include genre
                        durationMs: item.track.duration_ms,
                        popularity: item.track.popularity,
                        imageURL: item.track.album.images.first?.url
                    ),
                    playedAt: ISO8601DateFormatter().date(from: item.played_at) ?? Date()
                )
            }
        } catch {
            print("❌ Failed to fetch recently played: \(error)")
            return []
        }
    }
    
    private func batchSearchSpotify(queries: [SearchQuery]) async -> [UUID: SpotifyTrack] {
        guard let accessToken = try? await spotifyManager.getValidAccessToken() else {
            return [:]
        }
        
        var results: [UUID: SpotifyTrack] = [:]
        
        // Process queries in chunks to avoid rate limits
        for query in queries {
            if let track = await searchSingleTrack(
                query: query,
                accessToken: accessToken
            ) {
                results[query.enrichmentId] = track
            }
            
            // Small delay to respect rate limits
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        return results
    }
    
    private func searchSingleTrack(query: SearchQuery, accessToken: String) async -> SpotifyTrack? {
        let searchString = "track:\(query.track) artist:\(query.artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let url = URL(string: "https://api.spotify.com/v1/search?q=\(searchString)&type=track&limit=1")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            
            guard let item = response.tracks.items.first else { return nil }
            
            // Fetch full track details for genre
            return await fetchTrackDetails(trackId: item.id, accessToken: accessToken)
            
        } catch {
            print("❌ Search failed for \(query.track): \(error)")
            return nil
        }
    }
    
    private func fetchTrackDetails(trackId: String, accessToken: String) async -> SpotifyTrack? {
        let url = URL(string: "https://api.spotify.com/v1/tracks/\(trackId)")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let track = try JSONDecoder().decode(SpotifyTrackResponse.self, from: data)
            
            // Try to get genre from artist
            let genre = await fetchArtistGenre(
                artistId: track.artists.first?.id ?? "",
                accessToken: accessToken
            )
            
            return SpotifyTrack(
                id: track.id,
                name: track.name,
                artist: track.artists.first?.name ?? "Unknown",
                album: track.album.name,
                genre: genre,
                durationMs: track.duration_ms,
                popularity: track.popularity,
                imageURL: track.album.images.first?.url
            )
            
        } catch {
            return nil
        }
    }
    
    private func fetchArtistGenre(artistId: String, accessToken: String) async -> String? {
        guard !artistId.isEmpty else { return nil }
        
        let url = URL(string: "https://api.spotify.com/v1/artists/\(artistId)")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let artist = try JSONDecoder().decode(SpotifyArtistResponse.self, from: data)
            return artist.genres.first
        } catch {
            return nil
        }
    }
    
    // MARK: - Event Matching
    
    private func matchEventsWithSpotify(
        partialEvents: [PartialListeningEvent],
        spotifyTracks: [SpotifyRecentTrack],
        sessionMode: SessionMode
    ) async -> [ListeningEvent] {
        var enrichedEvents: [ListeningEvent] = []
        
        for partial in partialEvents {
            // Find best match based on timestamp and fuzzy string matching
            let bestMatch = findBestMatch(
                partial: partial,
                candidates: spotifyTracks,
                timeWindow: 180 // 3 minute window
            )
            
            if let match = bestMatch {
                let enriched = createEnrichedEvent(
                    from: partial,
                    spotifyTrack: match.track,
                    sessionMode: sessionMode
                )
                enrichedEvents.append(enriched)
                
                // Cache for future use
                cacheManager.cacheSpotifyTrack(match.track)
            }
        }
        
        return enrichedEvents
    }
    
    private func findBestMatch(
        partial: PartialListeningEvent,
        candidates: [SpotifyRecentTrack],
        timeWindow: TimeInterval
    ) -> SpotifyRecentTrack? {
        
        let matches = candidates
            .filter { candidate in
                // Time window check
                abs(candidate.playedAt.timeIntervalSince(partial.timestamp)) <= timeWindow
            }
            .map { candidate in
                // Calculate similarity score
                let titleScore = stringSimilarity(
                    partial.trackName.lowercased(),
                    candidate.track.name.lowercased()
                )
                let artistScore = stringSimilarity(
                    partial.artistName.lowercased(),
                    candidate.track.artist.lowercased()
                )
                let combinedScore = (titleScore * 0.7) + (artistScore * 0.3)
                
                return (candidate: candidate, score: combinedScore)
            }
            .filter { $0.score > 0.8 } // 80% similarity threshold
            .sorted { $0.score > $1.score }
        
        return matches.first?.candidate
    }
    
    private func enrichViaSearch(_ events: [PartialListeningEvent], sessionMode: SessionMode) async -> [ListeningEvent] {
        var enrichedEvents: [ListeningEvent] = []
        
        for event in events {
            let query = SearchQuery(
                track: event.trackName,
                artist: event.artistName,
                enrichmentId: event.id
            )
            
            if let accessToken = try? await spotifyManager.getValidAccessToken(),
               let track = await searchSingleTrack(query: query, accessToken: accessToken) {
                
                let enriched = createEnrichedEvent(from: event, spotifyTrack: track, sessionMode: sessionMode)
                enrichedEvents.append(enriched)
                
                // Cache for future
                cacheManager.cacheSpotifyTrack(track)
            } else {
                // Create fallback event
                let fallback = createFallbackEvent(from: event, sessionMode: sessionMode)
                enrichedEvents.append(fallback)
            }
        }
        
        return enrichedEvents
    }
    
    // MARK: - Helper Methods
    
    private func findCachedTrack(title: String, artist: String) -> SpotifyTrack? {
        // Try exact ID match first
        let cacheKey = "\(title):\(artist)".lowercased()
        if let trackId = cacheManager.get(String.self, for: cacheKey, namespace: .spotifyMetadata),
           let track = cacheManager.getCachedSpotifyTrack(id: trackId) {
            return track
        }
        
        return nil
    }
    
    private func createEnrichedEvent(from partial: PartialListeningEvent, spotifyTrack: SpotifyTrack, sessionMode: SessionMode) -> ListeningEvent {
        return ListeningEvent(
            timestamp: partial.timestamp,
            latitude: partial.latitude,
            longitude: partial.longitude,
            buildingName: partial.buildingName,
            trackName: spotifyTrack.name,
            artistName: spotifyTrack.artist,
            albumName: spotifyTrack.album,
            genre: spotifyTrack.genre,
            spotifyTrackId: spotifyTrack.id,
            sessionMode: sessionMode
        )
    }
    
    private func createFallbackEvent(from partial: PartialListeningEvent, sessionMode: SessionMode) -> ListeningEvent {
        return ListeningEvent(
            timestamp: partial.timestamp,
            latitude: partial.latitude,
            longitude: partial.longitude,
            buildingName: partial.buildingName,
            trackName: partial.trackName,
            artistName: partial.artistName,
            albumName: partial.albumName,
            genre: nil,
            spotifyTrackId: "local:\(partial.id)",
            sessionMode: sessionMode
        )
    }
    
    private func stringSimilarity(_ str1: String, _ str2: String) -> Double {
        // Simple Levenshtein-based similarity
        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)
        guard maxLength > 0 else { return 0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1[s1.index(s1.startIndex, offsetBy: i-1)] ==
                          s2[s2.index(s2.startIndex, offsetBy: j-1)] ? 0 : 1
                
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,     // deletion
                    matrix[i][j-1] + 1,     // insertion
                    matrix[i-1][j-1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
}

// MARK: - Supporting Types

struct PartialListeningEvent {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let buildingName: String?
    let trackName: String
    let artistName: String
    let albumName: String?
}

private struct PendingEnrichment {
    let id: UUID
    let event: PartialListeningEvent
    let sessionMode: SessionMode
    let completion: (ListeningEvent?) -> Void
    let timestamp: Date
}

private struct SearchQuery {
    let track: String
    let artist: String
    let enrichmentId: UUID
}


// MARK: - Spotify API Response Models

private struct RecentlyPlayedResponse: Decodable {
    let items: [RecentlyPlayedItem]
    
    struct RecentlyPlayedItem: Decodable {
        let track: Track
        let played_at: String
    }
    
    struct Track: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
        let album: Album
        let duration_ms: Int
        let popularity: Int
    }
    
    struct Artist: Decodable {
        let id: String
        let name: String
    }
    
    struct Album: Decodable {
        let name: String
        let images: [Image]
    }
    
    struct Image: Decodable {
        let url: String
    }
}

private struct SearchResponse: Decodable {
    let tracks: TracksResult
    
    struct TracksResult: Decodable {
        let items: [Track]
    }
    
    struct Track: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
    }
    
    struct Artist: Decodable {
        let name: String
    }
}

private struct SpotifyTrackResponse: Decodable {
    let id: String
    let name: String
    let artists: [Artist]
    let album: Album
    let duration_ms: Int
    let popularity: Int
    
    struct Artist: Decodable {
        let id: String
        let name: String
    }
    
    struct Album: Decodable {
        let name: String
        let images: [Image]
    }
    
    struct Image: Decodable {
        let url: String
    }
}

private struct SpotifyArtistResponse: Decodable {
    let genres: [String]
}

// Add around line 20 in EnrichmentEngine.swift
struct SpotifyRecentTrack {
    let track: SpotifyTrack
    let playedAt: Date
}
private struct SpotifyErrorResponse: Decodable {
    let error: SpotifyError
    
    struct SpotifyError: Decodable {
        let status: Int
        let message: String
    }
}
