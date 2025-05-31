import SwiftUI

struct SessionHistoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTimeRange: HistoryTimeRange = .all
    @State private var searchText = ""
    @State private var selectedSession: Session?
    @State private var showingSessionDetail = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Time Range Filter
                    TimeRangeFilter(selectedRange: $selectedTimeRange)
                        .padding(.horizontal, LociTheme.Spacing.medium)
                        .padding(.vertical, LociTheme.Spacing.small)
                    
                    // Content
                    if filteredSessions.isEmpty {
                        EmptyHistoryView()
                    } else {
                        SessionsList(
                            sessions: filteredSessions,
                            selectedSession: $selectedSession,
                            showingDetail: $showingSessionDetail
                        )
                    }
                }
            }
            .navigationTitle("Session History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
            .sheet(isPresented: $showingSessionDetail) {
                if let session = selectedSession {
                    SessionDetailView(session: session)
                }
            }
        }
    }
    
    private var filteredSessions: [Session] {
        dataStore.sessionHistory.filter { session in
            switch selectedTimeRange {
            case .all:
                return true
            case .today:
                return Calendar.current.isDateInToday(session.startTime)
            case .thisWeek:
                return session.startTime >= Date().addingTimeInterval(-7 * 24 * 60 * 60)
            case .thisMonth:
                return session.startTime >= Date().addingTimeInterval(-30 * 24 * 60 * 60)
            }
        }
    }
}

// MARK: - Time Range Filter

enum HistoryTimeRange: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
}

struct TimeRangeFilter: View {
    @Binding var selectedRange: HistoryTimeRange
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            ForEach(HistoryTimeRange.allCases, id: \.self) { range in
                TimeRangeButton(
                    title: range.rawValue,
                    isSelected: selectedRange == range
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedRange = range
                    }
                }
            }
        }
    }
}

struct TimeRangeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LociTheme.Typography.caption)
                .foregroundColor(isSelected ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LociTheme.Spacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                        .fill(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                )
        }
    }
}

// MARK: - Empty History View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.disabledState)
            
            Text("No sessions yet")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.6))
            
            Text("Start tracking to see your music history here")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sessions List

struct SessionsList: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?
    @Binding var showingDetail: Bool
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: LociTheme.Spacing.small) {
                ForEach(sessions) { session in
                    SessionHistoryCard(session: session)
                        .onTapGesture {
                            selectedSession = session
                            showingDetail = true
                        }
                }
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.vertical, LociTheme.Spacing.medium)
        }
    }
}

// MARK: - Session History Card

struct SessionHistoryCard: View {
    let session: Session
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(session.duration.displayText)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                Spacer()
                
                // Session Mode Badge
                SessionModeBadge(mode: session.mode)
                
                // Session Score/Badge
                VStack {
                    Text("\(session.events.count)")
                        .font(LociTheme.Typography.statNumber)
                        .foregroundColor(LociTheme.Colors.mainText)
                    Text("tracks")
                        .font(.system(size: 10))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            .padding(LociTheme.Spacing.medium)
            
            LociDivider()
                .opacity(0.3)
            
            // Stats
            HStack(spacing: LociTheme.Spacing.medium) {
                SessionStatItem(
                    icon: "building.2",
                    value: "\(uniqueLocations)",
                    label: "locations"
                )
                
                Spacer()
                
                if let topArtist = topArtist {
                    SessionStatItem(
                        icon: "person.fill",
                        value: topArtist,
                        label: "top artist"
                    )
                }
                
                Spacer()
                
                if let topGenre = topGenre {
                    SessionStatItem(
                        icon: "guitars",
                        value: topGenre,
                        label: "genre"
                    )
                }
            }
            .padding(LociTheme.Spacing.medium)
        }
        .lociCard()
    }
    
    private var uniqueLocations: Int {
        Set(session.events.compactMap { $0.buildingName }).count
    }
    
    private var topArtist: String? {
        let artistCounts = Dictionary(grouping: session.events) { $0.artistName }
            .mapValues { $0.count }
        return artistCounts.max { $0.value < $1.value }?.key
    }
    
    private var topGenre: String? {
        let genreCounts = Dictionary(grouping: session.events.compactMap { $0.genre }) { $0 }
            .mapValues { $0.count }
        return genreCounts.max { $0.value < $1.value }?.key
    }
}

