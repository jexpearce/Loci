import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class MatchingManager: ObservableObject {
    static let shared = MatchingManager()
    
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var currentFilters = MatchFilters()
    @Published var userPreferences = MatchPreferences()
    
    private let matchingEngine = MatchingEngine.shared
    private let firebaseManager = FirebaseManager.shared
    private let analyticsEngine = AnalyticsEngine.shared
    
    private var matchListener: ListenerRegistration?
    
    private init() {
        setupMatchListener()
    }
    
    deinit {
        matchListener?.remove()
    }
    
    // MARK: - Public Methods
    
    func refreshMatches() {
        Task {
            await findMatches()
        }
    }
    
    func updateFilters(_ filters: MatchFilters) {
        currentFilters = filters
        refreshMatches()
    }
    
    func updatePreferences(_ preferences: MatchPreferences) {
        userPreferences = preferences
        // Re-rank existing matches with new preferences
        matches = matchingEngine.rankMatches(matches, preferences: preferences)
    }
    
    // MARK: - Private Methods
    
    private func setupMatchListener() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Listen for new matches in real-time
        matchListener = Firestore.firestore()
            .collection("matches")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error listening to matches: \(error)")
                    return
                }
                
                // Process new matches
                self?.processMatchUpdates(snapshot?.documents ?? [])
            }
    }
    
    private func processMatchUpdates(_ documents: [QueryDocumentSnapshot]) {
        let newMatches = documents.compactMap { doc -> Match? in
            try? doc.data(as: Match.self)
        }
        
        DispatchQueue.main.async {
            // Merge with existing matches, avoiding duplicates
            let existingIds = Set(self.matches.map { $0.userId })
            let uniqueNewMatches = newMatches.filter { !existingIds.contains($0.userId) }
            
            self.matches.append(contentsOf: uniqueNewMatches)
            self.matches = self.matchingEngine.rankMatches(self.matches, preferences: self.userPreferences)
        }
    }
    
    @MainActor
    private func findMatches() async {
        isLoading = true
        
        do {
            // Get user's listening fingerprint
            guard let userFingerprint = await getUserListeningFingerprint() else {
                isLoading = false
                return
            }
            
            // Get candidate fingerprints from nearby users
            let candidates = await getCandidateFingerprints()
            
            // Find matches using the matching engine
            let newMatches = matchingEngine.findMatches(
                for: userFingerprint,
                from: candidates,
                filters: currentFilters
            )
            
            // Rank matches based on user preferences
            let rankedMatches = matchingEngine.rankMatches(newMatches, preferences: userPreferences)
            
            // Update UI
            matches = rankedMatches
            
            // Save matches to Firebase for persistence
            await saveMatchesToFirebase(rankedMatches)
            
        } catch {
            print("❌ Error finding matches: \(error)")
        }
        
        isLoading = false
    }
    
    private func getUserListeningFingerprint() async -> ListeningFingerprint? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        // Get user's session data from data store
        let userSessions = await DataStore.shared.sessionHistory
        
        // Create listening fingerprint from session data
        return createListeningFingerprint(from: userSessions, userId: UUID(uuidString: userId) ?? UUID())
    }
    
    private func getCandidateFingerprints() async -> [ListeningFingerprint] {
        // Get other users' anonymized listening data
        // This would be implemented to fetch from Firebase while preserving privacy
        
        // For now, return mock data for testing
        return createMockCandidates()
    }
    
    private func createListeningFingerprint(from sessions: [Session], userId: UUID) -> ListeningFingerprint {
        // Extract all listening events from sessions
        let allEvents = sessions.flatMap { $0.events }
        
        // Create vectors for matching
        let artistVector = createArtistVector(from: allEvents)
        let genreVector = createGenreVector(from: allEvents)
        let locationVector = createLocationVector(from: sessions)
        let timeVector = createTimeVector(from: allEvents)
        
        // Calculate diversity score
        let diversityScore = calculateDiversityScore(from: allEvents)
        
        return ListeningFingerprint(
            id: userId,
            artistVector: artistVector,
            genreVector: genreVector,
            locationVector: locationVector,
            timeVector: timeVector,
            diversityScore: diversityScore,
            totalEvents: allEvents.count,
            createdAt: Date()
        )
    }
    
    private func createArtistVector(from events: [ListeningEvent]) -> [Double] {
        // Create a vector representing artist preferences
        let artistCounts = Dictionary(grouping: events, by: { $0.artistName })
            .mapValues { $0.count }
        
        // Convert to normalized vector (simplified implementation)
        let topArtists = Array(artistCounts.sorted { $0.value > $1.value }.prefix(50))
        return topArtists.map { Double($0.value) / Double(events.count) }
    }
    
    private func createGenreVector(from events: [ListeningEvent]) -> [Double] {
        // Create a vector representing genre preferences
        // This would use Spotify's genre data for each track
        // For now, return a mock vector
        return Array(repeating: 0.1, count: 20)
    }
    
    private func createLocationVector(from sessions: [Session]) -> [Double] {
        // Create a vector representing location patterns
        let locationCounts = Dictionary(grouping: sessions, by: { $0.location?.building ?? "Unknown" })
            .mapValues { $0.count }
        
        let topLocations = Array(locationCounts.sorted { $0.value > $1.value }.prefix(20))
        return topLocations.map { Double($0.value) / Double(sessions.count) }
    }
    
    private func createTimeVector(from events: [ListeningEvent]) -> [Double] {
        // Create a vector representing listening time patterns
        let hourCounts = Dictionary(grouping: events, by: { Calendar.current.component(.hour, from: $0.timestamp) })
            .mapValues { $0.count }
        
        // Create 24-hour vector
        return (0..<24).map { hour in
            Double(hourCounts[hour] ?? 0) / Double(events.count)
        }
    }
    
    private func calculateDiversityScore(from events: [ListeningEvent]) -> Double {
        // Calculate how diverse the user's music taste is
        let uniqueArtists = Set(events.map { $0.artistName }).count
        let totalEvents = events.count
        
        guard totalEvents > 0 else { return 0 }
        
        return min(Double(uniqueArtists) / Double(totalEvents), 1.0)
    }
    
    private func saveMatchesToFirebase(_ matches: [Match]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let batch = db.batch()
        
        for match in matches {
            let matchData: [String: Any] = [
                "userId": userId,
                "matchUserId": match.userId.uuidString,
                "score": [
                    "overall": match.score.overall,
                    "musicTaste": match.score.musicTaste,
                    "locationOverlap": match.score.locationOverlap,
                    "timeAlignment": match.score.timeAlignment,
                    "diversityMatch": match.score.diversityMatch
                ],
                "matchType": match.matchType.rawValue,
                "sharedInterests": [
                    "topSharedArtists": match.sharedInterests.topSharedArtists,
                    "topSharedGenres": match.sharedInterests.topSharedGenres,
                    "sharedListeningTimes": match.sharedInterests.sharedListeningTimes.map { $0.rawValue },
                    "sharedLocations": match.sharedInterests.sharedLocations
                ],
                "timestamp": match.timestamp,
                "createdAt": FieldValue.serverTimestamp()
            ]
            
            let docRef = db.collection("matches").document()
            batch.setData(matchData, forDocument: docRef)
        }
        
        do {
            try await batch.commit()
            print("✅ Matches saved to Firebase")
        } catch {
            print("❌ Error saving matches: \(error)")
        }
    }
    
    // MARK: - Mock Data for Testing
    
    private func createMockCandidates() -> [ListeningFingerprint] {
        return [
            ListeningFingerprint(
                id: UUID(),
                artistVector: [0.3, 0.2, 0.15, 0.1, 0.08],
                genreVector: Array(repeating: 0.05, count: 20),
                locationVector: [0.4, 0.3, 0.2, 0.1],
                timeVector: Array(repeating: 0.04, count: 24),
                diversityScore: 0.7,
                totalEvents: 150,
                createdAt: Date()
            ),
            ListeningFingerprint(
                id: UUID(),
                artistVector: [0.25, 0.2, 0.18, 0.12, 0.1],
                genreVector: Array(repeating: 0.05, count: 20),
                locationVector: [0.5, 0.25, 0.15, 0.1],
                timeVector: Array(repeating: 0.04, count: 24),
                diversityScore: 0.8,
                totalEvents: 200,
                createdAt: Date()
            )
        ]
    }
}

// MARK: - Supporting Types




// MARK: - Extensions

extension Match: Identifiable {
    var id: UUID { userId }
}
