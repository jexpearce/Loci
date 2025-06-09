import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class FriendsManager: ObservableObject {
    static let shared = FriendsManager()
    
    @Published var friends: [Friend] = []
    @Published var friendRequests: [FriendRequest] = []
    @Published var sentRequests: [FriendRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private var friendsListener: ListenerRegistration?
    private var requestsListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupListeners()
    }
    
    deinit {
        friendsListener?.remove()
        requestsListener?.remove()
    }
    
    // MARK: - Real-time Listeners
    
    private func setupListeners() {
        guard let userId = auth.currentUser?.uid else { return }
        
        // Listen to friends
        friendsListener = db.collection("friends")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                Task { @MainActor in
                    self.friends = documents.compactMap { document in
                        try? Firestore.Decoder().decode(Friend.self, from: document.data())
                    }
                }
            }
        
        // Listen to friend requests
        requestsListener = db.collection("friend_requests")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                Task { @MainActor in
                    self.friendRequests = documents.compactMap { document in
                        try? Firestore.Decoder().decode(FriendRequest.self, from: document.data())
                    }
                }
            }
    }
    
    // MARK: - Friend Requests
    
    func sendFriendRequest(to userId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        guard currentUserId != userId else {
            throw FriendsError.cannotAddSelf
        }
        
        // Check if already friends or request exists
        let existingConnection = try await checkExistingConnection(userId: userId)
        if existingConnection != nil {
            throw FriendsError.connectionAlreadyExists
        }
        
        isLoading = true
        
        do {
            let request = FriendRequest(
                id: UUID().uuidString,
                fromUserId: currentUserId,
                toUserId: userId,
                status: .pending,
                createdAt: Date()
            )
            
            let data = try Firestore.Encoder().encode(request)
            try await db.collection("friend_requests").document(request.id).setData(data)
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        isLoading = true
        
        do {
            // Create friendship connection
            let friendship = Friendship(
                id: UUID().uuidString,
                userId1: request.fromUserId,
                userId2: currentUserId,
                status: .accepted,
                createdAt: request.createdAt,
                acceptedAt: Date()
            )
            
            // Use batch write to ensure atomicity
            let batch = db.batch()
            
            // Add friendship
            let friendshipData = try Firestore.Encoder().encode(friendship)
            let friendshipRef = db.collection("friendships").document(friendship.id)
            batch.setData(friendshipData, forDocument: friendshipRef)
            
            // Update request status
            let requestRef = db.collection("friend_requests").document(request.id)
            batch.updateData(["status": "accepted", "acceptedAt": FieldValue.serverTimestamp()], forDocument: requestRef)
            
            // Add to both users' friends collections
            let friend1 = Friend(
                id: UUID().uuidString,
                userId: currentUserId,
                friendId: request.fromUserId,
                friendshipId: friendship.id,
                addedAt: Date()
            )
            
            let friend2 = Friend(
                id: UUID().uuidString,
                userId: request.fromUserId,
                friendId: currentUserId,
                friendshipId: friendship.id,
                addedAt: Date()
            )
            
            let friend1Data = try Firestore.Encoder().encode(friend1)
            let friend2Data = try Firestore.Encoder().encode(friend2)
            
            batch.setData(friend1Data, forDocument: db.collection("friends").document(friend1.id))
            batch.setData(friend2Data, forDocument: db.collection("friends").document(friend2.id))
            
            try await batch.commit()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func declineFriendRequest(_ request: FriendRequest) async throws {
        isLoading = true
        
        do {
            try await db.collection("friend_requests")
                .document(request.id)
                .updateData(["status": "declined"])
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Friend Management
    
    func removeFriend(_ friend: Friend) async throws {
        isLoading = true
        
        do {
            // Remove friendship and friend entries
            let batch = db.batch()
            
            // Remove friendship
            let friendshipRef = db.collection("friendships").document(friend.friendshipId)
            batch.deleteDocument(friendshipRef)
            
            // Remove friend entries for both users
            let friendRef = db.collection("friends").document(friend.id)
            batch.deleteDocument(friendRef)
            
            // Find and remove the reciprocal friend entry
            let reciprocalQuery = db.collection("friends")
                .whereField("userId", isEqualTo: friend.friendId)
                .whereField("friendId", isEqualTo: friend.userId)
            
            let reciprocalSnapshot = try await reciprocalQuery.getDocuments()
            for document in reciprocalSnapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - User Search
    
    func searchUsers(query: String) async throws -> [UserProfile] {
        guard query.count >= 2 else { return [] }
        
        let snapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: query)
            .whereField("displayName", isLessThan: query + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            try? Firestore.Decoder().decode(UserProfile.self, from: document.data())
        }
    }
    
    func searchUsersByEmail(email: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users")
            .whereField("email", isEqualTo: email.lowercased())
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else { return nil }
        return try Firestore.Decoder().decode(UserProfile.self, from: document.data())
    }
    
    func searchUsersByUsername(username: String) async throws -> UserProfile? {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "").lowercased()
        
        let snapshot = try await db.collection("users")
            .whereField("username", isEqualTo: cleanUsername)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else { return nil }
        return try Firestore.Decoder().decode(UserProfile.self, from: document.data())
    }
    
    // MARK: - Friend Activity
    
    func getFriendActivity() async throws -> [FriendActivity] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let friendIds = friends.map { $0.friendId }
        guard !friendIds.isEmpty else { return [] }
        
        // Get recent sessions from friends
        let snapshot = try await db.collection("sessions")
            .whereField("userId", in: friendIds)
            .whereField("privacyLevel", in: ["friends", "public"])
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        let activities: [FriendActivity] = try snapshot.documents.compactMap { document in
            let sessionData = document.data()
            guard let userId = sessionData["userId"] as? String,
                  let friend = friends.first(where: { $0.friendId == userId }) else {
                return nil
            }
            
            return FriendActivity(
                id: document.documentID,
                friendId: userId,
                friendName: friend.displayName ?? "Friend",
                activityType: .listeningSession,
                timestamp: (sessionData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                location: sessionData["buildingName"] as? String,
                trackName: sessionData["currentTrack"] as? String,
                artistName: sessionData["currentArtist"] as? String
            )
        }
        
        return activities.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Helper Methods
    
    private func checkExistingConnection(userId: String) async throws -> String? {
        guard let currentUserId = auth.currentUser?.uid else { return nil }
        
        // Check for existing friendship
        let friendshipQuery = db.collection("friendships")
            .whereField("userId1", in: [currentUserId, userId])
            .whereField("userId2", in: [currentUserId, userId])
        
        let friendshipSnapshot = try await friendshipQuery.getDocuments()
        if !friendshipSnapshot.documents.isEmpty {
            return "friendship"
        }
        
        // Check for pending request
        let requestQuery = db.collection("friend_requests")
            .whereField("fromUserId", in: [currentUserId, userId])
            .whereField("toUserId", in: [currentUserId, userId])
            .whereField("status", isEqualTo: "pending")
        
        let requestSnapshot = try await requestQuery.getDocuments()
        if !requestSnapshot.documents.isEmpty {
            return "request"
        }
        
        return nil
    }
    
    func isFriend(userId: String) -> Bool {
        return friends.contains { $0.friendId == userId }
    }
    
    func getFriendCount() -> Int {
        return friends.count
    }
}

// MARK: - Models

struct Friend: Codable, Identifiable {
    let id: String
    let userId: String
    let friendId: String
    let friendshipId: String
    let addedAt: Date
    var displayName: String?
    var profileImageURL: String?
    var isOnline: Bool = false
    var lastSeen: Date?
}

struct FriendRequest: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let status: RequestStatus
    let createdAt: Date
    var acceptedAt: Date?
    var fromUserName: String?
    var fromUserImageURL: String?
    
    enum RequestStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
    }
}

struct Friendship: Codable, Identifiable {
    let id: String
    let userId1: String
    let userId2: String
    let status: FriendshipStatus
    let createdAt: Date
    let acceptedAt: Date
    
    enum FriendshipStatus: String, Codable {
        case accepted = "accepted"
        case blocked = "blocked"
    }
}

struct FriendActivity: Codable, Identifiable {
    let id: String
    let friendId: String
    let friendName: String
    let activityType: ActivityType
    let timestamp: Date
    let location: String?
    let trackName: String?
    let artistName: String?
    
    enum ActivityType: String, Codable {
        case listeningSession = "listening_session"
        case newLocation = "new_location"
        case musicDiscovery = "music_discovery"
    }
}

// MARK: - Errors

enum FriendsError: Error, LocalizedError {
    case cannotAddSelf
    case connectionAlreadyExists
    case userNotFound
    case requestNotFound
    
    var errorDescription: String? {
        switch self {
        case .cannotAddSelf:
            return "You cannot add yourself as a friend"
        case .connectionAlreadyExists:
            return "Connection already exists with this user"
        case .userNotFound:
            return "User not found"
        case .requestNotFound:
            return "Friend request not found"
        }
    }
} 
