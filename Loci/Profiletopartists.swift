import SwiftUI
import Foundation

// MARK: - Profile Top Artists/Songs Component

struct ProfileTopItemsView: View {
    let userId: String?
    let isCurrentUser: Bool
    
    @State private var selectedTab: ProfileTopTab = .artists
    @State private var timeRange: ProfileTimeRange = .thisWeek
    @StateObject private var viewModel = ProfileTopItemsViewModel()
    @StateObject private var privacyManager = PrivacyManager.shared
    @StateObject private var friendsManager = FriendsManager.shared
    
    init(userId: String? = nil) {
        self.userId = userId
        self.isCurrentUser = userId == nil
    }
    
    var body: some View {
        Group {
            if canViewTopItems {
                VStack(spacing: 16) {
                    headerSection
                    tabSelector
                    contentSection
                }
                .padding(16)
                .background(cardBackground)
                .onChange(of: selectedTab) { _ in
                    Task { await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange, userId: userId) }
                }
                .onChange(of: timeRange) { _ in
                    Task { await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange, userId: userId) }
                }
                .task {
                    await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange, userId: userId)
                }
            } else {
                PrivateTopItemsView(relationshipStatus: relationshipStatus)
            }
        }
    }
    
    private var canViewTopItems: Bool {
        // Current user can always see their own
        if isCurrentUser { return true }
        
        // Check privacy settings
        guard let userId = userId else { return false }
        
        switch privacyManager.privacySettings.topItemsVisibility {
        case .everyone:
            return true
        case .friends:
            return friendsManager.isFriend(userId: userId)
        case .nobody:
            return false
        }
    }
    
    private var relationshipStatus: String {
        guard !isCurrentUser, let userId = userId else { return "" }
        
        if friendsManager.isFriend(userId: userId) {
            return "This user has made their top artists and songs private."
        } else {
            return "Add this user as a friend to see their top artists and songs."
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("Your Top \(selectedTab.rawValue)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            timeRangeMenu
        }
    }
    
    private var timeRangeMenu: some View {
        Menu {
            ForEach(ProfileTimeRange.allCases, id: \.self) { range in
                Button(range.displayName) {
                    timeRange = range
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(timeRange.displayName)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(.blue)
        }
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTopTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .background(Color.gray.opacity(0.3))
        .cornerRadius(8)
    }
    
    private func tabButton(for tab: ProfileTopTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selectedTab == tab ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? .blue : Color.clear)
                )
        }
    }
    
    private var contentSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else {
                itemsList
            }
        }
    }
    
    private var itemsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(currentItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                ProfileTopItemRow(item: item, rank: index + 1)
            }
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var currentItems: [ProfileTopItem] {
        selectedTab == .artists ? viewModel.topArtists : viewModel.topSongs
    }
}

// MARK: - Top Item Row

struct ProfileTopItemRow: View {
    let item: ProfileTopItem
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank number
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(rankColor)
                .frame(width: 20)
            
            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Play count
            Text("\(item.playCount) plays")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 6)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .gray
        }
    }
}

// MARK: - View Model

@MainActor
class ProfileTopItemsViewModel: ObservableObject {
    @Published var topArtists: [ProfileTopItem] = []
    @Published var topSongs: [ProfileTopItem] = []
    @Published var isLoading = false
    
    private let dataStore = DataStore.shared
    
    func loadTopItems(tab: ProfileTopTab, timeRange: ProfileTimeRange, userId: String? = nil) async {
        isLoading = true
        
        // Get sessions for time range - either current user or specific user
        let sessions = getSessionsForTimeRange(timeRange, userId: userId)
        
        if tab == .artists {
            topArtists = calculateTopArtists(from: sessions, userId: userId)
        } else {
            topSongs = calculateTopSongs(from: sessions, userId: userId)
        }
        
        isLoading = false
    }
    
    private func getSessionsForTimeRange(_ range: ProfileTimeRange, userId: String? = nil) -> [Session] {
        let cutoffDate: Date
        
        switch range {
        case .today:
            cutoffDate = Calendar.current.startOfDay(for: Date())
        case .thisWeek:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .thisMonth:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .allTime:
            cutoffDate = Date.distantPast
        }
        
        if let userId = userId {
            // TODO: In a real implementation, you'd fetch this user's session data from Firebase
            // For now, return empty array since we don't have other users' data locally
            return []
        } else {
            // Current user's data
            return dataStore.sessionHistory.filter { $0.startTime >= cutoffDate }
        }
    }
    
    private func calculateTopArtists(from sessions: [Session], userId: String? = nil) -> [ProfileTopItem] {
        var artistCounts: [String: Int] = [:]
        
        // Count from sessions
        for session in sessions {
            for event in session.events {
                artistCounts[event.artistName, default: 0] += 1
            }
        }
        
        // Add import data (only for current user)
        if userId == nil {
            for batch in dataStore.importBatches {
                for track in batch.tracks {
                    artistCounts[track.artist, default: 0] += 1
                }
            }
        }
        
        // Sort and convert to items
        let sortedCounts = artistCounts.sorted { $0.value > $1.value }
        let topCounts = Array(sortedCounts.prefix(10))
        
        return topCounts.map { artist, count in
            ProfileTopItem(
                id: artist,
                name: artist,
                subtitle: nil,
                playCount: count
            )
        }
    }
    
    private func calculateTopSongs(from sessions: [Session], userId: String? = nil) -> [ProfileTopItem] {
        var songData: [String: (artist: String, count: Int)] = [:]
        
        // Count from sessions
        for session in sessions {
            for event in session.events {
                let key = "\(event.trackName)___\(event.artistName)"
                if songData[key] == nil {
                    songData[key] = (artist: event.artistName, count: 0)
                }
                songData[key]?.count += 1
            }
        }
        
        // Add import data (only for current user)
        if userId == nil {
            for batch in dataStore.importBatches {
                for track in batch.tracks {
                    let key = "\(track.name)___\(track.artist)"
                    if songData[key] == nil {
                        songData[key] = (artist: track.artist, count: 0)
                    }
                    songData[key]?.count += 1
                }
            }
        }
        
        // Sort and convert to items
        let sortedSongs = songData.sorted { $0.value.count > $1.value.count }
        let topSongs = Array(sortedSongs.prefix(10))
        
        return topSongs.compactMap { key, value in
            let parts = key.split(separator: "___", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            
            return ProfileTopItem(
                id: key,
                name: String(parts[0]),
                subtitle: String(parts[1]),
                playCount: value.count
            )
        }
    }
}

// MARK: - Supporting Types

enum ProfileTopTab: String, CaseIterable {
    case artists = "Artists"
    case songs = "Songs"
}

enum ProfileTimeRange: String, CaseIterable {
    case today = "today"
    case thisWeek = "week"
    case thisMonth = "month"
    case allTime = "all"
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .allTime: return "All Time"
        }
    }
}

struct ProfileTopItem: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let playCount: Int
}

// MARK: - Private Top Items View

struct PrivateTopItemsView: View {
    let relationshipStatus: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Top Artists & Songs")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Privacy message
            VStack(spacing: 12) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                
                VStack(spacing: 8) {
                    Text("Private Content")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(relationshipStatus)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
