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
    @Published var hasRecentImports: Bool = false
    @Published var isLoading = false

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


    // MARK: - Load User Playlists
    
    func loadUserPlaylists() async {
        // Placeholder implementation - you can implement this later
        print("📝 Loading user playlists...")
    }
    // MARK: - Import Integration (Uses Existing EnrichmentEngine)


    /// Fetch recent tracks using existing EnrichmentEngine infrastructure
    // MARK: - Import Methods

    func fetchRecentlyPlayedTracks(limit: Int = 50) async throws -> [SpotifyImportTrack] {
        let endTime = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -24, to: endTime) ?? endTime
        
        // Use EnrichmentEngine
        let recentTracks = await EnrichmentEngine.shared.fetchRecentlyPlayed(from: startTime, to: endTime)
        
        // Convert to UI model
        return recentTracks.prefix(limit).map { recentTrack in
            SpotifyImportTrack(
                id: recentTrack.track.id,
                name: recentTrack.track.name,
                artist: recentTrack.track.artist,
                album: recentTrack.track.album,
                playedAt: recentTrack.playedAt,
                imageURL: recentTrack.track.imageURL
            )
        }
    }

    func getValidAccessToken() async throws -> String {
        // Check if we have a valid token first
        if let tokenData = try? KeychainHelper.read(service: service, account: "accessToken"),
           let token = String(data: tokenData, encoding: .utf8),
           let expiryData = try? KeychainHelper.read(service: service, account: "expiryDate"),
           let expiryDate = try? JSONDecoder().decode(Date.self, from: expiryData) {
            
            // If token is still valid (with 5-minute buffer), return it
            if expiryDate.timeIntervalSinceNow > 300 {
                return token
            }
            
            // Token is expired or about to expire, try to refresh
            print("🔄 Access token expired, attempting refresh...")
            try await refreshAccessToken()
            
            // Get the new token
            if let newTokenData = try? KeychainHelper.read(service: service, account: "accessToken"),
               let newToken = String(data: newTokenData, encoding: .utf8) {
                return newToken
            }
        }
        
        throw SpotifyError.notAuthenticated
    }

    private func refreshAccessToken() async throws {
        guard let refreshTokenData = try? KeychainHelper.read(service: service, account: "refreshToken"),
              let refreshToken = String(data: refreshTokenData, encoding: .utf8) else {
            throw SpotifyError.notAuthenticated
        }
        
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ].map { "\($0.key)=\($0.value)" }
         .joined(separator: "&")
         .data(using: .utf8)!
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ Token refresh failed: \(errorData)")
            }
            
            // If refresh fails, user needs to re-authenticate
            DispatchQueue.main.async {
                self.isAuthenticated = false
            }
            throw SpotifyError.notAuthenticated
        }
        
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        try saveTokens(tokens)
        
        print("✅ Access token refreshed successfully")
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
    // Add to SpotifyManager.swift

    func importFromTimeRange(start: Date, end: Date) async throws -> [ImportedTrack] {
        // Fetch from EnrichmentEngine
        let recentTracks = await EnrichmentEngine.shared.fetchRecentlyPlayed(from: start, to: end)
        
        // Convert to ImportedTrack format for UI
        return recentTracks.map { track in
            ImportedTrack(
                id: track.track.id,
                name: track.track.name,
                artist: track.track.artist,
                album: track.track.album,
                playedAt: track.playedAt,
                spotifyId: track.track.id
            )
        }
    }
    // MARK: - Session Manager Integration

    /// Fetch recently played tracks for a specific time period (for SessionManager)
    func fetchRecentlyPlayed(after startTime: Date, before endTime: Date, completion: @escaping ([TrackData]) -> Void) {
        Task {
            // Use EnrichmentEngine
            let recentTracks = await EnrichmentEngine.shared.fetchRecentlyPlayed(from: startTime, to: endTime)
            
            // Convert to TrackData format expected by SessionManager
            let trackData = recentTracks.map { recent in
                TrackData(
                    id: recent.track.id,
                    title: recent.track.name,
                    artist: recent.track.artist,
                    album: recent.track.album,
                    playedAt: recent.playedAt
                )
            }
            
            DispatchQueue.main.async {
                completion(trackData)
            }
        }
    }

    func getCurrentTrack(completion: @escaping (SpotifyTrack?) -> Void) {
        Task {
            do {
                let accessToken = try await getValidAccessToken()
                
                let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check if anything is playing
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                let currentlyPlaying = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
                
                guard let item = currentlyPlaying.item, currentlyPlaying.is_playing else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                let track = SpotifyTrack(
                    id: item.id,
                    name: item.name,
                    artist: item.artists.first?.name ?? "Unknown",
                    album: item.album.name,
                    genre: nil, // Current playing doesn't include genre
                    durationMs: item.duration_ms,
                    popularity: item.popularity,
                    imageURL: item.album.images.first?.url
                )
                
                DispatchQueue.main.async {
                    completion(track)
                }
                
            } catch {
                print("❌ Failed to get current track: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func getPlaylistTracks(playlistId: String) async throws -> [TrackData] {
        guard let accessToken = try? await getValidAccessToken() else {
            throw SpotifyError.notAuthenticated
        }
        
        // Implement playlist fetching
        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(PlaylistTracksResponse.self, from: data)
        
        return response.items.compactMap { item in
            guard let track = item.track else { return nil }
            return TrackData(
                id: track.id,
                title: track.name,
                artist: track.artists.first?.name ?? "Unknown",
                album: track.album.name,
                playedAt: ISO8601DateFormatter().date(from: item.added_at) ?? Date()
            )
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
}


// MARK: - Recent Tracks Response Models

