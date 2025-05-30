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

// MARK: - SpotifyManager

class SpotifyManager: NSObject, ObservableObject {
    static let shared = SpotifyManager()

    // Your credentials
    private let clientID       = "3e7a70b96ac941ff9dde83c9477c4d8b"
    private let clientSecret   = "10272588b76f45d2a4ba2b7ba339ab29"
    private let redirectURI    = "loci://spotify-callback"
    private let scopes         = [
        "user-read-currently-playing",
        "user-read-recently-played"
    ].joined(separator: " ")

    // PKCE
    private var codeVerifier   = ""

    // Token storage keys
    private let service = "spotify"

    // Rate limiting
    private var lastAPICall = Date(timeIntervalSince1970: 0)
    private let minimumAPIInterval: TimeInterval = 1.0

    // Published state
    @Published var isAuthenticated = false
    @Published var currentTrack: SpotifyTrack?

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
                DispatchQueue.main.async { self.isAuthenticated = true }
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

    // MARK: — Actual Spotify API Calls

    private func fetchCurrentlyPlaying() async throws -> SpotifyTrack? {
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
            return try await fetchCurrentlyPlaying()
        default:
            print("❌ Spotify API status:", http.statusCode)
            return nil
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

// MARK: — ASWebAuthentication Presentation

extension SpotifyManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        UIApplication.shared.windows.first { $0.isKeyWindow }!
    }
}

