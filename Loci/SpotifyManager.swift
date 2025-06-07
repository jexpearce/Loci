import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Keychain Helper

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case noData
}

struct KeychainHelper {
    static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data
        ]
        SecItemDelete(query as CFDictionary) // remove old item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func read(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainError.noData }
        return data
    }
}

// MARK: - Models

struct SpotifyTrack: Identifiable, Codable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let genre: String?
    let durationMs: Int
    let popularity: Int?
    let imageURL: String?
}

// MARK: - API Response Models

private struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
}

private struct CurrentlyPlayingResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
        let album: Album
        let duration_ms: Int
        let popularity: Int
    }
    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        let name: String
        let images: [Image]
    }
    struct Image: Decodable { let url: String }
    let item: Item?
    let is_playing: Bool
}

private struct RecentlyPlayedResponse: Decodable {
    let items: [RecentlyPlayedItem]
    let next: String?
}

private struct RecentlyPlayedItem: Decodable {
    let track: Track
    let played_at: String
}

private struct PlaylistsResponse: Decodable {
    let items: [PlaylistItem]
}

private struct PlaylistItem: Decodable {
    let id: String
    let name: String
    let description: String?
    let tracks: PlaylistTracks
}

private struct PlaylistTracks: Decodable {
    let total: Int
}

private struct PlaylistTracksResponse: Decodable {
    let items: [PlaylistTrackItem]
    let next: String?
}

private struct PlaylistTrackItem: Decodable {
    let track: Track?
    let added_at: String
}

struct TracksResponse: Decodable {
    let tracks: [Track?] // Can contain null values for invalid IDs
}

struct Track: Decodable {
    let id: String
    let name: String
    let artists: [Artist]
    let album: Album
    let duration_ms: Int
    let popularity: Int
    
    struct Artist: Decodable {
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

// MARK: - SpotifyManager

class SpotifyManager: NSObject, ObservableObject {
    static let shared = SpotifyManager()

    // Your credentials
    private let clientID       = "3e7a70b96ac941ff9dde83c9477c4d8b"
    private let clientSecret   = "10272588b76f45d2a4ba2b7ba339ab29"
    private let redirectURI    = "loci://spotify-callback"
    private let scopes         = [
        "user-read-currently-playing",
        "user-read-recently-played",
        "playlist-read-private",
        "playlist-read-collaborative"
    ].joined(separator: " ")

    // PKCE
    private var codeVerifier   = ""

    // Token storage keys
    private let service = "spotify"

    // Rate limiting
    private var lastAPICall = Date(timeIntervalSince1970: 0)
    private let minimumAPIInterval: TimeInterval = 1.0
    
    // Retry logic with exponential backoff
    private var retryAttempts: [String: Int] = [:]
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // Published state
    @Published var isAuthenticated = false
    @Published var currentTrack: SpotifyTrack?
    @Published var userPlaylists: [SpotifyPlaylist] = []

    private override init() {
        super.init()
        // Attempt to read existing tokens to set isAuthenticated
        if let _ = try? KeychainHelper.read(service: service, account: "accessToken") {
            self.isAuthenticated = true
        }
    }

    // MARK: — Public Methods

    /// 1) Call this to start the OAuth flow
    func startAuthorization() {
        codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.makeCodeChallenge(from: codeVerifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]

        let session = ASWebAuthenticationSession(
            url: components.url!,
            callbackURLScheme: "loci"
        ) { callbackURL, error in
            guard error == nil, let url = callbackURL else {
                print("❌ Spotify auth failed:", error?.localizedDescription ?? "")
                return
            }
            self.handleRedirectURL(url)
        }
        session.presentationContextProvider = self
        session.start()
    }

    /// 2) After Spotify redirects → loci://spotify-callback?code=XXX
    func handleRedirectURL(_ url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
        else { return }

        Task {
            do {
                try await exchangeCodeForTokens(code: code)
                DispatchQueue.main.async { 
                    self.isAuthenticated = true
                    // Load user playlists after authentication
                    Task { await self.loadUserPlaylists() }
                }
            } catch {
                print("❌ Token exchange failed:", error)
            }
        }
    }

    /// 3) Public fetch for currently playing track
    func getCurrentTrack(completion: @escaping (SpotifyTrack?) -> Void) {
        // Rate limit
        let since = Date().timeIntervalSince(lastAPICall)
        guard since >= minimumAPIInterval else {
            let delay = minimumAPIInterval - since
            return DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.getCurrentTrack(completion: completion)
            }
        }
        lastAPICall = Date()

