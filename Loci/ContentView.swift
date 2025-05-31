import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var showingSessionHistory = false
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Background
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                // Header
                HeaderView(showingSettings: $showingSettings)
                    .padding(.horizontal, LociTheme.Spacing.medium)
                    .padding(.top, LociTheme.Spacing.large)
                    .padding(.bottom, LociTheme.Spacing.medium)
                
                // Main Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: LociTheme.Spacing.large) {
                        if sessionManager.isSessionActive {
                            ActiveSessionView()
                        } else {
                            SessionModeSelectionView()
                        }
                        
                        // Status Section
                        StatusSection()
                        
                        // Recent Sessions
                        if !dataStore.sessionHistory.isEmpty {
                            RecentSessionsSection(showingSessionHistory: $showingSessionHistory)
                        }
                        
                        // Social Activity
                        SocialActivitySection()
                    }
                    .padding(.horizontal, LociTheme.Spacing.medium)
                    .padding(.bottom, LociTheme.Spacing.xxLarge)
                }
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        HStack {
            Text("Loci")
                .font(LociTheme.Typography.heading)
                .foregroundColor(LociTheme.Colors.mainText)
                .neonText()
            
            Spacer()
            
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(LociTheme.Colors.mainText)
                    .padding(LociTheme.Spacing.xSmall)
            }
        }
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingSessionDetails = false
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Live Session Dashboard
            LiveSessionDashboard()
            
            // Session Progress
            SessionProgressView()
            
            // Current Activity
            CurrentActivityCard()
            
            // Quick Actions
            SessionQuickActions(showingDetails: $showingSessionDetails)
        }
        .padding(.vertical, LociTheme.Spacing.medium)
        .sheet(isPresented: $showingSessionDetails) {
            LiveSessionDetailsView()
        }
    }
}

// MARK: - Live Session Dashboard

struct LiveSessionDashboard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var timeElapsed = ""
    @State private var timeRemaining = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Mode Badge
            HStack {
                SessionModeBadge(mode: sessionManager.sessionMode)
                Spacer()
                LiveIndicatorDot()
            }
            
            // Timer Display
            VStack(spacing: LociTheme.Spacing.xSmall) {
                Text(timeElapsed)
                    .font(LociTheme.Typography.timer)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .monospacedDigit()
                
                if let endTime = sessionManager.sessionEndTime {
                    Text("Auto-stops in \(timeRemaining)")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .monospacedDigit()
                }
            }
            
            // Session Stats Grid
            SessionStatsGrid()
        }
        .padding(LociTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .fill(LociTheme.Colors.contentContainer)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                        .stroke(modeColor.opacity(0.3), lineWidth: 1)
                )
        )
        .onReceive(timer) { _ in
            updateTimers()
        }
        .onAppear {
            updateTimers()
        }
    }
    
    private var modeColor: Color {
        switch sessionManager.sessionMode {
        case .manual: return LociTheme.Colors.primaryAction
        case .passive: return LociTheme.Colors.secondaryHighlight
        case .active: return LociTheme.Colors.notificationBadge
        case .unknown: return LociTheme.Colors.subheadText
        }
    }
    
    private func updateTimers() {
        guard let startTime = sessionManager.sessionStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        timeElapsed = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        if let endTime = sessionManager.sessionEndTime {
            let remaining = endTime.timeIntervalSince(Date())
            if remaining > 0 {
                let remainingHours = Int(remaining) / 3600
                let remainingMinutes = (Int(remaining) % 3600) / 60
                timeRemaining = String(format: "%02d:%02d", remainingHours, remainingMinutes)
            } else {
                timeRemaining = "00:00"
            }
        }
    }
}

// MARK: - Session Mode Badge

struct SessionModeBadge: View {
    let mode: SessionMode
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: modeIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LociTheme.Colors.appBackground)
            
            Text(modeTitle.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(LociTheme.Colors.appBackground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(modeColor)
        .cornerRadius(6)
    }
    
    private var modeIcon: String {
        switch mode {
        case .manual: return "map.fill"
        case .passive: return "location.square.fill"
        case .active: return "location.fill.viewfinder"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modeTitle: String {
        switch mode {
        case .manual: return "Manual"
        case .passive: return "Stay-in-Place"
        case .active: return "Live Tracking"
        case .unknown: return "Unknown"
        }
    }
    
    private var modeColor: Color {
        switch mode {
        case .manual: return LociTheme.Colors.primaryAction
        case .passive: return LociTheme.Colors.secondaryHighlight
        case .active: return LociTheme.Colors.notificationBadge
        case .unknown: return LociTheme.Colors.subheadText
        }
    }
}

// MARK: - Live Indicator Dot

struct LiveIndicatorDot: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xSmall) {
            Circle()
                .fill(LociTheme.Colors.notificationBadge)
                .frame(width: 8, height: 8)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .opacity(isAnimating ? 0.7 : 1.0)
                .animation(LociTheme.Animation.pulse, value: isAnimating)
            
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(LociTheme.Colors.notificationBadge)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Session Stats Grid

struct SessionStatsGrid: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            SessionStatCard(
                icon: "music.note",
                value: "\(dataStore.currentSessionEvents.count)",
                label: "Tracks",
                color: LociTheme.Colors.secondaryHighlight
            )
            
            SessionStatCard(
                icon: "building.2",
                value: "\(uniqueLocations)",
                label: "Places",
                color: LociTheme.Colors.primaryAction
            )
            
            SessionStatCard(
                icon: "location.circle",
                value: currentLocationStatus,
                label: "Location",
                color: locationStatusColor
            )
        }
    }
    
    private var uniqueLocations: Int {
        Set(dataStore.currentSessionEvents.compactMap { $0.buildingName }).count
    }
    
    private var currentLocationStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Active"
        default:
            return "Off"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return LociTheme.Colors.secondaryHighlight
        default:
            return LociTheme.Colors.primaryAction
        }
    }
}