// MARK: - Session Stat Item

struct SessionStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xxSmall) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: Session
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: DetailTab = .overview
    @State private var showingExportMenu = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Selector
                    DetailTabSelector(selectedTab: $selectedTab)
                        .padding(.horizontal, LociTheme.Spacing.medium)
                        .padding(.vertical, LociTheme.Spacing.small)
                    
                    // Content
                    ScrollView {
                        switch selectedTab {
                        case .overview:
                            SessionOverviewTab(session: session)
                        case .tracks:
                            SessionTracksTab(session: session)
                        case .locations:
                            SessionLocationsTab(session: session)
                        case .insights:
                            SessionInsightsTab(session: session)
                        }
                    }
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingExportMenu = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
            .confirmationDialog("Export Session", isPresented: $showingExportMenu) {
                Button("Export as JSON") {
                    exportAsJSON()
                }
                Button("Export as CSV") {
                    exportAsCSV()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    private func exportAsJSON() {
        // Implementation would go here
    }
    
    private func exportAsCSV() {
        // Implementation would go here
    }
}

// MARK: - Detail Tab System

enum DetailTab: String, CaseIterable {
    case overview = "Overview"
    case tracks = "Tracks"
    case locations = "Locations"
    case insights = "Insights"
}

struct DetailTabSelector: View {
    @Binding var selectedTab: DetailTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                SessionTabButton(
                    title: tab.rawValue,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedTab = tab
                    }
                }
            }
        }
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

struct SessionTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LociTheme.Typography.caption)
                .foregroundColor(isSelected ? LociTheme.Colors.mainText : LociTheme.Colors.subheadText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LociTheme.Spacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                        .fill(isSelected ? LociTheme.Colors.cardBackground : Color.clear)
                )
        }
    }
}

// MARK: - Session Overview Tab

struct SessionOverviewTab: View {
    let session: Session
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Session Header
            SessionHeaderCard(session: session)
            
            // Quick Stats
            SessionQuickStats(session: session)
            
            // Time Distribution
            TimeDistributionCard(session: session)
            
            // Top Items
            TopItemsCard(session: session)
        }
        .padding(LociTheme.Spacing.medium)
    }
}

// MARK: - Session Header Card

struct SessionHeaderCard: View {
    let session: Session
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "music.note.house")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            Text(session.startTime.formatted(date: .complete, time: .omitted))
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(LociTheme.Spacing.large)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Session Quick Stats

struct SessionQuickStats: View {
    let session: Session
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            QuickStatCard(
                value: "\(session.events.count)",
                label: "Total Tracks",
                icon: "music.note",
                color: LociTheme.Colors.primaryAction
            )
            
            QuickStatCard(
                value: "\(uniqueTracks)",
                label: "Unique Tracks",
                icon: "star",
                color: LociTheme.Colors.secondaryHighlight
            )
            
            QuickStatCard(
                value: "\(uniqueArtists)",
                label: "Artists",
                icon: "person.2",
                color: LociTheme.Colors.notificationBadge
            )
        }
    }
    
    private var uniqueTracks: Int {
        Set(session.events.map { $0.trackName }).count
    }
    
    private var uniqueArtists: Int {
        Set(session.events.map { $0.artistName }).count
    }
}

struct QuickStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(color)
            
            Text(value)
                .font(LociTheme.Typography.statNumber)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(LociTheme.Colors.subheadText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Placeholder implementations for other tabs
// (These would be fully implemented in a real app)

struct TimeDistributionCard: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Time Distribution")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Text("Chart visualization would go here")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 100)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

struct TopItemsCard: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Top Items")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            // This would show top artists, tracks, genres
            Text("Top items list would go here")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.5))
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

struct SessionTracksTab: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Tracks list would go here")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
                .padding()
        }
    }
}

struct SessionLocationsTab: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Locations map would go here")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
                .padding()
        }
    }
}

struct SessionInsightsTab: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Session insights would go here")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
                .padding()
        }
    }
}
