
import Foundation
import MediaPlayer
import Combine

// MARK: - MediaPlayer Manager

class MediaPlayerManager: NSObject, ObservableObject {
    static let shared = MediaPlayerManager()
    
    // Published properties
    @Published var currentTrack: LocalTrackInfo?
    @Published var isPlaying = false
    @Published var playbackState: MPMusicPlaybackState = .stopped
    @Published var hasMediaLibraryAccess = false
    
    // Player reference
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
    // Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // Track cache to avoid duplicate events
    private var lastTrackIdentifier: String?
    private var lastTrackChangeTime: Date?
    
    private override init() {
        super.init()
        setupNotifications()
        checkMediaLibraryAuthorization()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        // Start generating notifications
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        // Now playing item changed
        NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)
            .sink { [weak self] _ in
                self?.handleNowPlayingItemChanged()
            }
            .store(in: &cancellables)
        
        // Playback state changed
        NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)
            .sink { [weak self] _ in
                self?.handlePlaybackStateChanged()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Authorization
    
    private func checkMediaLibraryAuthorization() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            hasMediaLibraryAccess = true
        case .notDetermined:
            requestMediaLibraryAccess()
        default:
            hasMediaLibraryAccess = false
        }
    }
    
    private func requestMediaLibraryAccess() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.hasMediaLibraryAccess = (status == .authorized)
            }
        }
    }
    
    // MARK: - Current Track Polling
    
    /// Poll current track for location update
    func pollCurrentTrack() -> PartialListeningEvent? {
        guard hasMediaLibraryAccess else {
            print("❌ No media library access")
            return nil
        }
        
        guard let nowPlayingItem = musicPlayer.nowPlayingItem else {
            print("❌ No item currently playing")
            return nil
        }
        
        // Check if we've already logged this track recently
        let trackIdentifier = createTrackIdentifier(from: nowPlayingItem)
        if trackIdentifier == lastTrackIdentifier,
           let lastChange = lastTrackChangeTime,
           Date().timeIntervalSince(lastChange) < 30 { // Within 30 seconds
            print("⏭️ Skipping duplicate track event")
            return nil
        }
        
        // Extract track info
        let trackInfo = extractTrackInfo(from: nowPlayingItem)
        self.currentTrack = trackInfo
        
        // Update cache
        lastTrackIdentifier = trackIdentifier
        lastTrackChangeTime = Date()
        
        // Create partial event
        guard let location = LocationManager.shared.currentLocation else {
            print("❌ No location available for track event")
            return nil
        }
        
        let partialEvent = PartialListeningEvent(
            id: UUID(),
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            buildingName: nil, // Will be filled by geocoding
            trackName: trackInfo.title,
            artistName: trackInfo.artist,
            albumName: trackInfo.album
        )
        
        print("🎵 MediaPlayer: \(trackInfo.title) by \(trackInfo.artist)")
        
        return partialEvent
    }
    
    // MARK: - Track Info Extraction
    
    private func extractTrackInfo(from item: MPMediaItem) -> LocalTrackInfo {
        let title = item.title ?? "Unknown Track"
        let artist = item.artist ?? "Unknown Artist"
        let album = item.albumTitle ?? "Unknown Album"
        let duration = item.playbackDuration
        
        // Additional metadata
        let genre = item.genre
        let trackNumber = item.albumTrackNumber
        let releaseDate = item.releaseDate
        let artwork = item.artwork
        
        // Apple Music specific
        let isAppleMusic = item.hasProtectedAsset
        let playbackStoreID = item.playbackStoreID
        
        return LocalTrackInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            genre: genre,
            trackNumber: trackNumber,
            releaseDate: releaseDate,
            artwork: artwork,
            isAppleMusic: isAppleMusic,
            storeID: playbackStoreID != "" ? playbackStoreID : nil,
            mediaItem: item
        )
    }
    
    private func createTrackIdentifier(from item: MPMediaItem) -> String {
        // Use persistent ID if available, otherwise create from metadata
        if let persistentID = item.persistentID as? String {
            return persistentID
        }
        
        let title = item.title ?? ""
        let artist = item.artist ?? ""
        let album = item.albumTitle ?? ""
        
        return "\(title)-\(artist)-\(album)".lowercased()
    }
    
    // MARK: - Notification Handlers
    
    private func handleNowPlayingItemChanged() {
        if let item = musicPlayer.nowPlayingItem {
            let trackInfo = extractTrackInfo(from: item)
            self.currentTrack = trackInfo
            
            print("🎵 Now playing changed: \(trackInfo.title)")
        } else {
            self.currentTrack = nil
        }
    }
    
    private func handlePlaybackStateChanged() {
        self.playbackState = musicPlayer.playbackState
        self.isPlaying = musicPlayer.playbackState == .playing
        
        print("▶️ Playback state: \(playbackStateDescription)")
    }
    
    private var playbackStateDescription: String {
        switch musicPlayer.playbackState {
        case .stopped: return "Stopped"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .interrupted: return "Interrupted"
        case .seekingForward: return "Seeking Forward"
        case .seekingBackward: return "Seeking Backward"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Apple Music Integration
    
    /// Attempt to get Apple Music catalog ID for Spotify matching
    func getAppleMusicCatalogID(for item: MPMediaItem) -> String? {
        // For Apple Music tracks, we can use the playbackStoreID
        if item.hasProtectedAsset && !item.playbackStoreID.isEmpty {
            return item.playbackStoreID
        }
        
        // For local tracks, we might need to search Apple Music catalog
        // This would require MusicKit integration
        return nil
    }
    
    // MARK: - Cleanup
    
    deinit {
        musicPlayer.endGeneratingPlaybackNotifications()
    }
}

// MARK: - Supporting Types

struct LocalTrackInfo: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let genre: String?
    let trackNumber: Int
    let releaseDate: Date?
    let artwork: MPMediaItemArtwork?
    let isAppleMusic: Bool
    let storeID: String?
    let mediaItem: MPMediaItem
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var artworkImage: UIImage? {
        artwork?.image(at: CGSize(width: 300, height: 300))
    }
}