// MARK: - Session Stat Card

struct SessionStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(LociTheme.Typography.statNumber)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.small)
        .background(LociTheme.Colors.appBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Session Progress View

struct SessionProgressView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Session Progress")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                if sessionManager.sessionMode == .active {
                    Text("Auto-stops at 6 hours")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(LociTheme.Colors.disabledState)
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(progressGradient)
                        .frame(width: geometry.size.width * progressPercentage, height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.3), value: progressPercentage)
                }
            }
            .frame(height: 6)
            
            // Progress milestones
            HStack {
                Text("Started")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Spacer()
                
                if dataStore.currentSessionEvents.count > 0 {
                    Text("\(dataStore.currentSessionEvents.count) tracks collected")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                Spacer()
                
                Text(progressText)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
    
    private var progressPercentage: Double {
        guard let startTime = sessionManager.sessionStartTime else { return 0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let maxDuration: TimeInterval = sessionManager.sessionMode == .active ? 6 * 3600 : 12 * 3600 // 6 hours for active, 12 for others
        
        return min(elapsed / maxDuration, 1.0)
    }
    
    private var progressGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                LociTheme.Colors.secondaryHighlight,
                LociTheme.Colors.primaryAction
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var progressText: String {
        guard let startTime = sessionManager.sessionStartTime else { return "Starting..." }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m elapsed"
        } else {
            return "\(minutes)m elapsed"
        }
    }
}

// MARK: - Current Activity Card

struct CurrentActivityCard: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("Current Activity")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            if let lastEvent = dataStore.currentSessionEvents.last {
                RecentTrackView(event: lastEvent)
            } else {
                EmptyActivityView()
            }
            
            // Location status
            LocationStatusView()
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Recent Track View

struct RecentTrackView: View {
    let event: ListeningEvent
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 32, height: 32)
                .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.trackName)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                Text(event.artistName)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .lineLimit(1)
                
                if let building = event.buildingName {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text(building)
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.primaryAction)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Text(timeAgo(from: event.timestamp))
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60
        
        if minutes < 1 {
            return "Now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "\(hours)h ago"
        }
    }
}

// MARK: - Empty Activity View

struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "music.note.list")
                .font(.system(size: 24))
                .foregroundColor(LociTheme.Colors.subheadText.opacity(0.5))
            
            Text("Waiting for music...")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Text("Start playing music on Spotify to see it appear here")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.medium)
    }
}

// MARK: - Location Status View

struct LocationStatusView: View {
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: locationIcon)
                .font(.system(size: 12))
                .foregroundColor(locationColor)
            
            Text(locationStatusText)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
            
            if locationManager.authorizationStatus != .authorizedAlways && locationManager.authorizationStatus != .authorizedWhenInUse {
                Button("Fix") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
        }
        .padding(.horizontal, LociTheme.Spacing.small)
        .padding(.vertical, LociTheme.Spacing.xSmall)
        .background(locationColor.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
    
    private var locationIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "checkmark.circle.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var locationColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return LociTheme.Colors.secondaryHighlight
        default:
            return LociTheme.Colors.primaryAction
        }
    }
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "Location tracking active"
        case .authorizedWhenInUse:
            return "Location available when app is open"
        default:
            return "Location access needed for accurate tracking"
        }
    }
}

// MARK: - Session Quick Actions

struct SessionQuickActions: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var showingDetails: Bool
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack(spacing: LociTheme.Spacing.medium) {
                Button(action: { showingDetails = true }) {
                    HStack(spacing: LociTheme.Spacing.small) {
                        Image(systemName: "chart.bar.fill")
                        Text("Details")
                    }
                }
                .lociButton(.secondary)
                
                Button(action: { sessionManager.stopSession() }) {
                    HStack(spacing: LociTheme.Spacing.small) {
                        Image(systemName: "stop.fill")
                        Text("End Session")
                    }
                }
                .lociButton(.primary, isFullWidth: true)
            }
            
            Text("Session will auto-save when stopped")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Live Session Details View