        Task {
            do {
                try await refreshIfNeeded()
                let track = try await fetchCurrentlyPlaying()
                DispatchQueue.main.async {
                    self.currentTrack = track
                    completion(track)
                }
            } catch {
                print("❌ fetchCurrentlyPlaying error:", error)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - NEW: Import Methods Implementation

    /// Fetch recently played tracks for import functionality
    func fetchRecentlyPlayed(after startTime: Date, before endTime: Date, completion: @escaping ([TrackData]) -> Void) {
        Task {
            do {
                let tracks = try await fetchRecentlyPlayedFromAPI(after: startTime, before: endTime)
                
                // Handle empty sessions gracefully
                if tracks.isEmpty {
                    print("📭 No tracks found for session period")
                }
                
                DispatchQueue.main.async {
                    completion(tracks)
                }
            } catch {
                print("❌ Failed to fetch recently played: \(error)")
                DispatchQueue.main.async {
                    completion([]) // Return empty array on error
                }
            }
        }
    }

    /// Import tracks from time range
    func importFromTimeRange(start: Date, end: Date) async throws -> [ImportedTrack] {
        let tracks = try await fetchRecentlyPlayedFromAPI(after: start, before: end)
        
        return tracks.map { track in
            ImportedTrack(
                id: track.id,
                name: track.title,
                artist: track.artist,
                album: track.album,
                playedAt: track.playedAt,
                spotifyId: track.id
            )
        }
    }

    /// Get playlist tracks
    func getPlaylistTracks(playlistId: String) async throws -> [TrackData] {
        return try await fetchPlaylistTracks(playlistId: playlistId)
    }

    /// Load user playlists
    func loadUserPlaylists() async {
        do {
            let playlists = try await fetchUserPlaylists()
            DispatchQueue.main.async {
                self.userPlaylists = playlists
            }
        } catch {
            print("❌ Failed to load playlists: \(error)")
        }
    }

    // MARK: — Internal OAuth & Token Handling

    private func exchangeCodeForTokens(code: String) async throws {
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientID,
            "code_verifier": codeVerifier
        ].map { "\($0.key)=\($0.value)" }
         .joined(separator: "&")
         .data(using: .utf8)!

        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        try saveTokens(tokens)
    }

    private func refreshIfNeeded() async throws {
        // 1) Read expiry date
        let expiryData = try KeychainHelper.read(service: service, account: "expiryDate")
        let expiryDate = try JSONDecoder().decode(Date.self, from: expiryData)
        guard expiryDate <= Date() else { return }

        // 2) Read refresh token
        let refreshData = try KeychainHelper.read(service: service, account: "refreshToken")
        guard let refreshToken = String(data: refreshData, encoding: .utf8) else { return }

        // 3) Make refresh request
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     clientID,
            "client_secret": clientSecret
        ].map { "\($0.key)=\($0.value)" }
         .joined(separator: "&")
         .data(using: .utf8)!

        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        try saveTokens(tokens)
    }

    private func saveTokens(_ tokens: TokenResponse) throws {
        // Access Token
        try KeychainHelper.save(
            Data(tokens.access_token.utf8),
            service: service,
            account: "accessToken"
        )
        // Refresh Token
        if let refresh = tokens.refresh_token {
            try KeychainHelper.save(
                Data(refresh.utf8),
                service: service,
                account: "refreshToken"
            )
        }
        // Expiry Date
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        let expiryData = try JSONEncoder().encode(expiryDate)
        try KeychainHelper.save(
            expiryData,
            service: service,
            account: "expiryDate"
        )
    }

    // MARK: — Spotify API Implementation

    private func fetchCurrentlyPlaying() async throws -> SpotifyTrack? {
        return try await retryWithBackoff(
            operation: { try await self.performFetchCurrentlyPlaying() },
            operationId: "fetchCurrentlyPlaying"
        )
    }
    
    private func performFetchCurrentlyPlaying() async throws -> SpotifyTrack? {
        // Build request
        let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
        var req = URLRequest(url: url)
        let tokenData = try KeychainHelper.read(service: service, account: "accessToken")
        let accessToken = String(data: tokenData, encoding: .utf8)!
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // Fetch
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200:
            let response = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
            guard let item = response.item, response.is_playing else { return nil }
            // Map to model
            return SpotifyTrack(
                id: item.id,
                name: item.name,
                artist: item.artists.first?.name ?? "Unknown",
                album: item.album.name,
                genre: nil,
                durationMs: item.duration_ms,
                popularity: item.popularity,
                imageURL: item.album.images.first?.url
            )
        case 204:
            return nil
        case 401:
            // Token expired—refresh + retry once
            try await refreshIfNeeded()
            return try await performFetchCurrentlyPlaying()
        case 429:
            throw HTTPError(statusCode: 429)
        default:
            print("❌ Spotify API status:", http.statusCode)
            if http.statusCode >= 500 {
                throw HTTPError(statusCode: http.statusCode)
            }
            return nil
        }
    }

