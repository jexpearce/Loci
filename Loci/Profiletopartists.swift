import SwiftUI

// MARK: - Profile Top Artists/Songs Component

struct ProfileTopItemsView: View {
    @State private var selectedTab: ProfileTopTab = .artists
    @State private var timeRange: ProfileTimeRange = .thisWeek
    @StateObject private var viewModel = ProfileTopItemsViewModel()
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Header with time range
            HStack {
                Text("Your Top \(selectedTab.rawValue)")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
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
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
            
            // Tab selector
            HStack(spacing: 0) {
                ForEach(ProfileTopTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedTab == tab ? .white : LociTheme.Colors.subheadText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? LociTheme.Colors.primaryAction : Color.clear)
                            )
                    }
                }
            }
            .background(LociTheme.Colors.disabledState.opacity(0.3))
            .cornerRadius(8)
            
            // Content
            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(currentItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                        ProfileTopItemRow(item: item, rank: index + 1)
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
        .onChange(of: selectedTab) { _ in
            Task { await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange) }
        }
        .onChange(of: timeRange) { _ in
            Task { await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange) }
        }
        .task {
            await viewModel.loadTopItems(tab: selectedTab, timeRange: timeRange)
        }
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
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Play count
            Text("\(item.playCount) plays")
                .font(.system(size: 11))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .padding(.vertical, 6)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return LociTheme.Colors.subheadText
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
    
    func loadTopItems(tab: ProfileTopTab, timeRange: ProfileTimeRange) async {
        isLoading = true
        
        // Get sessions for time range
        let sessions = getSessionsForTimeRange(timeRange)
        
        if tab == .artists {
            topArtists = calculateTopArtists(from: sessions)
        } else {
            topSongs = calculateTopSongs(from: sessions)
        }
        
        isLoading = false
    }
    
    private func getSessionsForTimeRange(_ range: ProfileTimeRange) -> [Session] {
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
        
        return dataStore.sessionHistory.filter { $0.startTime >= cutoffDate }
    }
    
    private func calculateTopArtists(from sessions: [Session]) -> [ProfileTopItem] {
        var artistCounts: [String: Int] = [:]
        
        // Count from sessions
        for session in sessions {
            for event in session.events {
                artistCounts[event.artistName, default: 0] += 1
            }
        }
        
        // Add import data
        for batch in dataStore.importBatches {
            for track in batch.tracks {
                artistCounts[track.artist, default: 0] += 1
            }
        }
        
        // Sort and convert to items
        return artistCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { artist, count in
                ProfileTopItem(
                    id: artist,
                    name: artist,
                    subtitle: nil,
                    playCount: count
                )
            }
    }
    
    private func calculateTopSongs(from sessions: [Session]) -> [ProfileTopItem] {
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
        
        // Add import data
        for batch in dataStore.importBatches {
            for track in batch.tracks {
                let key = "\(track.name)___\(track.artist)"
                if songData[key] == nil {
                    songData[key] = (artist: track.artist, count: 0)
                }
                songData[key]?.count += 1
            }
        }
        
        // Sort and convert to items
        return songData
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .compactMap { key, value in
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