struct LiveSessionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.large) {
                    // Session overview
                    SessionOverviewCard()
                    
                    // Track list
                    if !dataStore.currentSessionEvents.isEmpty {
                        TrackListSection()
                    }
                    
                    // Location breakdown
                    if !dataStore.currentSessionEvents.isEmpty {
                        LocationBreakdownSection()
                    }
                }
                .padding(LociTheme.Spacing.medium)
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
        }
    }
}

// MARK: - Session Overview Card

struct SessionOverviewCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            Text("Session Overview")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                OverviewRow(label: "Mode", value: sessionManager.sessionMode.rawValue.capitalized)
                OverviewRow(label: "Started", value: formatTime(sessionManager.sessionStartTime))
                OverviewRow(label: "Tracks Collected", value: "\(dataStore.currentSessionEvents.count)")
                OverviewRow(label: "Unique Locations", value: "\(uniqueLocations)")
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
    
    private var uniqueLocations: Int {
        Set(dataStore.currentSessionEvents.compactMap { $0.buildingName }).count
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Overview Row

struct OverviewRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
            
            Text(value)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
        }
    }
}

// MARK: - Track List Section

struct TrackListSection: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            Text("Recent Tracks")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            LazyVStack(spacing: LociTheme.Spacing.small) {
                ForEach(dataStore.currentSessionEvents.suffix(10).reversed(), id: \.id) { event in
                    TrackRowView(event: event)
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Track Row View

struct TrackRowView: View {
    let event: ListeningEvent
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.trackName)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                Text(event.artistName)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let building = event.buildingName {
                    Text(building)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.primaryAction)
                        .lineLimit(1)
                }
                
                Text(formatTime(event.timestamp))
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
        .padding(.vertical, LociTheme.Spacing.xSmall)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Location Breakdown Section

struct LocationBreakdownSection: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            Text("Location Breakdown")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                ForEach(locationCounts.sorted(by: { $0.value > $1.value }), id: \.key) { location, count in
                    LocationBreakdownRow(location: location, count: count, total: dataStore.currentSessionEvents.count)
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
    
    private var locationCounts: [String: Int] {
        Dictionary(grouping: dataStore.currentSessionEvents.compactMap { $0.buildingName }) { $0 }
            .mapValues { $0.count }
    }
}

// MARK: - Location Breakdown Row

struct LocationBreakdownRow: View {
    let location: String
    let count: Int
    let total: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                Text("\(count) tracks")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Text("\(Int(Double(count) / Double(total) * 100))%")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.primaryAction)
        }
        .padding(.vertical, LociTheme.Spacing.xSmall)
    }
}

// MARK: - Status Section

struct StatusSection: View {
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            LociChip(
                text: spotifyManager.isAuthenticated ? "Spotify Connected" : "Connect Spotify",
                icon: spotifyManager.isAuthenticated ? "checkmark.circle" : "exclamationmark.triangle",
                isActive: spotifyManager.isAuthenticated,
                action: spotifyManager.isAuthenticated ? nil : {
                    spotifyManager.startAuthorization()
                }
            )
            
            LociChip(
                text: locationManager.authorizationStatus == .authorizedAlways ? "Location Enabled" : "Enable Location",
                icon: locationManager.authorizationStatus == .authorizedAlways ? "checkmark.circle" : "exclamationmark.triangle",
                isActive: locationManager.authorizationStatus == .authorizedAlways,
                action: locationManager.authorizationStatus == .authorizedAlways ? nil : {
                    locationManager.requestPermissions()
                }
            )
        }
    }
}

// MARK: - Recent Sessions Section

struct RecentSessionsSection: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var showingSessionHistory: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Recent Sessions")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                ForEach(dataStore.sessionHistory.prefix(2)) { session in
                    RecentSessionCard(session: session)
                }
            }
            
            Button(action: { showingSessionHistory = true }) {
                Text("View All History")
                    .font(LociTheme.Typography.buttonSmall)
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            .padding(.top, LociTheme.Spacing.xxSmall)
        }
    }
}

// MARK: - Recent Session Card

struct RecentSessionCard: View {
    let session: Session
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("\(session.events.count) tracks • \(session.duration.displayText)")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Social Activity Section

struct SocialActivitySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Nearby Activity")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            SocialActivityCard()
        }
    }
}

// MARK: - Social Activity Card

struct SocialActivityCard: View {
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Circle()
                .fill(LociTheme.Colors.notificationBadge)
                .frame(width: 8, height: 8)
                .glow(color: LociTheme.Colors.notificationBadge, radius: 4)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("3 people tracking now")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Top song in this building: 'Neon Skyline'")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.secondaryCardBackground)
    }
}

// MARK: - Settings View Placeholder

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                Text("Settings Coming Soon")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
        }
    }
}

