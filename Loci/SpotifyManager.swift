import Foundation
import Combine

// TODO: Replace with actual Spotify SDK/API implementation
class SpotifyManager: ObservableObject {
    static let shared = SpotifyManager()
    
    @Published var isAuthenticated = false
    @Published var currentTrack: SpotifyTrack?
    
    // Spotify API endpoints
    private let baseURL = "https://api.spotify.com/v1"
    private let currentlyPlayingEndpoint = "/me/player/currently-playing"
    private let recentlyPlayedEndpoint = "/me/player/recently-played"
    
    // TODO: Store these securely in Keychain
    private var accessToken: String?
    private var refreshToken: String?
    
    // API rate limiting
    private var lastAPICall = Date()
    private let minimumAPIInterval: TimeInterval = 1.0 // 1 second between calls
    
    private init() {
        // TODO: Load stored tokens from Keychain
        // For now, simulate authentication
        simulateAuthentication()
    }
    
    // MARK: - Authentication (Stubbed)
    
    private func simulateAuthentication() {
        // TODO: Implement actual Spotify OAuth flow
        // This will involve:
        // 1. Redirecting to Spotify auth URL with PKCE
        // 2. Handling callback with authorization code
        // 3. Exchanging code for access/refresh tokens
        // 4. Storing tokens securely in Keychain
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isAuthenticated = true
            print("🎵 Spotify: Simulated authentication successful")
        }
    }
    
    // MARK: - Track Fetching
    
    func getCurrentTrack(completion: @escaping (SpotifyTrack?) -> Void) {
        // Check rate limiting
        let timeSinceLastCall = Date().timeIntervalSince(lastAPICall)
        if timeSinceLastCall < minimumAPIInterval {
            let delay = minimumAPIInterval - timeSinceLastCall
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.getCurrentTrack(completion: completion)
            }
            return
        }
        
        lastAPICall = Date()
        
        // TODO: Replace with actual API call
        // For now, return mock data
        fetchMockTrack(completion: completion)
    }
    
    // MARK: - Mock Data (Remove when implementing real API)
    
    private func fetchMockTrack(completion: @escaping (SpotifyTrack?) -> Void) {
        // Simulate API delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let mockTracks = [
                SpotifyTrack(
                    id: "mock_1",
                    name: "Blinding Lights",
                    artist: "The Weeknd",
                    album: "After Hours",
                    genre: "Pop",
                    durationMs: 200040,
                    popularity: 95,
                    imageURL: nil
                ),
                SpotifyTrack(
                    id: "mock_2",
                    name: "Watermelon Sugar",
                    artist: "Harry Styles",
                    album: "Fine Line",
                    genre: "Pop",
                    durationMs: 174000,
                    popularity: 88,
                    imageURL: nil
                ),
                SpotifyTrack(
                    id: "mock_3",
                    name: "Levitating",
                    artist: "Dua Lipa",
                    album: "Future Nostalgia",
                    genre: "Pop",
                    durationMs: 203064,
                    popularity: 90,
                    imageURL: nil
                ),
                SpotifyTrack(
                    id: "mock_4",
                    name: "Heat Waves",
                    artist: "Glass Animals",
                    album: "Dreamland",
                    genre: "Alternative",
                    durationMs: 238805,
                    popularity: 92,
                    imageURL: nil
                ),
                SpotifyTrack(
                    id: "mock_5",
                    name: "good 4 u",
                    artist: "Olivia Rodrigo",
                    album: "SOUR",
                    genre: "Pop",
                    durationMs: 178147,
                    popularity: 94,
                    imageURL: nil
                )
            ]
            
            // Randomly return a track or nil (to simulate no track playing)
            if Bool.random() && Bool.random() { // 25% chance of no track
                completion(nil)
            } else {
                let track = mockTracks.randomElement()!
                self.currentTrack = track
                completion(track)
            }
        }
    }
    
    // MARK: - Actual API Implementation (TODO)
    
    private func makeAPIRequest(endpoint: String, completion: @escaping (Data?) -> Void) {
        // TODO: Implement actual API request with proper headers and error handling
        /*
        guard let accessToken = accessToken else {
            completion(nil)
            return
        }
        
        guard let url = URL(string: baseURL + endpoint) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Spotify API error: \(error)")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    completion(data)
                case 204:
                    // No content (nothing playing)
                    completion(nil)
                case 401:
                    // Token expired, refresh and retry
                    self.refreshAccessToken { success in
                        if success {
                            self.makeAPIRequest(endpoint: endpoint, completion: completion)
                        } else {
                            completion(nil)
                        }
                    }
                default:
                    print("❌ Spotify API returned status: \(httpResponse.statusCode)")
                    completion(nil)
                }
            }
        }.resume()
        */
    }
    
    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        // TODO: Implement token refresh
        completion(false)
    }
    
    // MARK: - Parsing
    
    private func parseCurrentlyPlayingResponse(data: Data) -> SpotifyTrack? {
        // TODO: Implement JSON parsing for Spotify API response
        /*
        Example response structure:
        {
            "item": {
                "id": "...",
                "name": "...",
                "artists": [{"name": "..."}],
                "album": {"name": "..."},
                "duration_ms": ...,
                "popularity": ...
            },
            "is_playing": true
        }
        */
        return nil
    }
}

// MARK: - Models

struct SpotifyTrack: Identifiable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let genre: String? // Note: Spotify doesn't directly provide genre in track info
    let durationMs: Int
    let popularity: Int?
    let imageURL: String?
}

// MARK: - Spotify OAuth Configuration

struct SpotifyConfiguration {
    // TODO: Replace with your actual Spotify app credentials
    static let clientId = "YOUR_SPOTIFY_CLIENT_ID"
    static let redirectURI = "loci://spotify-callback"
    static let scopes = [
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-read-playback-state"
    ]
    
    static var authorizationURL: URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        
        // TODO: Implement PKCE flow
        let codeChallenge = generateCodeChallenge()
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]
        
        return components.url!
    }
    
    private static func generateCodeChallenge() -> String {
        // TODO: Implement PKCE code challenge generation
        return "placeholder_code_challenge"
    }
}
