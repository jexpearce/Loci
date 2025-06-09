import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
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
    
    func signUp(email: String, password: String, displayName: String, username: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            // First check if username is already taken
            try await checkUsernameAvailability(username: username)
            
            let result = try await auth.createUser(withEmail: email, password: password)
            
            // Create user profile in Firestore
            let user = User(
                id: result.user.uid,
                email: email,
                displayName: displayName,
                username: username,
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
    
    private func checkUsernameAvailability(username: String) async throws {
        let query = db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        if !snapshot.documents.isEmpty {
            throw FirebaseError.usernameAlreadyTaken
        }
    }
    
    // Public method for checking username availability from other views
    func checkUsernameAvailability(username: String, excludeCurrentUser: Bool = false) async throws {
        let query = db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        if excludeCurrentUser, let currentUserId = auth.currentUser?.uid {
            // Filter out current user if excluding them
            let filteredDocs = snapshot.documents.filter { $0.documentID != currentUserId }
            if !filteredDocs.isEmpty {
                throw FirebaseError.usernameAlreadyTaken
            }
        } else if !snapshot.documents.isEmpty {
            throw FirebaseError.usernameAlreadyTaken
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
    
    // MARK: - Profile Picture Management
    
    func uploadProfilePicture(_ imageData: Data) async throws -> String {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let storage = Storage.storage()
        let imageRef = storage.reference().child("profile_pictures/\(userId).jpg")
        
        // Upload image with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await imageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await imageRef.downloadURL()
        
        // Update user profile with new image URL
        try await updateUserProfile(["profileImageURL": downloadURL.absoluteString])
        
        return downloadURL.absoluteString
    }
    
    func deleteProfilePicture() async throws {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let storage = Storage.storage()
        let imageRef = storage.reference().child("profile_pictures/\(userId).jpg")
        
        // Delete image from storage
        try await imageRef.delete()
        
        // Remove image URL from user profile
        try await updateUserProfile(["profileImageURL": FieldValue.delete()])
    }
    
    // MARK: - Session Management
    
    func saveSession(_ session: Session) async throws {
        guard let userId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let firebaseSession = FirebaseSession(from: session, userId: userId)
        var sessionData = try Firestore.Encoder().encode(firebaseSession)
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
            let firebaseSession = try Firestore.Decoder().decode(FirebaseSession.self, from: document.data())
            return firebaseSession.toSession()
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
                    "latitude": session.location?.latitude ?? 0,
                    "longitude": session.location?.longitude ?? 0,
                    "lastActivity": FieldValue.serverTimestamp()
                ]
                
                if document.exists {
                    // Update existing activity
                    let currentListeners = document.data()?["activeUsers"] as? Int ?? 0
                    data["activeUsers"] = currentListeners + 1
                    
                    // Add current tracks
                    if let currentEvent = session.events.last {
                        var currentTracks = document.data()?["currentTracks"] as? [[String: Any]] ?? []
                        let trackData: [String: Any] = [
                            "id": UUID().uuidString,
                            "name": currentEvent.trackName,
                            "artist": currentEvent.artistName,
                            "album": currentEvent.albumName ?? "",
                            "spotifyId": currentEvent.spotifyTrackId,
                            "playCount": 1,
                            "timestamp": FieldValue.serverTimestamp()
                        ]
                        currentTracks.append(trackData)
                        
                        // Keep only last 10 tracks
                        if currentTracks.count > 10 {
                            currentTracks = Array(currentTracks.suffix(10))
                        }
                        data["currentTracks"] = currentTracks
                    }
                    
                    transaction.updateData(data, forDocument: buildingRef)
                } else {
                    // Create new activity
                    data["activeUsers"] = 1
                    data["currentTracks"] = []
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

// MARK: - Firebase-Compatible Models

// Firebase-compatible Session struct for encoding/decoding
struct FirebaseSession: Codable {
    let id: String
    let startTime: Date
    let endTime: Date
    let duration: String
    let mode: SessionMode
    let events: [FirebaseListeningEvent]
    let userId: String?
    let createdAt: Date?
    let privacyLevel: SessionPrivacyLevel
    
    init(from session: Session, userId: String? = nil) {
        self.id = session.id.uuidString
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.duration = session.duration.rawValue
        self.mode = session.mode
        self.events = session.events.map { FirebaseListeningEvent(from: $0) }
        self.userId = userId
        self.createdAt = nil // Will be set by Firestore
        self.privacyLevel = session.privacyLevel
    }
    
    func toSession() -> Session {
        let session = Session(
            startTime: startTime,
            endTime: endTime,
            duration: SessionDuration(rawValue: duration) ?? .twelveHours,
            mode: mode,
            events: events.map { $0.toListeningEvent() }
        )
        session.id = UUID(uuidString: id) ?? UUID()
        return session
    }
}

// Firebase-compatible ListeningEvent struct
struct FirebaseListeningEvent: Codable {
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
    
    init(from event: ListeningEvent) {
        self.id = event.id.uuidString
        self.timestamp = event.timestamp
        self.latitude = event.latitude
        self.longitude = event.longitude
        self.buildingName = event.buildingName
        self.trackName = event.trackName
        self.artistName = event.artistName
        self.albumName = event.albumName
        self.genre = event.genre
        self.spotifyTrackId = event.spotifyTrackId
    }
    
    func toListeningEvent() -> ListeningEvent {
        let event = ListeningEvent(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            buildingName: buildingName,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            genre: genre,
            spotifyTrackId: spotifyTrackId
        )
                event.id = UUID(uuidString: id) ?? UUID()
        return event
    }
} 