// MARK: - MediaPlayer + Spotify Matching

extension MediaPlayerManager {
    /// Create a search query for Spotify based on MediaPlayer track
    func createSpotifySearchQuery(for track: LocalTrackInfo) -> String {
        // Clean up track and artist names for better matching
        let cleanTitle = cleanTrackName(track.title)
        let cleanArtist = cleanArtistName(track.artist)
        
        // Build search query
        var query = "track:\(cleanTitle)"
        if !cleanArtist.isEmpty && cleanArtist != "Unknown Artist" {
            query += " artist:\(cleanArtist)"
        }
        
        return query
    }
    
    private func cleanTrackName(_ name: String) -> String {
        // Remove common suffixes and clean up
        var cleaned = name
        
        // Remove feat. collaborations for cleaner matching
        if let range = cleaned.range(of: " (feat.", options: .caseInsensitive) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        
        // Remove version indicators
        let versionPatterns = [" - Single Version", " - Radio Edit", " - Remastered", " (Remastered"]
        for pattern in versionPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        
        // Remove extra whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func cleanArtistName(_ name: String) -> String {
        // Remove "Various Artists" and similar
        if name.lowercased().contains("various") {
            return ""
        }
        
        // Take first artist if multiple
        if let firstArtist = name.components(separatedBy: "&").first {
            return firstArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Session Support

extension MediaPlayerManager {
    /// Get all tracks played during a time window (for session reconciliation)
    func getTracksPlayedDuring(startTime: Date, endTime: Date) -> [LocalTrackInfo] {
        // Note: MediaPlayer doesn't provide play history
        // This would need to be tracked separately if needed
        // For now, we can only get the current track
        
        if let current = currentTrack,
           let lastChange = lastTrackChangeTime,
           lastChange >= startTime && lastChange <= endTime {
            return [current]
        }
        
        return []
    }
}

// MARK: - Combine Publishers

extension MediaPlayerManager {
    /// Publisher for track changes
    var trackChangePublisher: AnyPublisher<LocalTrackInfo?, Never> {
        $currentTrack.eraseToAnyPublisher()
    }
    
    /// Publisher for playback state
    var playbackStatePublisher: AnyPublisher<MPMusicPlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
}
