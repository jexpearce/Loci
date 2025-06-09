import Foundation
import Combine

// MARK: - API Configuration

struct APIConfiguration {
    let baseURL: URL
    let apiKey: String?
    let timeout: TimeInterval
    
    static let production = APIConfiguration(
        baseURL: URL(string: "https://api.loci.app/v1")!,
        apiKey: ProcessInfo.processInfo.environment["LOCI_API_KEY"],
        timeout: 30
    )
    
    static let development = APIConfiguration(
        baseURL: URL(string: "http://localhost:8080/v1")!,
        apiKey: "dev-key",
        timeout: 60
    )
}

// MARK: - API Endpoints

enum APIEndpoint {
    case sessions
    case session(id: String)
    case events
    case leaderboard(building: String?, timeRange: TimeRange)
    case trends(timeRange: TimeRange)
    case userProfile(id: String)
    case matches(userId: String)
    case analytics(type: AnalyticsType)
    
    var path: String {
        switch self {
        case .sessions:
            return "/sessions"
        case .session(let id):
            return "/sessions/\(id)"
        case .events:
            return "/events"
        case .leaderboard:
            return "/leaderboards"
        case .trends:
            return "/trends"
        case .userProfile(let id):
            return "/users/\(id)"
        case .matches(let userId):
            return "/users/\(userId)/matches"
        case .analytics(let type):
            return "/analytics/\(type.rawValue)"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .sessions, .events:
            return .post
        default:
            return .get
        }
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

enum AnalyticsType: String {
    case realtime = "realtime"
    case historical = "historical"
    case predictive = "predictive"
}

// MARK: - API Client

class APIClient: ObservableObject {
    static let shared = APIClient()
    
    private let configuration: APIConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // Authentication
    @Published var authToken: String?
    
    // Request tracking
    private var activeTasks = Set<URLSessionTask>()
    private let taskQueue = DispatchQueue(label: "com.loci.api.tasks")
    
    private init(configuration: APIConfiguration = .development) {
        self.configuration = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.waitsForConnectivity = true
        
        self.session = URLSession(configuration: sessionConfig)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        // Load auth token from keychain if available
        self.authToken = loadAuthToken()
    }
    
    // MARK: - Core Request Method
    
    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: Encodable? = nil,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        let request = try buildRequest(
            endpoint: endpoint,
            body: body,
            parameters: parameters,
            headers: headers
        )
        
        let (data, response) = try await session.data(for: request)
        
        try validateResponse(response)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log the error and raw response for debugging
            print("❌ Decoding error: \(error)")
            print("📦 Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Upload Method
    
    func upload<T: Decodable>(
        _ endpoint: APIEndpoint,
        data: Data,
        mimeType: String,
        parameters: [String: Any]? = nil
    ) async throws -> T {
        var request = try buildRequest(endpoint: endpoint, parameters: parameters)
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add parameters
        parameters?.forEach { key, value in
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: responseData)
    }
    
    // MARK: - Convenience Methods
    
    func get<T: Decodable>(_ endpoint: APIEndpoint, parameters: [String: Any]? = nil) async throws -> T {
        return try await request(endpoint, parameters: parameters)
    }
    
    func post<T: Decodable>(_ endpoint: APIEndpoint, body: Encodable) async throws -> T {
        return try await request(endpoint, body: body)
    }
    
    func delete(_ endpoint: APIEndpoint) async throws {
        let _: EmptyResponse = try await request(endpoint)
    }
    
    // MARK: - Request Building
    
    private func buildRequest(
        endpoint: APIEndpoint,
        body: Encodable? = nil,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) throws -> URLRequest {
        var url = configuration.baseURL.appendingPathComponent(endpoint.path)
        
        // Add query parameters for GET requests
        if endpoint.method == .get, let parameters = parameters {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = parameters.map {
                URLQueryItem(name: $0.key, value: "\($0.value)")
            }
            url = components.url!
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        
        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Loci-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        // Auth header
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // API key if configured
        if let apiKey = configuration.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        // Custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Body
        if let body = body {
            request.httpBody = try encoder.encode(body)
        } else if endpoint.method != .get, let parameters = parameters {
            // For non-GET requests, encode parameters as JSON
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }
        
        return request
    }
    
    // MARK: - Response Validation
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Authentication
    
    func authenticate(with token: String) {
        authToken = token
        saveAuthToken(token)
    }
    
    func logout() {
        authToken = nil
        deleteAuthToken()
    }
    
    private func loadAuthToken() -> String? {
        // Use KeychainHelper from SpotifyManager
        try? String(data: KeychainHelper.read(service: "loci", account: "authToken"), encoding: .utf8)
    }
    
    private func saveAuthToken(_ token: String) {
        try? KeychainHelper.save(Data(token.utf8), service: "loci", account: "authToken")
    }
    
    private func deleteAuthToken() {
        // Remove from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "loci",
            kSecAttrAccount as String: "authToken"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Task Management
    
    func cancelAllRequests() {
        taskQueue.sync {
            activeTasks.forEach { $0.cancel() }
            activeTasks.removeAll()
        }
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidResponse
    case decodingError(Error)
    case encodingError(Error)
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Rate limit exceeded"
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Models

struct EmptyResponse: Decodable {}

struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let meta: ResponseMeta?
}

struct ResponseMeta: Decodable {
    let timestamp: Date
    let version: String
    let pagination: Pagination?
}

struct Pagination: Decodable {
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
}

// MARK: - Response Models for Loci

struct LeaderboardResponse: Decodable {
    let building: String?
    let timeRange: String
    let topArtists: [ArtistRanking]
    let topTracks: [TrackRanking]
    let topListeners: [ListenerRanking]
    let lastUpdated: Date
}

struct TrendsResponse: Decodable {
    let trends: TrendReport
    let lastUpdated: Date
}

struct MatchesResponse: Decodable {
    let matches: [Match]
    let meta: MatchesMeta
}

struct MatchesMeta: Decodable {
    let totalMatches: Int
    let newMatches: Int
    let lastChecked: Date
}
struct ListenerRanking: Codable {
    let userId: String
    let displayName: String?
    let playCount: Int
    let uniqueTracks: Int
    let favoriteGenre: String?
    let rank: Int
    let badge: String?
    let sessionModeBreakdown: [String: Int] // SessionMode breakdown as strings for API
}

struct MatchResult: Codable {
    let id: String
    let userId: String
    let matchedUserId: String
    let compatibilityScore: Double
    let sharedArtists: [String]
    let sharedGenres: [String]
    let sharedLocations: [String]
    let matchType: String // "artist", "genre", "location", "time"
    let timestamp: Date
    let isNew: Bool
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let displayName: String
    let username: String
    let email: String?
    let spotifyConnected: Bool
    let joinedDate: Date
    let totalSessions: Int
    let totalTracks: Int
    let favoriteLocations: [String]
    let topGenres: [String]
    let sessionModePreference: String?
    let privacyLevel: String
    let profileImageURL: String?
}

// MARK: - API Request Models (Updated for new session modes)

struct SessionUploadRequest: Encodable {
    let startTime: Date
    let endTime: Date
    let duration: Int // Duration in seconds
    let mode: String // SessionMode as string for API
    let events: [ListeningEventAPI]
    let buildingChanges: [BuildingChangeAPI]?
    let privacyLevel: String
}

struct ListeningEventAPI: Encodable {
    let id: String
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let buildingName: String?
    let trackName: String
    let artistName: String
    let albumName: String?
    let genre: String?
    let spotifyTrackId: String
    let sessionMode: String // SessionMode as string
}

struct BuildingChangeAPI: Encodable {
    let id: String
    let timestamp: Date
    let fromBuildingName: String?
    let toBuildingName: String
    let fromLatitude: Double?
    let fromLongitude: Double?
    let toLatitude: Double
    let toLongitude: Double
    let wasAutoDetected: Bool
}

struct EventBatchRequest: Encodable {
    let events: [ListeningEventAPI]
    let sessionId: String
    let sessionMode: String
}

struct BuildingStatsRequest: Encodable {
    let buildingName: String
    let timeRange: String
    let includeSessionModes: Bool
}

struct TrendAnalysisRequest: Encodable {
    let timeRange: String
    let includeSessionModes: Bool
    let minPlayCount: Int?
    let filterByLocation: String?
}

// MARK: - Additional Response Types

struct BuildingStatsResponse: Decodable {
    let buildingName: String
    let timeRange: String
    let totalSessions: Int
    let sessionModeBreakdown: [String: Int]
    let totalEvents: Int
    let uniqueUsers: Int
    let topTracks: [TrackRanking]
    let topArtists: [ArtistRanking]
    let topGenres: [GenreRanking]
    let peakHours: [Int]
    let averageSessionLength: Double
    let buildingCategory: String
    let lastUpdated: Date
}

struct BuildingChangeUploadRequest: Encodable {
    let sessionId: String
    let changes: [BuildingChangeAPI]
}

struct SessionModeStatsResponse: Decodable {
    let onePlace: ModeStatsAPI
    let onTheMove: ModeStatsAPI
    let totalSessions: Int
    let generatedAt: Date
}

struct ModeStatsAPI: Decodable {
    let mode: String
    let totalSessions: Int
    let totalEvents: Int
    let averageDuration: Double
    let uniqueBuildings: Int
    let topBuildings: [BuildingRankingAPI]
    let averageTracksPerSession: Double
    let buildingChanges: Int?
    let batteryEfficiencyScore: Double
}

struct BuildingRankingAPI: Decodable {
    let name: String
    let visitCount: Int
    let sessionCount: Int
    let lastVisit: Date?
}
