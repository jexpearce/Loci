import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import Combine

@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Authentication
    
    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isAuthenticated = user != nil
                if let user = user {
                    await self?.loadUserProfile(userId: user.uid)
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }
    
    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            
            // Create user profile in Firestore
            let user = User(
                id: result.user.uid,
                email: email,
                displayName: displayName,
                spotifyUserId: nil,
                profileImageURL: nil,
                joinedDate: Date(),
                privacySettings: PrivacySettings(),
                musicPreferences: MusicPreferences()
            )
            
            try await saveUserProfile(user: user)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            try await auth.signIn(withEmail: email, password: password)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func signOut() throws {
        try auth.signOut()
        currentUser = nil
    }
    
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }
    
    // MARK: - User Profile Management
    
    private func loadUserProfile(userId: String) async {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let data = document.data() {
                currentUser = try Firestore.Decoder().decode(User.self, from: data)
            }
        } catch {
            print("Error loading user profile: \(error)")
            errorMessage = "Failed to load user profile"
        }
    }
    
    func saveUserProfile(user: User) async throws {
        let data = try Firestore.Encoder().encode(user)
        try await db.collection("users").document(user.id).setData(data)
        currentUser = user
    }
    
    func updateUserProfile(_ updates: [String: Any]) async throws {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        try await db.collection("users").document(userId).updateData(updates)
        await loadUserProfile(userId: userId)
    }
    
    // MARK: - Session Management
    
    func saveSession(_ session: Session) async throws {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        var sessionData = try Firestore.Encoder().encode(session)
        sessionData["userId"] = userId
        sessionData["createdAt"] = FieldValue.serverTimestamp()
        
        try await db.collection("sessions").document(session.id.uuidString).setData(sessionData)
        
        // Update building activity if session is public
        if session.privacyLevel == .public {
            await updateBuildingActivity(for: session)
        }
    }
    
    func loadUserSessions(limit: Int = 50) async throws -> [Session] {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let query = db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { document in
            try Firestore.Decoder().decode(Session.self, from: document.data())
        }
    }
    
    // MARK: - Location-Based Discovery
    
    func getNearbyActivity(location: CLLocation, radius: Double = 1000) async throws -> [BuildingActivity] {
        // For now, we'll use a simple bounding box query
        // In production, you'd want to use GeoFirestore for proper geospatial queries
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let latDelta = radius / 111000 // Rough conversion: 1 degree ≈ 111km
        let lonDelta = radius / (111000 * cos(lat * .pi / 180))
        
        let query = db.collection("building_activity")
            .whereField("latitude", isGreaterThan: lat - latDelta)
            .whereField("latitude", isLessThan: lat + latDelta)
            .whereField("longitude", isGreaterThan: lon - lonDelta)
            .whereField("longitude", isLessThan: lon + lonDelta)
            .whereField("lastActivity", isGreaterThan: Date().addingTimeInterval(-3600)) // Last hour
        
        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { document in
            try Firestore.Decoder().decode(BuildingActivity.self, from: document.data())
        }
    }
    
    private func updateBuildingActivity(for session: Session) async {
        guard let building = session.location?.building else { return }
        
        let buildingId = building.replacingOccurrences(of: " ", with: "_").lowercased()
        let buildingRef = db.collection("building_activity").document(buildingId)
        
        do {
            try await db.runTransaction { transaction, errorPointer in
                let document: DocumentSnapshot
                do {
                    document = try transaction.getDocument(buildingRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                var data: [String: Any] = [
                    "buildingName": building,
                    "latitude": session.location?.coordinate.latitude ?? 0,
                    "longitude": session.location?.coordinate.longitude ?? 0,
                    "lastActivity": FieldValue.serverTimestamp()
                ]
                
                if document.exists {
                    // Update existing activity
                    let currentListeners = document.data()?["currentListeners"] as? Int ?? 0
                    data["currentListeners"] = currentListeners + 1
                    
                    // Add current tracks
                    if let currentTrack = session.tracks.last {
                        var recentTracks = document.data()?["recentTracks"] as? [[String: Any]] ?? []
                        let trackData: [String: Any] = [
                            "name": currentTrack.name,
                            "artist": currentTrack.artist,
                            "timestamp": FieldValue.serverTimestamp()
                        ]
                        recentTracks.append(trackData)
                        
                        // Keep only last 10 tracks
                        if recentTracks.count > 10 {
                            recentTracks = Array(recentTracks.suffix(10))
                        }
                        data["recentTracks"] = recentTracks
                    }
                    
                    transaction.updateData(data, forDocument: buildingRef)
                } else {
                    // Create new activity
                    data["currentListeners"] = 1
                    data["recentTracks"] = []
                    transaction.setData(data, forDocument: buildingRef)
                }
                
                return nil
            }
        } catch {
            print("Error updating building activity: \(error)")
        }
    }
    
    // MARK: - Real-time Listeners
    
    func listenToNearbyActivity(location: CLLocation, radius: Double = 1000, completion: @escaping ([BuildingActivity]) -> Void) -> ListenerRegistration {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let latDelta = radius / 111000
        let lonDelta = radius / (111000 * cos(lat * .pi / 180))
        
        return db.collection("building_activity")
            .whereField("latitude", isGreaterThan: lat - latDelta)
            .whereField("latitude", isLessThan: lat + latDelta)
            .whereField("longitude", isGreaterThan: lon - lonDelta)
            .whereField("longitude", isLessThan: lon + lonDelta)
            .whereField("lastActivity", isGreaterThan: Date().addingTimeInterval(-3600))
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching nearby activity: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                let activities = documents.compactMap { document in
                    try? Firestore.Decoder().decode(BuildingActivity.self, from: document.data())
                }
                
                completion(activities)
            }
    }
}

// MARK: - Supporting Models

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let spotifyUserId: String?
    let profileImageURL: String?
    let joinedDate: Date
    let privacySettings: PrivacySettings
    let musicPreferences: MusicPreferences
}

struct PrivacySettings: Codable {
    var shareLocation: Bool = true
    var shareListening: Bool = true
    var allowDiscovery: Bool = true
    var shareProfile: Bool = true
}

struct MusicPreferences: Codable {
    var favoriteGenres: [String] = []
    var favoriteArtists: [String] = []
    var discoveryRadius: Double = 1000 // meters
}

struct BuildingActivity: Codable, Identifiable {
    let id: String
    let buildingName: String
    let latitude: Double
    let longitude: Double
    let currentListeners: Int
    let recentTracks: [RecentTrack]
    let lastActivity: Date
}

struct RecentTrack: Codable {
    let name: String
    let artist: String
    let timestamp: Date
}

enum FirebaseError: Error, LocalizedError {
    case notAuthenticated
    case invalidData
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidData:
            return "Invalid data format"
        case .networkError:
            return "Network error occurred"
        }
    }
}

// MARK: - Session Privacy Extension

extension Session {
    enum PrivacyLevel: String, Codable, CaseIterable {
        case `private` = "private"
        case friends = "friends"
        case `public` = "public"
        
        var displayName: String {
            switch self {
            case .private: return "Private"
            case .friends: return "Friends Only"
            case .public: return "Public"
            }
        }
    }
    
    var privacyLevel: PrivacyLevel {
        get {
            // Default to private for existing sessions
            return PrivacyLevel(rawValue: self.metadata["privacyLevel"] as? String ?? "private") ?? .private
        }
        set {
            self.metadata["privacyLevel"] = newValue.rawValue
        }
    }
} 