    // MARK: - Recently Played Implementation

    private func fetchRecentlyPlayedFromAPI(after startTime: Date, before endTime: Date) async throws -> [TrackData] {
        return try await retryWithBackoff(
            operation: { try await self.performFetchRecentlyPlayed(after: startTime, before: endTime) },
            operationId: "fetchRecentlyPlayed"
        )
    }
    
    private func performFetchRecentlyPlayed(after startTime: Date, before endTime: Date) async throws -> [TrackData] {
        // Convert dates to Unix timestamps (milliseconds)
        let afterTimestamp = Int(startTime.timeIntervalSince1970 * 1000)
        let beforeTimestamp = Int(endTime.timeIntervalSince1970 * 1000)
        
        // Build URL with query parameters
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")!
        components.queryItems = [
            URLQueryItem(name: "after", value: String(afterTimestamp)),
            URLQueryItem(name: "before", value: String(beforeTimestamp)),
            URLQueryItem(name: "limit", value: "50") // Maximum allowed by Spotify
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        // Create request with authorization
        var request = URLRequest(url: url)
        let tokenData = try KeychainHelper.read(service: service, account: "accessToken")
        let accessToken = String(data: tokenData, encoding: .utf8)!
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Make API call
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let recentlyPlayedResponse = try JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
            return recentlyPlayedResponse.items.map { item in
                TrackData(
                    id: item.track.id,
                    title: item.track.name,
                    artist: item.track.artists.first?.name ?? "Unknown Artist",
                    album: item.track.album.name,
                    playedAt: ISO8601DateFormatter().date(from: item.played_at) ?? Date()
                )
            }
        case 401:
            // Token expired, refresh and retry
            try await refreshIfNeeded()
            return try await performFetchRecentlyPlayed(after: startTime, before: endTime)
        case 429:
            throw HTTPError(statusCode: 429)
        default:
            print("❌ Spotify recently played API error: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 500 {
                throw HTTPError(statusCode: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Playlist Implementation

    private func fetchUserPlaylists() async throws -> [SpotifyPlaylist] {
        return try await retryWithBackoff(
            operation: { try await self.performFetchUserPlaylists() },
            operationId: "fetchUserPlaylists"
        )
    }

    private func performFetchUserPlaylists() async throws -> [SpotifyPlaylist] {
        let url = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!
        var request = URLRequest(url: url)
        
        let tokenData = try KeychainHelper.read(service: service, account: "accessToken")
        let accessToken = String(data: tokenData, encoding: .utf8)!
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let playlistsResponse = try JSONDecoder().decode(PlaylistsResponse.self, from: data)
            return playlistsResponse.items.map { item in
                SpotifyPlaylist(
                    id: item.id,
                    name: item.name,
                    description: item.description,
                    trackCount: item.tracks.total
                )
            }
        case 401:
            try await refreshIfNeeded()
            return try await performFetchUserPlaylists()
        case 429:
            throw HTTPError(statusCode: 429)
        default:
            print("❌ Spotify playlists API error: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 500 {
                throw HTTPError(statusCode: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
    }

    private func fetchPlaylistTracks(playlistId: String) async throws -> [TrackData] {
        return try await retryWithBackoff(
            operation: { try await self.performFetchPlaylistTracks(playlistId: playlistId) },
            operationId: "fetchPlaylistTracks_\(playlistId)"
        )
    }

    private func performFetchPlaylistTracks(playlistId: String) async throws -> [TrackData] {
        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks?limit=50")!
        var request = URLRequest(url: url)
        
        let tokenData = try KeychainHelper.read(service: service, account: "accessToken")
        let accessToken = String(data: tokenData, encoding: .utf8)!
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let playlistTracksResponse = try JSONDecoder().decode(PlaylistTracksResponse.self, from: data)
            return playlistTracksResponse.items.compactMap { item in
                guard let track = item.track else { return nil }
                return TrackData(
                    id: track.id,
                    title: track.name,
                    artist: track.artists.first?.name ?? "Unknown Artist",
                    album: track.album.name,
                    playedAt: ISO8601DateFormatter().date(from: item.added_at) ?? Date()
                )
            }
        case 401:
            try await refreshIfNeeded()
            return try await performFetchPlaylistTracks(playlistId: playlistId)
        case 429:
            throw HTTPError(statusCode: 429)
        default:
            print("❌ Spotify playlist tracks API error: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 500 {
                throw HTTPError(statusCode: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
    }

    // MARK: — PKCE Utilities

    private static func makeCodeVerifier() -> String {
        let length = 64
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        let base64 = Data(hash).base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
    
    // MARK: - Retry Logic with Exponential Backoff
    
    private func retryWithBackoff<T>(
        operation: @escaping () async throws -> T,
        operationId: String
    ) async throws -> T {
        let currentAttempt = retryAttempts[operationId, default: 0]
        
        do {
            let result = try await operation()
            // Success - reset retry count
            retryAttempts.removeValue(forKey: operationId)
            return result
        } catch {
            // Check if we should retry
            guard currentAttempt < maxRetryAttempts else {
                retryAttempts.removeValue(forKey: operationId)
                throw error
            }
            
            // Check if it's a retryable error
            if let urlError = error as? URLError,
               urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                // Network errors - retry
            } else if let httpError = error as? HTTPError, httpError.statusCode == 429 {
                // Rate limited - retry
            } else if let httpError = error as? HTTPError, httpError.statusCode >= 500 {
                // Server errors - retry
            } else {
                // Don't retry for other errors (auth, client errors, etc.)
                retryAttempts.removeValue(forKey: operationId)
                throw error
            }
            
            // Increment attempt count
            retryAttempts[operationId] = currentAttempt + 1
            
            // Calculate delay with exponential backoff + jitter
            let delay = baseRetryDelay * pow(2.0, Double(currentAttempt))
            let jitter = Double.random(in: 0...0.1) * delay
            let totalDelay = delay + jitter
            
            print("🔄 Retrying Spotify API call (attempt \(currentAttempt + 1)/\(maxRetryAttempts)) after \(totalDelay)s")
            
            try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
            
            // Retry
            return try await retryWithBackoff(operation: operation, operationId: operationId)
        }
    }
    
    // MARK: - Batch Track Lookup (for Active Mode Reconciliation)
    
    func batchLookupTracks(trackIds: [String]) async throws -> [String: SpotifyTrack] {
        var allTracks: [String: SpotifyTrack] = [:]
        
        // Split into batches of 50 (Spotify's limit)
        let batches = trackIds.chunked(into: 50)
        
        for batch in batches {
            let batchTracks = try await retryWithBackoff(
                operation: { try await self.performBatchLookup(trackIds: batch) },
                operationId: "batchLookup_\(batch.hashValue)"
            )
            allTracks.merge(batchTracks) { _, new in new }
        }
        
        return allTracks
    }
    
    private func performBatchLookup(trackIds: [String]) async throws -> [String: SpotifyTrack] {
        let idsString = trackIds.joined(separator: ",")
        let url = URL(string: "https://api.spotify.com/v1/tracks?ids=\(idsString)")!
        
        var request = URLRequest(url: url)
        let tokenData = try KeychainHelper.read(service: service, account: "accessToken")
        let accessToken = String(data: tokenData, encoding: .utf8)!
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let tracksResponse = try JSONDecoder().decode(TracksResponse.self, from: data)
            var trackDict: [String: SpotifyTrack] = [:]
            
            for track in tracksResponse.tracks.compactMap({ $0 }) { // Filter out null tracks
                let spotifyTrack = SpotifyTrack(
                    id: track.id,
                    name: track.name,
                    artist: track.artists.first?.name ?? "Unknown",
                    album: track.album.name,
                    genre: nil,
                    durationMs: track.duration_ms,
                    popularity: track.popularity,
                    imageURL: track.album.images.first?.url
                )
                trackDict[track.id] = spotifyTrack
            }
            
            return trackDict
            
        case 401:
            try await refreshIfNeeded()
            return try await performBatchLookup(trackIds: trackIds)
            
        case 429:
            throw HTTPError(statusCode: 429)
            
        default:
            print("❌ Spotify batch lookup error: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 500 {
                throw HTTPError(statusCode: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Supporting Types for Import

struct TrackData {
    let id: String
    let title: String
    let artist: String
    let album: String
    let playedAt: Date
}

struct SpotifyPlaylist: Identifiable {
    let id: String
    let name: String
    let description: String?
    let trackCount: Int
}

struct ImportedTrack: Identifiable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let playedAt: Date
    let spotifyId: String
}

// MARK: — ASWebAuthentication Presentation

extension SpotifyManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        UIApplication.shared.windows.first { $0.isKeyWindow }!
    }
}

// MARK: - HTTP Error for Retry Logic

struct HTTPError: Error {
    let statusCode: Int
}

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

