import Foundation
import CryptoKit

class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()
    
    // Privacy Settings
    @Published var privacySettings: PrivacySettings
    @Published var sharingPreferences: SharingPreferences
    @Published var anonymousMode: Bool = true
    
    // User ID Management
    private var userID: String
    private var anonymousID: String
    
    // Encryption keys
    private let encryptionKey: SymmetricKey
    
    private let userDefaults = UserDefaults.standard
    private let privacySettingsKey = "com.loci.privacySettings"
    private let sharingPreferencesKey = "com.loci.sharingPreferences"
    
    private init() {
        // Initialize or load user IDs
        self.userID = Self.loadOrCreateUserID()
        self.anonymousID = Self.generateAnonymousID()
        
        // Generate or load encryption key
        self.encryptionKey = Self.loadOrCreateEncryptionKey()
        
        // Load saved settings
        self.privacySettings = Self.loadPrivacySettings()
        self.sharingPreferences = Self.loadSharingPreferences()
    }
    
    // MARK: - User ID Management
    
    private static func loadOrCreateUserID() -> String {
        if let savedID = UserDefaults.standard.string(forKey: "com.loci.userID") {
            return savedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "com.loci.userID")
            return newID
        }
    }
    
    private static func generateAnonymousID() -> String {
        // Generate a session-specific anonymous ID
        return "ANON_" + UUID().uuidString.prefix(8)
    }
    
    func regenerateAnonymousID() {
        anonymousID = Self.generateAnonymousID()
    }
    
    func getCurrentUserID() -> String {
        return anonymousMode ? anonymousID : userID
    }
    
    // MARK: - Data Anonymization
    
    func anonymizeListeningEvent(_ event: ListeningEvent) -> AnonymizedListeningEvent {
        let anonymizedLocation = anonymizeLocation(
            latitude: event.latitude,
            longitude: event.longitude,
            precision: privacySettings.locationPrecision
        )
        
        return AnonymizedListeningEvent(
            id: event.id,
            timestamp: fuzzyTimestamp(event.timestamp, precision: privacySettings.timePrecision),
            latitude: anonymizedLocation.latitude,
            longitude: anonymizedLocation.longitude,
            buildingHash: event.buildingName.map { hashBuilding($0) },
            trackName: privacySettings.shareTrackNames ? event.trackName : nil,
            artistName: privacySettings.shareArtistNames ? event.artistName : nil,
            genre: event.genre,
            userHash: hashUserID(getCurrentUserID())
        )
    }
    
    func anonymizeSession(_ session: SessionData) -> AnonymizedSessionData {
        let anonymizedEvents = session.events.map { anonymizeListeningEvent($0) }
        
        return AnonymizedSessionData(
            id: session.id,
            startTime: fuzzyTimestamp(session.startTime, precision: .hour),
            duration: session.duration,
            eventCount: anonymizedEvents.count,
            uniqueLocations: Set(anonymizedEvents.compactMap { $0.buildingHash }).count,
            topGenres: extractTopGenres(from: session.events),
            userHash: hashUserID(getCurrentUserID())
        )
    }
    
    // MARK: - Location Anonymization
    
    private func anonymizeLocation(latitude: Double, longitude: Double, precision: LocationPrecision) -> (latitude: Double, longitude: Double) {
        switch precision {
        case .exact:
            return (latitude, longitude)
        case .building:
            // Round to ~100m precision
            return (
                round(latitude * 1000) / 1000,
                round(longitude * 1000) / 1000
            )
        case .neighborhood:
            // Round to ~1km precision
            return (
                round(latitude * 100) / 100,
                round(longitude * 100) / 100
            )
        case .city:
            // Round to ~10km precision
            return (
                round(latitude * 10) / 10,
                round(longitude * 10) / 10
            )
        }
    }
    
    // MARK: - Time Anonymization
    
    private func fuzzyTimestamp(_ date: Date, precision: TimePrecision) -> Date {
        let calendar = Calendar.current
        
        switch precision {
        case .exact:
            return date
        case .minute:
            // Round to nearest minute
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return calendar.date(from: components) ?? date
        case .hour:
            // Round to nearest hour
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        case .day:
            // Start of day
            return calendar.startOfDay(for: date)
        }
    }
    
    // MARK: - Hashing
    
    private func hashUserID(_ userID: String) -> String {
        let inputData = Data(userID.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }
    
    private func hashBuilding(_ building: String) -> String {
        // Use a salted hash for buildings to prevent reverse lookups
        let salt = "loci_building_v1"
        let inputData = Data((building + salt).utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
    }
    
    // MARK: - Data Sharing Control
    
    func canShareWith(userID: String) -> Bool {
        // Check if user is blocked
        if privacySettings.blockedUsers.contains(userID) {
            return false
        }
        
        // Check sharing preferences
        switch sharingPreferences.defaultVisibility {
        case .everyone:
            return true
        case .matches:
            // Would check if userID is in matches list
            return true // Placeholder
        case .nobody:
            return false
        }
    }
    
    func shouldShareDataPoint(type: DataType) -> Bool {
        switch type {
        case .location:
            return sharingPreferences.shareLocation
        case .musicTaste:
            return sharingPreferences.shareMusic
        case .listeningPatterns:
            return sharingPreferences.sharePatterns
        case .socialConnections:
            return sharingPreferences.shareSocial
        }
    }
    
    // MARK: - Privacy Settings Management
    
    func updatePrivacySettings(_ settings: PrivacySettings) {
        privacySettings = settings
        savePrivacySettings()
    }
    
    func updateSharingPreferences(_ preferences: SharingPreferences) {
        sharingPreferences = preferences
        saveSharingPreferences()
    }
    
    func blockUser(_ userID: String) {
        privacySettings.blockedUsers.insert(userID)
        savePrivacySettings()
    }
    
    func unblockUser(_ userID: String) {
        privacySettings.blockedUsers.remove(userID)
        savePrivacySettings()
    }
    
    // MARK: - Data Export
    
    @MainActor func exportUserData() -> ExportedUserData {
        let dataStore = DataStore.shared
        
        return ExportedUserData(
            userID: userID,
            exportDate: Date(),
            sessions: dataStore.sessionHistory.map { session in
                SessionData(
                    id: session.id,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    duration: session.duration,
                    mode: session.mode,
                    events: session.events,
                    buildingChanges: session.buildingChanges,
                    isActive: session.isActive
                )
            },
            privacySettings: privacySettings,
            sharingPreferences: sharingPreferences
        )
    }
    
    @MainActor func deleteAllUserData() {
        // Clear all stored data
        DataStore.shared.clearAllData()
        
        // Reset user IDs
        userDefaults.removeObject(forKey: "com.loci.userID")
        userID = Self.loadOrCreateUserID()
        anonymousID = Self.generateAnonymousID()
        
        // Reset settings to defaults
        privacySettings = PrivacySettings()
        sharingPreferences = SharingPreferences()
        savePrivacySettings()
        saveSharingPreferences()
    }
    
    // MARK: - Encryption
    
    private static func loadOrCreateEncryptionKey() -> SymmetricKey {
        if let keyData = KeychainManager.shared.getData(for: "com.loci.encryptionKey") {
            return SymmetricKey(data: keyData)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            KeychainManager.shared.save(newKey.withUnsafeBytes { Data($0) }, for: "com.loci.encryptionKey")
            return newKey
        }
    }
    
    func encryptSensitiveData(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: encryptionKey)
        return sealed.combined ?? Data()
    }
    
    func decryptSensitiveData(_ encryptedData: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
    
    // MARK: - Persistence
    
    private func savePrivacySettings() {
        if let encoded = try? JSONEncoder().encode(privacySettings) {
            userDefaults.set(encoded, forKey: privacySettingsKey)
        }
    }
    
    private static func loadPrivacySettings() -> PrivacySettings {
        guard let data = UserDefaults.standard.data(forKey: "com.loci.privacySettings"),
              let decoded = try? JSONDecoder().decode(PrivacySettings.self, from: data) else {
            return PrivacySettings()
        }
        return decoded
    }
    
    private func saveSharingPreferences() {
        if let encoded = try? JSONEncoder().encode(sharingPreferences) {
            userDefaults.set(encoded, forKey: sharingPreferencesKey)
        }
    }
    
    private static func loadSharingPreferences() -> SharingPreferences {
        guard let data = UserDefaults.standard.data(forKey: "com.loci.sharingPreferences"),
              let decoded = try? JSONDecoder().decode(SharingPreferences.self, from: data) else {
            return SharingPreferences()
        }
        return decoded
    }
    
    // MARK: - Helper Methods
    
    private func extractTopGenres(from events: [ListeningEvent]) -> [String] {
        let genres = events.compactMap { $0.genre }
        let genreCounts = Dictionary(grouping: genres) { $0 }.mapValues { $0.count }
        return genreCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }
}

// MARK: - Keychain Manager (Simplified)

class KeychainManager {
    static let shared = KeychainManager()
    
    func save(_ data: Data, for key: String) {
        // Simplified - in production use proper Keychain wrapper
        UserDefaults.standard.set(data, forKey: "keychain.\(key)")
    }
    
    func getData(for key: String) -> Data? {
        UserDefaults.standard.data(forKey: "keychain.\(key)")
    }
}

// MARK: - Supporting Types

struct SharingPreferences: Codable {
    var defaultVisibility: Visibility = .matches
    var shareLocation: Bool = true
    var shareMusic: Bool = true
    var sharePatterns: Bool = true
    var shareSocial: Bool = false
}

enum Visibility: String, Codable, CaseIterable {
    case everyone = "Everyone"
    case matches = "Matches Only"
    case nobody = "Nobody"
}

enum DataType {
    case location
    case musicTaste
    case listeningPatterns
    case socialConnections
}

struct AnonymizedListeningEvent: Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let buildingHash: String?
    let trackName: String?
    let artistName: String?
    let genre: String?
    let userHash: String
}

struct AnonymizedSessionData: Codable {
    let id: UUID
    let startTime: Date
    let duration: SessionDuration
    let eventCount: Int
    let uniqueLocations: Int
    let topGenres: [String]
    let userHash: String
}

struct ExportedUserData: Codable {
    let userID: String
    let exportDate: Date
    let sessions: [SessionData]
    let privacySettings: PrivacySettings
    let sharingPreferences: SharingPreferences
}

// Extension to DataStore for privacy features
extension DataStore {
    func clearAllData() {
        currentSessionEvents.removeAll()
        sessionHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "com.loci.sessionHistory")
    }
}
