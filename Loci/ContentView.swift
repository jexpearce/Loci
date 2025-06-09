import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @State private var showingSessionHistory = false
    @State private var showingSettings = false
    @State private var showingSpotifyImport = false
    @State private var showingLocationChangeAlert = false
    @State private var detectedBuildingChange: BuildingChange?
    
    var body: some View {
        ZStack {
            // Background
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                // Header (Updated with import button)
                HeaderView(
                    showingSettings: $showingSettings,
                    showingSpotifyImport: $showingSpotifyImport,
                    showingSessionHistory: $showingSessionHistory
                )
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.top, LociTheme.Spacing.large)
                .padding(.bottom, LociTheme.Spacing.medium)
                
                // Main Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: LociTheme.Spacing.large) {
                        if sessionManager.isSessionActive {
                            // Show active session (mode-specific)
                            ActiveSessionView()
                        } else {
                            // Location Selection Section
                            LocationSelectionSection()
                            
                            // NEW: Primary Spotify Import Flow
                            SpotifyImportMainView()
                            
                            // MOVED: Session modes now secondary
                            AdvancedSessionOptionsView()
                        }
                        
                        // Status Section (keep existing)
                        StatusSection()
                        
                        // Recent Sessions (keep existing)
                        if !dataStore.sessionHistory.isEmpty {
                            RecentSessionsSection(showingSessionHistory: $showingSessionHistory)
                        }
                        
                        // Social Activity (keep existing)
                        // Leaderboards (NEW - replaces regional discovery)
                        LeaderboardPreviewSection()
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
                .environmentObject(spotifyManager)
                .environmentObject(dataStore)
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingSpotifyImport) {
            SpotifyImportView()
                .environmentObject(spotifyManager)
                .environmentObject(locationManager)
                .environmentObject(dataStore)
                .environmentObject(ReverseGeocoding.shared)
        }
        .alert("Location Changed", isPresented: $showingLocationChangeAlert) {
            Button("Got it") {
                showingLocationChangeAlert = false
            }
        } message: {
            if let change = detectedBuildingChange {
                Text("You've moved to \(change.toBuildingName). Your music will now be tracked here.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .buildingChangeDetected)) { notification in
            if let change = notification.object as? BuildingChange {
                detectedBuildingChange = change
                showingLocationChangeAlert = true
            }
        }
        .onAppear {
            // Trigger initial leaderboard sync if user has consented
            Task {
                await LeaderboardManager.shared.autoSyncUserDataIfNeeded()
            }
        }
    }
}
// MARK: - Header View
struct HeaderView: View {
    @Binding var showingSettings: Bool
    @Binding var showingSpotifyImport: Bool
    @Binding var showingSessionHistory: Bool
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("Loci")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .neonText()
                
                // Show session status if active
                if sessionManager.isSessionActive {
                    Text("\(sessionManager.sessionMode.displayName) Session")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(sessionManager.sessionMode == .onePlace ?
                                       LociTheme.Colors.secondaryHighlight :
                                       LociTheme.Colors.primaryAction)
                }
            }
            
            Spacer()
            
            HStack(spacing: LociTheme.Spacing.small) {
                // NEW: Spotify Import Button
                Button(action: { showingSpotifyImport = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        .padding(LociTheme.Spacing.xSmall)
                }
                
                // History Button
                Button(action: { showingSessionHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .padding(LociTheme.Spacing.xSmall)
                }
                
                // Settings Button (keep existing)
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(LociTheme.Colors.mainText)
                        .padding(LociTheme.Spacing.xSmall)
                }
            }
        }
    }
}
struct OnTheMoveActiveDashboard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var timeElapsed = ""
    @State private var timeRemaining = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Mode Badge
            HStack {
                SessionModeBadge(mode: .onTheMove)
                Spacer()
                LiveIndicatorDot()
            }
            
            // Timer Display
            VStack(spacing: LociTheme.Spacing.xSmall) {
                Text(timeElapsed)
                    .font(LociTheme.Typography.timer)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .monospacedDigit()
                
                if !timeRemaining.isEmpty {
                    Text("Stops in \(timeRemaining)")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .monospacedDigit()
                }
            }
            
            // Session Stats
            OnTheMoveStatsGrid()
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
        .onReceive(timer) { _ in
            updateTimers()
        }
        .onAppear {
            updateTimers()
        }
    }
    
    private func updateTimers() {
        if let elapsed = sessionManager.getSessionElapsed() {
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            let seconds = Int(elapsed) % 60
            timeElapsed = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        if let remaining = sessionManager.getSessionTimeRemaining() {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            timeRemaining = String(format: "%02d:%02d", hours, minutes)
        } else {
            timeRemaining = ""
        }
    }
}
struct OnePlaceActiveDashboard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Mode Badge
            HStack {
                SessionModeBadge(mode: .onePlace)
                Spacer()
                LiveIndicatorDot()
            }
            
            // Current Building
            VStack(spacing: LociTheme.Spacing.small) {
                if let building = sessionManager.currentBuilding {
                    Text(building)
                        .font(LociTheme.Typography.timer)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Getting location...")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                if sessionManager.hasDetectedLocationChange {
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        
                        Text("Location updated")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
            
            // Session Stats
            OnePlaceStatsGrid()
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}


// MARK: - Active Session View

struct ActiveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var showingSessionDetails = false
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Mode-specific dashboard
            Group {
                switch sessionManager.sessionMode {
                case .onePlace:
                    OnePlaceActiveDashboard()
                case .onTheMove:
                    OnTheMoveActiveDashboard()
                case .unknown:
                    UnknownSessionDashboard()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: sessionManager.sessionMode == .onePlace ? .leading : .trailing).combined(with: .opacity),
                removal: .move(edge: sessionManager.sessionMode == .onePlace ? .trailing : .leading).combined(with: .opacity)
            ))
            
            // Current Activity (shared)
            CurrentActivityCard()
            
            // Quick Actions
            SessionQuickActions(showingDetails: $showingSessionDetails)
        }
        .sheet(isPresented: $showingSessionDetails) {
            LiveSessionDetailsView()
        }
    }
}
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.subheadText)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
    }
}


// MARK: - Live Indicator Dot

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
        case .onePlace: return "location.square.fill"
        case .onTheMove: return "location.fill.viewfinder"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modeTitle: String {
        switch mode {
        case .onePlace: return "One-Place"
        case .onTheMove: return "On-the-Move"
        case .unknown: return "Unknown"
        }
    }
    
    private var modeColor: Color {
        switch mode {
        case .onePlace: return LociTheme.Colors.secondaryHighlight
        case .onTheMove: return LociTheme.Colors.primaryAction
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
                
                if sessionManager.sessionMode == .onTheMove {
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
        let maxDuration: TimeInterval = sessionManager.sessionMode == .onTheMove ? 6 * 3600 : 12 * 3600 // 6 hours for on-the-move, 12 for one-place
        
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


// MARK: - Recent Track View

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

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var privacyManager = PrivacyManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingPrivacyExplanation = false
    @State private var showingDataExportSheet = false
    @State private var showingLeaderboardConsent = false
    @State private var notificationsEnabled = false
    
    var body: some View {
        NavigationView {
            ZStack {
                settingsBackground
                
                ScrollView {
                    VStack(spacing: 24) {
                        accountSection
                        privacySection
                        notificationsSection
                        dataManagementSection
                        aboutSection
                        signOutButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            checkNotificationStatus()
        }
    }
    
    // MARK: - Settings Sections
    
    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.1),
                Color(red: 0.1, green: 0.05, blue: 0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var accountSection: some View {
        SettingsSection(title: "Account") {
            SettingsRow(
                icon: "person.circle",
                title: "Account Info",
                subtitle: "\(firebaseManager.currentUser?.username ?? ""), \(firebaseManager.currentUser?.email ?? "Not signed in")",
                action: {}
            )
            
            if spotifyManager.isAuthenticated {
                SettingsRow(
                    icon: "music.note",
                    title: "Spotify Connected",
                    subtitle: "Disconnect to stop music tracking",
                    action: { 
                        // Properly sign out of Spotify
                        spotifyManager.signOut()
                    }
                )
            } else {
                SettingsRow(
                    icon: "music.note",
                    title: "Connect Spotify",
                    subtitle: "Enable music tracking",
                    action: { spotifyManager.startAuthorization() }
                )
            }
        }
    }
    
    private var privacySection: some View {
        SettingsSection(title: "Privacy & Data") {
            // Leaderboard Privacy
            SettingsRow(
                icon: "chart.bar.xaxis",
                title: "Leaderboard Privacy",
                subtitle: leaderboardPrivacySubtitle,
                action: { showingLeaderboardConsent = true }
            )
            
            SettingsToggleRow(
                icon: "location",
                title: "Share Location",
                subtitle: "Allow others to see your general area",
                isOn: $privacyManager.privacySettings.shareLocation
            )
            
            SettingsToggleRow(
                icon: "music.note",
                title: "Share Listening Activity",
                subtitle: "Show what you're listening to",
                isOn: $privacyManager.privacySettings.shareListeningActivity
            )
            
            SettingsToggleRow(
                icon: "person.2",
                title: "Allow Friend Requests",
                subtitle: "Let others send you friend requests",
                isOn: $privacyManager.privacySettings.allowFriendRequests
            )
            
            SettingsToggleRow(
                icon: "eye",
                title: "Show Online Status",
                subtitle: "Let friends see when you're active",
                isOn: $privacyManager.privacySettings.showOnlineStatus
            )
            
            // Top Items Visibility Setting
            SettingsPickerRow(
                icon: "music.note.list",
                title: "Top Artists & Songs",
                subtitle: "Who can see your top music",
                selection: $privacyManager.privacySettings.topItemsVisibility
            )
            
            SettingsRow(
                icon: "shield",
                title: "Privacy Explanation",
                subtitle: "How we protect your data",
                action: { showingPrivacyExplanation = true }
            )
        }
    }
    
    private var notificationsSection: some View {
        SettingsSection(title: "Notifications") {
            SettingsToggleRow(
                icon: "bell",
                title: "Push Notifications",
                subtitle: "Get notified about matches and activity",
                isOn: $notificationsEnabled
            )
        }
    }
    
    private var dataManagementSection: some View {
        SettingsSection(title: "Data Management") {
            SettingsRow(
                icon: "square.and.arrow.up",
                title: "Export My Data",
                subtitle: "Download all your Loci data",
                action: { showingDataExportSheet = true }
            )
            
            SettingsRow(
                icon: "trash",
                title: "Delete All Data",
                subtitle: "Permanently remove all your data",
                action: { showingDeleteAccountAlert = true },
                isDestructive: true
            )
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsRow(
                icon: "info.circle",
                title: "About Loci",
                subtitle: "Version 1.0",
                action: {}
            )
            
            SettingsRow(
                icon: "doc.text",
                title: "Terms of Service",
                subtitle: "View our terms and conditions",
                action: { openURL("https://loci.app/terms") }
            )
            
            SettingsRow(
                icon: "hand.raised",
                title: "Privacy Policy",
                subtitle: "Read our privacy policy",
                action: { openURL("https://loci.app/privacy") }
            )
            
            SettingsRow(
                icon: "questionmark.circle",
                title: "Support",
                subtitle: "Get help with Loci",
                action: { openURL("mailto:support@loci.app") }
            )
        }
    }
    
    private var signOutButton: some View {
        Button(action: { showingSignOutAlert = true }) {
            Text("Sign Out")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .onChange(of: privacyManager.privacySettings.shareLocation) { _ in
            privacyManager.updatePrivacySettings(privacyManager.privacySettings)
        }
        .onChange(of: privacyManager.privacySettings.shareListeningActivity) { _ in
            privacyManager.updatePrivacySettings(privacyManager.privacySettings)
        }
        .onChange(of: privacyManager.privacySettings.allowFriendRequests) { _ in
            privacyManager.updatePrivacySettings(privacyManager.privacySettings)
        }
        .onChange(of: privacyManager.privacySettings.showOnlineStatus) { _ in
            privacyManager.updatePrivacySettings(privacyManager.privacySettings)
        }
        .onChange(of: notificationsEnabled) { newValue in
            if newValue {
                notificationManager.requestNotificationPermission()
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                do {
                    try firebaseManager.signOut()
                } catch {
                    print("Error signing out: \(error)")
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete All Data", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await privacyManager.deleteAllUserData()
                    try? firebaseManager.signOut()
                }
            }
        } message: {
            Text("This will permanently delete all your Loci data including session history, imports, and preferences. This action cannot be undone.")
        }
        .sheet(isPresented: $showingPrivacyExplanation) {
            PrivacyExplanationView()
        }
        .sheet(isPresented: $showingDataExportSheet) {
            DataExportView()
                .environmentObject(dataStore)
        }
        .sheet(isPresented: $showingLeaderboardConsent) {
            LeaderboardConsentView(
                isPresented: $showingLeaderboardConsent,
                privacySettings: .constant(privacyManager.leaderboardPrivacySettings)
            ) { settings in
                privacyManager.updateLeaderboardPrivacySettings(settings)
            }
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private var leaderboardPrivacySubtitle: String {
        let settings = privacyManager.leaderboardPrivacySettings
        
        if !settings.hasGivenConsent {
            return "Not configured - tap to set up"
        }
        
        switch settings.privacyLevel {
        case .privateMode:
            return "Private - no data shared"
        case .anonymous:
            return "Anonymous participation"
        case .publicRegional:
            return "Public in regional leaderboards only"
        case .publicGlobal:
            return "Public in all leaderboards"
        }
    }
}

import Combine

// MARK: - Session Mode Coordinator

struct SessionModeCoordinator: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var selectedMode: SessionMode = .onePlace
    @State private var showingSessionHistory = false
    @State private var showingSettings = false
    @State private var showingSpotifyImport = false
    @State private var hasShownWelcome = UserDefaults.standard.bool(forKey: "hasShownModeWelcome")
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                CoordinatorHeader(
                    showingSettings: $showingSettings,
                    showingSpotifyImport: $showingSpotifyImport,
                    showingSessionHistory: $showingSessionHistory
                )
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.top, LociTheme.Spacing.large)
                
                // Main Content
                if sessionManager.isSessionActive {
                    // Show active session view
                    ActiveSessionCoordinatorView()
                } else {
                    // Show mode selection and setup
                    SessionModeSelectionCoordinator(selectedMode: $selectedMode)
                }
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(spotifyManager)
                .environmentObject(dataStore)
        }
        .sheet(isPresented: $showingSpotifyImport) {
            SpotifyImportView()
                .environmentObject(spotifyManager)
                .environmentObject(locationManager)
                .environmentObject(dataStore)
                .environmentObject(ReverseGeocoding.shared)
        }
        .sheet(isPresented: .constant(!hasShownWelcome)) {
            ModeWelcomeSheet(hasShownWelcome: $hasShownWelcome)
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    private func setupInitialState() {
        // If there's an active session, don't override the mode
        if !sessionManager.isSessionActive {
            // Set default mode based on user preference or last used
            selectedMode = UserDefaults.standard.string(forKey: "lastSelectedMode")
                .flatMap { SessionMode(rawValue: $0) } ?? .onePlace
        }
    }
}

// MARK: - Coordinator Header

struct CoordinatorHeader: View {
    @Binding var showingSettings: Bool
    @Binding var showingSpotifyImport: Bool
    @Binding var showingSessionHistory: Bool
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("Loci")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .neonText()
                
                if sessionManager.isSessionActive {
                    Text("\(sessionManager.sessionMode.displayName) Session Active")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(sessionManager.sessionMode == .onePlace ?
                                       LociTheme.Colors.secondaryHighlight :
                                       LociTheme.Colors.primaryAction)
                }
            }
            
            Spacer()
            
            HStack(spacing: LociTheme.Spacing.small) {
                // Import Button
                Button(action: { showingSpotifyImport = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                // History Button
                Button(action: { showingSessionHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                // Settings Button
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(LociTheme.Colors.mainText)
                }
            }
        }
    }
}


struct OnePlaceStatsGrid: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            SessionStatCard(
                icon: "music.note",
                value: "\(dataStore.currentSessionEvents.count)",
                label: "Tracks",
                color: LociTheme.Colors.secondaryHighlight
            )
            
            SessionStatCard(
                icon: "clock",
                value: sessionDuration,
                label: "Active",
                color: LociTheme.Colors.primaryAction
            )
            
            SessionStatCard(
                icon: "location.circle",
                value: "Here",
                label: "Location",
                color: LociTheme.Colors.secondaryHighlight
            )
        }
    }
    
    private var sessionDuration: String {
        // Calculate active time
        return "2h 15m" // Placeholder
    }
}

struct OnTheMoveStatsGrid: View {
    @EnvironmentObject var dataStore: DataStore
    
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
                value: "Active",
                label: "Tracking",
                color: LociTheme.Colors.secondaryHighlight
            )
        }
    }
    
    private var uniqueLocations: Int {
        Set(dataStore.currentSessionEvents.compactMap { $0.buildingName }).count
    }
}



struct OnePlaceSetupCard: View {
    @Binding var selectedLocation: String?
    @Binding var showingLocationPicker: Bool
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "location.square")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("One-Place Session")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            // Features
            VStack(spacing: LociTheme.Spacing.small) {
                FeatureRow(icon: "infinity", text: "No time limit - session continues until you stop it")
                FeatureRow(icon: "location.magnifyingglass", text: "Auto-detects when you move to a new building")
                FeatureRow(icon: "battery.100", text: "Battery efficient with smart location monitoring")
            }
            
            // Location selection (optional)
            if let location = selectedLocation {
                HStack {
                    Text("Starting at: \(location)")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Spacer()
                    
                    Button("Change") {
                        showingLocationPicker = true
                    }
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                .padding(LociTheme.Spacing.small)
                .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
                .cornerRadius(LociTheme.CornerRadius.small)
            } else {
                Button("Set Starting Location (Optional)") {
                    showingLocationPicker = true
                }
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - On-the-Move Setup Card

struct OnTheMoveSetupCard: View {
    @Binding var selectedDuration: SessionDuration
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text("On-the-Move Session")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            // Features
            VStack(spacing: LociTheme.Spacing.small) {
                FeatureRow(icon: "location.fill.viewfinder", text: "Precise GPS tracking every 90 seconds")
                FeatureRow(icon: "building.2", text: "Track music across multiple locations")
                FeatureRow(icon: "clock.badge.checkmark", text: "Auto-stops at your chosen time")
            }
            
            // Duration picker
            VStack(spacing: LociTheme.Spacing.small) {
                HStack {
                    Text("Session Duration")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Spacer()
                    
                    Text("Max 6 hours")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                SessionDurationPicker(selectedDuration: $selectedDuration, mode: .onTheMove)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}
struct ModeOptionButton: View {
    let mode: SessionMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: LociTheme.Spacing.small) {
                // Icon
                Image(systemName: mode.icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(iconColor)
                    .frame(height: 40)
                
                // Title
                Text(mode.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                // Description
                Text(shortDescription)
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(LociTheme.Spacing.medium)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .cornerRadius(LociTheme.CornerRadius.medium)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(LociTheme.Animation.bouncy, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var shortDescription: String {
        switch mode {
        case .onePlace: return "Stay in one location\nAuto-detects moves"
        case .onTheMove: return "Move around freely\nTimed sessions"
        case .unknown: return ""
        }
    }
    
    private var iconColor: Color {
        if isSelected {
            return mode == .onePlace ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.primaryAction
        } else {
            return LociTheme.Colors.subheadText
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            let baseColor = mode == .onePlace ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.primaryAction
            return baseColor.opacity(0.1)
        } else {
            return LociTheme.Colors.contentContainer
        }
    }
    
    @ViewBuilder
    private var borderOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .stroke(mode == .onePlace ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.primaryAction, lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .stroke(LociTheme.Colors.disabledState, lineWidth: 1)
        }
    }
}
struct OnePlaceActiveSessionCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Status Header
            HStack {
                HStack(spacing: LociTheme.Spacing.small) {
                    Circle()
                        .fill(LociTheme.Colors.secondaryHighlight)
                        .frame(width: 12, height: 12)
                        .glow(color: LociTheme.Colors.secondaryHighlight, radius: 4)
                    
                    Text("ACTIVE SESSION")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                Spacer()
                
                Text("One-Place")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xxSmall)
                    .background(LociTheme.Colors.disabledState.opacity(0.5))
                    .cornerRadius(LociTheme.CornerRadius.small)
            }
            
            // Current Building
            VStack(spacing: LociTheme.Spacing.small) {
                if let building = sessionManager.currentBuilding {
                    Text("Currently at")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Text(building)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Getting your location...")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                if sessionManager.hasDetectedLocationChange {
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text("Location updated automatically")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                    }
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xSmall)
                    .background(LociTheme.Colors.primaryAction.opacity(0.1))
                    .cornerRadius(LociTheme.CornerRadius.small)
                }
            }
            
            // Session Stats
            HStack(spacing: LociTheme.Spacing.medium) {
                OnePlaceStatItem(
                    icon: "music.note",
                    value: "\(dataStore.currentSessionEvents.count)",
                    label: "Tracks"
                )
                
                OnePlaceStatItem(
                    icon: "clock.arrow.circlepath",
                    value: sessionDuration,
                    label: "Active"
                )
                
                OnePlaceStatItem(
                    icon: "location.magnifyingglass",
                    value: "Auto",
                    label: "Detection"
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
    
    private var sessionDuration: String {
        guard let elapsed = sessionManager.getSessionElapsed() else { return "0m" }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
// MARK: - Active Session Coordinator View

struct ActiveSessionCoordinatorView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: LociTheme.Spacing.large) {
                // Mode-specific active session view
                switch sessionManager.sessionMode {
                case .onePlace:
                    OnePlaceActiveSessionCard()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                case .onTheMove:
                    OnTheMoveActiveSessionCard()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .unknown:
                    UnknownSessionCard()
                }
                
                // Current Activity (shared between modes)
                CurrentActivityCard()
                
                // Quick Session Actions
                QuickSessionActions()
                
                // Session Stats
                SessionStatsCard()
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.vertical, LociTheme.Spacing.large)
        }
        .animation(LociTheme.Animation.smoothEaseInOut, value: sessionManager.sessionMode)
    }
}
struct NewSessionModeSelectionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var spotifyManager: SpotifyManager
    
    @State private var selectedMode: SessionMode = .onePlace
    @State private var selectedDuration: SessionDuration = .twoHours
    @State private var showingLocationPicker = false
    @State private var selectedLocation: String?
    @State private var selectedLocationInfo: SelectedLocationInfo?
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Mode Toggle (Clean and simple)
            ModeToggleCard(selectedMode: $selectedMode)
            
            // Mode-specific content
            Group {
                switch selectedMode {
                case .onePlace:
                    OnePlaceSetupCard(
                        selectedLocation: $selectedLocation,
                        showingLocationPicker: $showingLocationPicker
                    )
                case .onTheMove:
                    OnTheMoveSetupCard(selectedDuration: $selectedDuration)
                case .unknown:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: selectedMode == .onePlace ? .leading : .trailing).combined(with: .opacity),
                removal: .move(edge: selectedMode == .onePlace ? .trailing : .leading).combined(with: .opacity)
            ))
            .animation(LociTheme.Animation.smoothEaseInOut, value: selectedMode)
            
            // Start Button
            StartSessionButton(
                mode: selectedMode,
                duration: selectedMode == .onTheMove ? selectedDuration : nil,
                location: selectedLocation,
                canStart: canStartSession
            )
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationSelectionView(
                selectedLocation: $selectedLocation,
                selectedLocationInfo: $selectedLocationInfo
            )
        }
    }
    
    private var canStartSession: Bool {
        switch selectedMode {
        case .onePlace:
            return locationManager.authorizationStatus != .denied &&
                   locationManager.authorizationStatus != .restricted
        case .onTheMove:
            return locationManager.authorizationStatus == .authorizedAlways ||
                   locationManager.authorizationStatus == .authorizedWhenInUse
        case .unknown:
            return false
        }
    }
}
struct ModeToggleCard: View {
    @Binding var selectedMode: SessionMode
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Header
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Choose Your Session Type")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Two simple modes for any situation")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            // Mode buttons
            HStack(spacing: LociTheme.Spacing.medium) {
                ModeOptionButton(
                    mode: .onePlace,
                    isSelected: selectedMode == .onePlace
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedMode = .onePlace
                    }
                }
                
                ModeOptionButton(
                    mode: .onTheMove,
                    isSelected: selectedMode == .onTheMove
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedMode = .onTheMove
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Session Mode Selection Coordinator

struct SessionModeSelectionCoordinator: View {
    @Binding var selectedMode: SessionMode
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: LociTheme.Spacing.large) {
                // Mode Toggle
                ModeToggleSegment(selectedMode: $selectedMode)
                    .padding(.horizontal, LociTheme.Spacing.medium)
                
                // Mode-specific view
                Group {
                    switch selectedMode {
                    case .onePlace:
                        OnePlaceSessionView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    case .onTheMove:
                        OnTheMoveSessionView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .unknown:
                        EmptyView()
                    }
                }
                .animation(LociTheme.Animation.smoothEaseInOut, value: selectedMode)
            }
            .padding(.bottom, LociTheme.Spacing.xxLarge)
        }
        .onChange(of: selectedMode) { newMode in
            // Save user preference
            UserDefaults.standard.set(newMode.rawValue, forKey: "lastSelectedMode")
        }
    }
}

// MARK: - Mode Toggle Segment

struct ModeToggleSegment: View {
    @Binding var selectedMode: SessionMode
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Header
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Choose Your Session Type")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Swipe between modes or tap to switch")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            // Segmented Control
            HStack(spacing: 0) {
                ModeSegmentButton(
                    mode: .onePlace,
                    isSelected: selectedMode == .onePlace
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedMode = .onePlace
                    }
                }
                
                ModeSegmentButton(
                    mode: .onTheMove,
                    isSelected: selectedMode == .onTheMove
                ) {
                    withAnimation(LociTheme.Animation.smoothEaseInOut) {
                        selectedMode = .onTheMove
                    }
                }
            }
            .background(LociTheme.Colors.disabledState)
            .cornerRadius(LociTheme.CornerRadius.medium)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Mode Segment Button

struct ModeSegmentButton: View {
    let mode: SessionMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textColor)
                    
                    Text(shortDescription)
                        .font(.system(size: 10))
                        .foregroundColor(subtitleColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LociTheme.Spacing.small)
            .background(backgroundColor)
            .cornerRadius(LociTheme.CornerRadius.small)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var shortDescription: String {
        switch mode {
        case .onePlace: return "Stay in one location"
        case .onTheMove: return "Move around freely"
        case .unknown: return ""
        }
    }
    
    private var iconColor: Color {
        isSelected ? LociTheme.Colors.appBackground : modeColor.opacity(0.7)
    }
    
    private var textColor: Color {
        isSelected ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText
    }
    
    private var subtitleColor: Color {
        isSelected ? LociTheme.Colors.appBackground.opacity(0.8) : LociTheme.Colors.subheadText
    }
    
    private var backgroundColor: Color {
        isSelected ? modeColor : Color.clear
    }
    
    private var modeColor: Color {
        switch mode {
        case .onePlace: return LociTheme.Colors.secondaryHighlight
        case .onTheMove: return LociTheme.Colors.primaryAction
        case .unknown: return LociTheme.Colors.disabledState
        }
    }
}
struct UnknownSessionDashboard: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Unknown Session")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("This session was created with an older version")
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Button("End Session") {
                sessionManager.stopSession()
            }
            .lociButton(.primary)
        }
        .padding(LociTheme.Spacing.large)
        .lociCard()
    }
}

// MARK: - Unknown Session Card

struct UnknownSessionCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Unknown Session Type")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("This session was created with an older version of Loci")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Button("End Session") {
                sessionManager.stopSession()
            }
            .lociButton(.primary)
        }
        .padding(LociTheme.Spacing.large)
        .lociCard()
    }
}

// MARK: - Current Activity Card (Shared)

struct CurrentActivityCard: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var sessionManager: SessionManager
    
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
                
                if let building = sessionManager.currentBuilding {
                    Text(building)
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                        .lineLimit(1)
                }
            }
            
            if let lastEvent = dataStore.currentSessionEvents.last {
                RecentTrackView(event: lastEvent)
            } else {
                EmptyActivityView()
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
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
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeAgo(from: event.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Image(systemName: sessionModeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(sessionModeColor)
            }
        }
    }
    
    private var sessionModeIcon: String {
        switch event.sessionMode {
        case .onePlace: return "location.square.fill"
        case .onTheMove: return "location.fill.viewfinder"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var sessionModeColor: Color {
        switch event.sessionMode {
        case .onePlace: return LociTheme.Colors.secondaryHighlight
        case .onTheMove: return LociTheme.Colors.primaryAction
        case .unknown: return LociTheme.Colors.subheadText
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
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.subheadText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.medium)
    }
}

// MARK: - Quick Session Actions

struct QuickSessionActions: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showingSessionDetails = false
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Button("View Details") {
                showingSessionDetails = true
            }
            .lociButton(.secondary)
            
            Button("End Session") {
                sessionManager.stopSession()
            }
            .lociButton(.primary)
        }
        .sheet(isPresented: $showingSessionDetails) {
            LiveSessionDetailsView()
        }
    }
}

// MARK: - Session Stats Card

struct SessionStatsCard: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Session Stats")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Text("Live")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LociTheme.Colors.secondaryHighlight.opacity(0.2))
                    .cornerRadius(4)
            }
            
            HStack(spacing: LociTheme.Spacing.medium) {
                StatItem(
                    icon: "music.note",
                    value: "\(dataStore.currentSessionEvents.count)",
                    label: "Tracks"
                )
                
                StatItem(
                    icon: "building.2",
                    value: "\(uniqueLocations)",
                    label: sessionManager.sessionMode == .onePlace ? "Changes" : "Places"
                )
                
                StatItem(
                    icon: "clock",
                    value: sessionDuration,
                    label: "Duration"
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
    
    private var uniqueLocations: Int {
        if sessionManager.sessionMode == .onePlace {
            return dataStore.buildingChanges.count
        } else {
            return Set(dataStore.currentSessionEvents.compactMap { $0.buildingName }).count
        }
    }
    
    private var sessionDuration: String {
        guard let elapsed = sessionManager.getSessionElapsed() else { return "0m" }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.small)
        .background(LociTheme.Colors.appBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Mode Welcome Sheet

struct ModeWelcomeSheet: View {
    @Binding var hasShownWelcome: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: LociTheme.Spacing.large) {
                    // Welcome Header
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                            .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
                        
                        Text("Welcome to the New Loci")
                            .font(LociTheme.Typography.heading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("We've simplified session tracking into two powerful modes")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Mode Explanations
                    VStack(spacing: LociTheme.Spacing.medium) {
                        WelcomeModeCard(
                            mode: .onePlace,
                            highlights: [
                                "No time limits",
                                "Auto-detects location changes",
                                "Battery efficient",
                                "Perfect for cafes, offices, home"
                            ]
                        )
                        
                        WelcomeModeCard(
                            mode: .onTheMove,
                            highlights: [
                                "Precise GPS tracking",
                                "Multi-location journeys",
                                "Timed sessions (max 6 hours)",
                                "Great for commutes, travel"
                            ]
                        )
                    }
                    
                    Button("Get Started") {
                        hasShownWelcome = true
                        UserDefaults.standard.set(true, forKey: "hasShownModeWelcome")
                        dismiss()
                    }
                    .lociButton(.gradient, isFullWidth: true)
                }
                .padding()
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Welcome Mode Card

struct WelcomeModeCard: View {
    let mode: SessionMode
    let highlights: [String]
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: mode.icon)
                    .font(.system(size: 24))
                    .foregroundColor(modeColor)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(mode.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(mode.description)
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                ForEach(highlights, id: \.self) { highlight in
                    HStack(spacing: LociTheme.Spacing.small) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(modeColor)
                        
                        Text(highlight)
                            .font(.system(size: 13))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .fill(modeColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                        .stroke(modeColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var modeColor: Color {
        switch mode {
        case .onePlace: return LociTheme.Colors.secondaryHighlight
        case .onTheMove: return LociTheme.Colors.primaryAction
        case .unknown: return LociTheme.Colors.disabledState
        }
    }
}

// MARK: - Live Session Details View (Placeholder)

struct LiveSessionDetailsView: View {
    @Environment(\.dismiss) var dismiss
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

// MARK: - Placeholder Views for Details

struct SessionOverviewCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            Text("Session Overview")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                OverviewRow(label: "Mode", value: sessionManager.sessionMode.displayName)
                OverviewRow(label: "Started", value: formatTime(sessionManager.sessionStartTime))
                OverviewRow(label: "Tracks Collected", value: "\(dataStore.currentSessionEvents.count)")
                OverviewRow(label: "Unique Locations", value: "\(uniqueLocations)")
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
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
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

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
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
    
    private var locationCounts: [String: Int] {
        Dictionary(grouping: dataStore.currentSessionEvents.compactMap { $0.buildingName }) { $0 }
            .mapValues { $0.count }
    }
}

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

// MARK: - Spotify Import Main View (NEW PRIMARY FEATURE)

struct SpotifyImportMainView: View {
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingImportSheet = false
    @State private var currentRegion: String = "Your Area"
    @State private var currentBuilding: String?
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Hero Import Section
            SpotifyImportHeroCard(
                region: currentRegion,
                building: currentBuilding,
                showingImportSheet: $showingImportSheet
            )
            
            // Quick Stats / Recent Activity Preview
            RecentImportPreviewCard()
            
            // Regional Discovery Teaser
            RegionalDiscoveryTeaser(region: currentRegion)
        }
    }
}

// MARK: - Spotify Import Hero Card

struct SpotifyImportHeroCard: View {
    let region: String
    let building: String?
    @Binding var showingImportSheet: Bool
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var dataStore: DataStore
    
    @State private var showingStreamlinedImport = false
    
    private var locationDisplayText: String {
        dataStore.designatedLocation?.displayName ?? region
    }
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Catchy Header
            VStack(spacing: LociTheme.Spacing.medium) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
                
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Share Your Sound")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Let **\(locationDisplayText)** know what you've been listening to")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Import Button
            Button(action: { 
                if spotifyManager.isAuthenticated {
                    if dataStore.designatedLocation != nil {
                        // Use streamlined import when location is known
                        showingStreamlinedImport = true
                    } else {
                        // Use full import flow when location needs to be selected
                        showingImportSheet = true
                    }
                } else {
                    spotifyManager.startAuthorization()
                }
            }) {
                HStack(spacing: LociTheme.Spacing.medium) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 24))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dataStore.designatedLocation != nil ? "Quick Import" : "Import Recent Plays")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text(dataStore.designatedLocation != nil ? "Import to \(dataStore.designatedLocation?.displayName ?? "your location")" : "Your last 50 tracks from Spotify")
                            .font(.system(size: 14))
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(LociTheme.Spacing.large)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [LociTheme.Colors.secondaryHighlight, LociTheme.Colors.primaryAction],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: LociTheme.Colors.secondaryHighlight.opacity(0.3), radius: 10, x: 0, y: 5)
                )
            }
            .disabled(!spotifyManager.isAuthenticated && spotifyManager.isLoading)
            
            // Status indicator
            if !spotifyManager.isAuthenticated {
                HStack(spacing: LociTheme.Spacing.small) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                    
                    Text("Connect Spotify to start sharing")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
        }
        .padding(LociTheme.Spacing.large)
        .lociCard()
        .sheet(isPresented: $showingImportSheet) {
            SpotifyImportView()
                .environmentObject(spotifyManager)
                .environmentObject(locationManager)
                .environmentObject(dataStore)
                .environmentObject(ReverseGeocoding.shared)
        }
        .sheet(isPresented: $showingStreamlinedImport) {
            StreamlinedSpotifyImportView()
                .environmentObject(spotifyManager)
                .environmentObject(dataStore)
                .environmentObject(locationManager)
        }
    }
}

// MARK: - Recent Import Preview (REAL IMPLEMENTATION)

struct RecentImportPreviewCard: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingImportHistory = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Your Recent Shares")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Button("View All") {
                    showingImportHistory = true
                }
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
            if let recentImport = dataStore.importBatches.last {
                RecentImportRow(importBatch: recentImport) {
                    showingImportHistory = true
                }
            } else {
                EmptyImportPreview()
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
        .sheet(isPresented: $showingImportHistory) {
            ImportHistoryView()
                .environmentObject(dataStore)
        }
    }
}

struct RecentImportRow: View {
    let importBatch: ImportBatch
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: LociTheme.Spacing.medium) {
            // Import icon
            ZStack {
                Circle()
                    .fill(LociTheme.Colors.secondaryHighlight.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
            // Import details
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                HStack {
                    Text("\(importBatch.tracks.count) tracks")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("•")
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Text(timeAgo(from: importBatch.importedAt))
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Image(systemName: importBatch.assignmentType == .building ? "building.2" : "map")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                    
                    Text(importBatch.location)
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                        .lineLimit(1)
                }
                
                // Show first few track names
                if !importBatch.tracks.isEmpty {
                    let previewTracks = Array(importBatch.tracks.prefix(2))
                    let trackNames = previewTracks.map { $0.name }.joined(separator: ", ")
                    let moreText = importBatch.tracks.count > 2 ? " +\(importBatch.tracks.count - 2) more" : ""
                    
                    Text(trackNames + moreText)
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct EmptyImportPreview: View {
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.subheadText.opacity(0.7))
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("No imports yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text("Import your recent Spotify plays to get started")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.vertical, LociTheme.Spacing.small)
    }
}
// MARK: - Regional Discovery Teaser (REAL IMPLEMENTATION)

struct RegionalDiscoveryTeaser: View {
    let region: String
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text("Discover \(region)")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            // Show actual trending track from recent data
            if let trendingTrack = getMostPlayedTrack() {
                VStack(spacing: LociTheme.Spacing.small) {
                    HStack {
                        Text("🎵 Trending in your area:")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("\(trendingTrack.name) • \(trendingTrack.artist)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(LociTheme.Colors.mainText)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(trendingTrack.playCount) plays")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                    }
                }
            } else {
                HStack {
                    Text("🎵 No trending data yet")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Spacer()
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
    
    private func getMostPlayedTrack() -> (name: String, artist: String, playCount: Int)? {
        // Aggregate tracks from all sessions and imports
        var trackCounts: [String: (artist: String, count: Int)] = [:]
        
        // Count from sessions
        for session in dataStore.sessionHistory {
            for event in session.events {
                let key = "\(event.trackName)|\(event.artistName)"
                if let existing = trackCounts[key] {
                    trackCounts[key] = (artist: existing.artist, count: existing.count + 1)
                } else {
                    trackCounts[key] = (artist: event.artistName, count: 1)
                }
            }
        }
        
        // Count from imports
        for importBatch in dataStore.importBatches {
            for track in importBatch.tracks {
                let key = "\(track.name)|\(track.artist)"
                if let existing = trackCounts[key] {
                    trackCounts[key] = (artist: existing.artist, count: existing.count + 1)
                } else {
                    trackCounts[key] = (artist: track.artist, count: 1)
                }
            }
        }
        
        // Find most played
        guard let mostPlayed = trackCounts.max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }
        
        let trackName = String(mostPlayed.key.split(separator: "|").first ?? "")
        return (
            name: trackName,
            artist: mostPlayed.value.artist,
            playCount: mostPlayed.value.count
        )
    }
}

// MARK: - Advanced Session Options (MOVED DOWN - Secondary Feature)

struct AdvancedSessionOptionsView: View {
    @State private var showingAdvancedOptions = false
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingAdvancedOptions.toggle()
                }
            }) {
                HStack {
                    Text("Advanced Session Modes")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Spacer()
                    
                    Image(systemName: showingAdvancedOptions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.contentContainer.opacity(0.5))
                .cornerRadius(LociTheme.CornerRadius.medium)
            }
            
            if showingAdvancedOptions {
                // KEEP your existing NewSessionModeSelectionView here
                NewSessionModeSelectionView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
    }
}
// MARK: - Leaderboard Preview Section

struct LeaderboardPreviewSection: View {
    @StateObject private var leaderboardManager = LeaderboardManager.shared
    @State private var showingFullLeaderboards = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Your Rankings")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Button("View All") {
                    showingFullLeaderboards = true
                }
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
            if let bestRanking = leaderboardManager.getBestUserRanking() {
                LeaderboardPreviewCard(ranking: bestRanking)
            } else {
                EmptyLeaderboardPreview()
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
        .sheet(isPresented: $showingFullLeaderboards) {
            LeaderboardView()
                .environmentObject(leaderboardManager)
        }
        .onAppear {
            Task {
                await leaderboardManager.loadLeaderboards()
            }
        }
    }
}

struct LeaderboardPreviewCard: View {
    let ranking: BestRanking
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(LociTheme.Colors.secondaryHighlight)
                    .frame(width: 40, height: 40)
                
                Text("#\(ranking.rank)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(LociTheme.Colors.appBackground)
            }
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(ranking.displayText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("out of \(ranking.totalParticipants) listeners")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
    }
}

struct EmptyLeaderboardPreview: View {
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Text("Start listening to see your rankings")
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
        }
    }
}

// MARK: - Location Selection Section

struct LocationSelectionSection: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingLocationPicker = false
    @State private var isDetectingLocation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Your Location")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                if dataStore.designatedLocation != nil {
                    Button("Change") {
                        showingLocationPicker = true
                    }
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
            
            if let location = dataStore.designatedLocation {
                SelectedLocationCard(location: location) {
                    dataStore.clearDesignatedLocation()
                }
            } else {
                LocationSelectionCard(
                    onDetectLocation: detectCurrentLocation,
                    onManualSelection: { showingLocationPicker = true },
                    isDetecting: isDetectingLocation
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(onLocationSelected: { region, building, coordinate in
                dataStore.setDesignatedLocation(region: region, building: building, coordinate: coordinate)
            })
        }
    }
    
    private func detectCurrentLocation() {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            locationManager.requestPermissions()
            return
        }
        
        isDetectingLocation = true
        
        locationManager.requestOneTimeLocation { location in
            guard let location = location else {
                isDetectingLocation = false
                return
            }
            
            Task {
                let buildingInfo = await ReverseGeocoding.shared.reverseGeocodeAsync(location: location)
                
                DispatchQueue.main.async {
                    let region = buildingInfo?.city ?? buildingInfo?.neighborhood ?? "Your Area"
                    let building = buildingInfo?.name
                    
                    dataStore.setDesignatedLocation(
                        region: region,
                        building: building,
                        coordinate: location.coordinate
                    )
                    
                    isDetectingLocation = false
                }
            }
        }
    }
}

struct SelectedLocationCard: View {
    let location: DataStore.DesignatedLocation
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: location.building != nil ? "building.2.fill" : "map.fill")
                .font(.system(size: 20))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(location.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(location.building != nil ? "Building & Region" : "Region Only")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(LociTheme.Colors.disabledState)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

struct LocationSelectionCard: View {
    let onDetectLocation: () -> Void
    let onManualSelection: () -> Void
    let isDetecting: Bool
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Button(action: onDetectLocation) {
                HStack {
                    if isDetecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                            .scaleEffect(0.8)
                        Text("Detecting...")
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        Text("Auto-Detect Location")
                    }
                    
                    Spacer()
                    
                    if !isDetecting {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
                .foregroundColor(LociTheme.Colors.mainText)
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.disabledState.opacity(0.3))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
            .disabled(isDetecting)
            
            Button(action: onManualSelection) {
                HStack {
                    Image(systemName: "map")
                        .font(.system(size: 18))
                        .foregroundColor(LociTheme.Colors.mainText)
                    Text("Select Manually")
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .foregroundColor(LociTheme.Colors.mainText)
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.disabledState.opacity(0.3))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}

struct LocationPickerView: View {
    let onLocationSelected: (String, String?, CLLocationCoordinate2D?) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var isReverseGeocoding = false
    @State private var selectedType: LocationType = .regionOnly
    
    enum LocationType: CaseIterable {
        case regionOnly, building
        
        var title: String {
            switch self {
            case .regionOnly: return "Region Only"
            case .building: return "Specific Building"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map
                Map(coordinateRegion: $mapRegion)
                    .ignoresSafeArea(edges: .bottom)
                
                // Center crosshair
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                // Selection UI
                VStack {
                    // Type selector
                    VStack(spacing: LociTheme.Spacing.small) {
                        HStack(spacing: 0) {
                            ForEach(LocationType.allCases, id: \.self) { type in
                                Button(type.title) {
                                    selectedType = type
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedType == type ? .white : LociTheme.Colors.subheadText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, LociTheme.Spacing.small)
                                .background(selectedType == type ? LociTheme.Colors.primaryAction : Color.clear)
                                .cornerRadius(LociTheme.CornerRadius.small)
                            }
                        }
                        .background(LociTheme.Colors.disabledState)
                        .cornerRadius(LociTheme.CornerRadius.medium)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: LociTheme.Spacing.medium) {
                        if isReverseGeocoding {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Finding location...")
                                    .font(LociTheme.Typography.body)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(LociTheme.CornerRadius.medium)
                        }
                        
                        HStack(spacing: LociTheme.Spacing.small) {
                            Button("Cancel") {
                                dismiss()
                            }
                            .lociButton(.secondary)
                            
                            Button("Select This Location") {
                                selectCurrentLocation()
                            }
                            .lociButton(.primary)
                            .disabled(isReverseGeocoding)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Your Location")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Center on user's current location if available
                if let currentLocation = locationManager.currentLocation {
                    mapRegion.center = currentLocation.coordinate
                }
            }
        }
    }
    
    private func selectCurrentLocation() {
        isReverseGeocoding = true
        let coordinate = mapRegion.center
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        Task {
            let buildingInfo = await ReverseGeocoding.shared.reverseGeocodeAsync(location: location)
            
            DispatchQueue.main.async {
                let region = buildingInfo?.city ?? buildingInfo?.neighborhood ?? "Selected Area"
                let building = selectedType == .building ? buildingInfo?.name : nil
                
                onLocationSelected(region, building, coordinate)
                isReverseGeocoding = false
                dismiss()
            }
        }
    }
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            VStack(spacing: 1) {
                content
            }
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
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var isDestructive: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isDestructive ? .red : .blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDestructive ? .red : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct SettingsPickerRow<T: CaseIterable & RawRepresentable & Hashable>: View where T.RawValue == String {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selection: T
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text(selection.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Picker options
            VStack(spacing: 8) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Button(action: { selection = option }) {
                        HStack {
                            Text(option.rawValue)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            selection == option ? 
                            Color.blue.opacity(0.2) :
                            Color.clear
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if let topItemsVisibility = selection as? TopItemsVisibility {
                    Text(topItemsVisibility.description)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

// MARK: - Privacy Explanation View

struct PrivacyExplanationView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)
                            
                            Text("Your Privacy Matters")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Loci is designed with privacy at its core. Here's how we protect your data:")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        
                        // Location Privacy
                        PrivacyPointCard(
                            icon: "location.circle",
                            title: "Location is Optional",
                            description: "You can manually select your location instead of using GPS. Like dating apps, you control exactly what location information you share.",
                            points: [
                                "GPS is never required",
                                "Manual location selection available",
                                "You choose the precision level",
                                "Location data stays on your device by default"
                            ]
                        )
                        
                        // Music Privacy
                        PrivacyPointCard(
                            icon: "music.note.list",
                            title: "Music Data Protection",
                            description: "Your listening history is anonymized and encrypted. Only you see the full details.",
                            points: [
                                "Data is anonymized before sharing",
                                "Only trends are shared, not full history",
                                "You control what music info is visible",
                                "Full listening data stays private"
                            ]
                        )
                        
                        // Data Control
                        PrivacyPointCard(
                            icon: "hand.raised",
                            title: "You're in Control",
                            description: "You decide what to share, when to share it, and with whom.",
                            points: [
                                "Granular privacy controls",
                                "Export your data anytime",
                                "Delete everything instantly",
                                "No hidden data collection"
                            ]
                        )
                        
                        // Bottom note
                        VStack(spacing: 12) {
                            Text("Questions?")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Button("Contact Support") {
                                if let url = URL(string: "mailto:privacy@loci.app") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

struct PrivacyPointCard: View {
    let icon: String
    let title: String
    let description: String
    let points: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(points, id: \.self) { point in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        
                        Text(point)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
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

// MARK: - Data Export View

struct DataExportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var privacyManager = PrivacyManager.shared
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.up.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)
                        
                        Text("Export Your Data")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Download all your Loci data including sessions, imports, and preferences as a JSON file.")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    VStack(spacing: 16) {
                        DataExportRow(
                            title: "Session History",
                            count: dataStore.sessionHistory.count,
                            icon: "clock.arrow.circlepath"
                        )
                        
                        DataExportRow(
                            title: "Spotify Imports",
                            count: dataStore.importBatches.count,
                            icon: "square.and.arrow.down"
                        )
                        
                        DataExportRow(
                            title: "Privacy Settings",
                            count: 1,
                            icon: "shield.checkered"
                        )
                    }
                    
                    Spacer()
                    
                    Button(action: exportData) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export My Data")
                            }
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.blue)
                        .cornerRadius(16)
                    }
                    .disabled(isExporting)
                    .padding(.horizontal, 20)
                }
                .padding(24)
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func exportData() {
        isExporting = true
        
        Task {
            let exportData = await privacyManager.exportUserData()
            
            DispatchQueue.main.async {
                let jsonData = try? JSONEncoder().encode(exportData)
                let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "Export failed"
                
                let activityController = UIActivityViewController(
                    activityItems: [jsonString],
                    applicationActivities: nil
                )
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityController, animated: true)
                }
                
                isExporting = false
                dismiss()
            }
        }
    }
}

struct DataExportRow: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Streamlined Spotify Import View

struct StreamlinedSpotifyImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var isLoading = false
    @State private var recentTracks: [SpotifyImportTrack] = []
    @State private var selectedTracks: Set<String> = []
    @State private var errorMessage: String?
    @State private var importStep: StreamlinedImportStep = .loading
    @State private var allTracksCount: Int?
    @State private var showingSuccessMessage = false
    
    enum StreamlinedImportStep {
        case loading
        case trackSelection
        case importing
        case success
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                switch importStep {
                case .loading:
                    LoadingView()
                case .trackSelection:
                    TrackSelectionView()
                case .importing:
                    ImportingView()
                case .success:
                    SuccessView()
                }
            }
            .navigationTitle("Quick Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                if importStep == .trackSelection {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Import") {
                            performImport()
                        }
                        .disabled(selectedTracks.isEmpty)
                        .foregroundColor(selectedTracks.isEmpty ? LociTheme.Colors.disabledState : LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
        }
        .onAppear {
            loadRecentTracks()
        }
    }
    
    // MARK: - Loading View
    
    @ViewBuilder
    func LoadingView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                .scaleEffect(1.5)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Fetching Your Recent Plays")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Finding new tracks to share")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
    }
    
    // MARK: - Track Selection View
    
    @ViewBuilder
    func TrackSelectionView() -> some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Header with location info
            VStack(spacing: LociTheme.Spacing.small) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sharing to")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        Text(dataStore.designatedLocation?.displayName ?? "Unknown Location")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
                
                // Show info about filtered tracks if any were removed
                if let allTracksCount = allTracksCount, allTracksCount > recentTracks.count {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text("Showing \(recentTracks.count) new tracks (filtered out \(allTracksCount - recentTracks.count) already imported)")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Spacer()
                    }
                }
                
                HStack {
                    Button(selectedTracks.count == recentTracks.count ? "Deselect All" : "Select All") {
                        if selectedTracks.count == recentTracks.count {
                            selectedTracks.removeAll()
                        } else {
                            selectedTracks = Set(recentTracks.map { $0.id })
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    Spacer()
                    
                    Text("\(selectedTracks.count) of \(recentTracks.count) selected")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            .padding(.horizontal)
            
                         // Track List
             List(recentTracks, id: \.id) { track in
                 StreamlinedTrackRow(
                     track: track,
                     isSelected: selectedTracks.contains(track.id)
                 ) {
                     if selectedTracks.contains(track.id) {
                         selectedTracks.remove(track.id)
                     } else {
                         selectedTracks.insert(track.id)
                     }
                 }
                 .listRowBackground(LociTheme.Colors.contentContainer)
             }
             .listStyle(PlainListStyle())
        }
    }
    
    // MARK: - Importing View
    
    @ViewBuilder
    func ImportingView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                .scaleEffect(1.5)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Sharing Your Music")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Adding \(selectedTracks.count) tracks to \(dataStore.designatedLocation?.displayName ?? "your location")")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Success View
    
    @ViewBuilder
    func SuccessView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            VStack(spacing: LociTheme.Spacing.medium) {
                Text("Music Shared!")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                if let error = errorMessage {
                    Text(error)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.primaryAction)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Successfully shared \(selectedTracks.count) tracks with \(dataStore.designatedLocation?.displayName ?? "your location")")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: LociTheme.Spacing.medium) {
                Text("Listen to some new music and come back to share more!")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Button("Got it") {
                dismiss()
            }
            .lociButton(.primary, isFullWidth: true)
        }
        .padding(LociTheme.Spacing.large)
    }
    
    // MARK: - Helper Methods
    
    private func loadRecentTracks() {
        isLoading = true
        
        Task {
            do {
                let allTracks = try await spotifyManager.fetchRecentlyPlayedTracks(limit: 50)
                let newTracks = dataStore.filterNewTracks(allTracks)
                
                await MainActor.run {
                    self.allTracksCount = allTracks.count
                    self.recentTracks = newTracks
                    
                    // Show helpful message if some/all tracks were already imported
                    let importedCount = allTracks.count - newTracks.count
                    if importedCount > 0 {
                        if newTracks.isEmpty {
                            self.errorMessage = "All \(allTracks.count) recent tracks have already been imported"
                            self.importStep = .success
                        } else {
                            print("ℹ️ Filtered out \(importedCount) already-imported tracks, showing \(newTracks.count) new tracks")
                        }
                    }
                    
                    self.selectedTracks = Set(newTracks.map { $0.id }) // Select all new tracks by default
                    
                    if !newTracks.isEmpty {
                        self.importStep = .trackSelection
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performImport() {
        guard let location = dataStore.designatedLocation else { return }
        
        importStep = .importing
        
        // Get selected tracks (already filtered for duplicates)
        let tracksToImport = recentTracks.filter { selectedTracks.contains($0.id) }
        
        // This shouldn't happen since we already filtered duplicates, but safety check
        if tracksToImport.isEmpty {
            importStep = .success
            errorMessage = "No tracks selected for import"
            return
        }
        
        // Create import batch using the designated location
        let importBatch = ImportBatch(
            id: UUID(),
            tracks: tracksToImport,
            location: location.displayName,
            assignmentType: location.building != nil ? .building : .region,
            importedAt: Date()
        )
        
        // Save to data store (triggers leaderboard update)
        dataStore.saveImportBatch(importBatch)
        
        // Update SpotifyManager
        spotifyManager.hasRecentImports = !dataStore.importBatches.isEmpty
        
        // Show success feedback
        NotificationManager.shared.showImportSuccessNotification(
            trackCount: tracksToImport.count,
            location: location.displayName
        )
        
        // Move to success step
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            importStep = .success
        }
    }
}

// MARK: - Streamlined Track Row

struct StreamlinedTrackRow: View {
    let track: SpotifyImportTrack
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: LociTheme.Spacing.medium) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                
                // Track info
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(track.name)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Played time
                Text(track.playedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            .padding(.vertical, LociTheme.Spacing.xSmall)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Import History View

struct ImportHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                if dataStore.importBatches.isEmpty {
                    VStack(spacing: LociTheme.Spacing.large) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(LociTheme.Colors.subheadText.opacity(0.5))
                        
                        VStack(spacing: LociTheme.Spacing.small) {
                            Text("No Import History")
                                .font(LociTheme.Typography.subheading)
                                .foregroundColor(LociTheme.Colors.mainText)
                            
                            Text("Your Spotify imports will appear here")
                                .font(LociTheme.Typography.body)
                                .foregroundColor(LociTheme.Colors.subheadText)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    List(dataStore.importBatches.reversed(), id: \.id) { importBatch in
                        ImportHistoryRow(importBatch: importBatch)
                            .listRowBackground(LociTheme.Colors.contentContainer)
                    }
                    .listStyle(PlainListStyle())
                    .background(LociTheme.Colors.appBackground)
                }
            }
            .navigationTitle("Import History")
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

struct ImportHistoryRow: View {
    let importBatch: ImportBatch
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            // Header
            HStack {
                Text("\(importBatch.tracks.count) tracks")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Text(timeAgo(from: importBatch.importedAt))
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            // Location
            HStack(spacing: LociTheme.Spacing.xSmall) {
                Image(systemName: importBatch.assignmentType == .building ? "building.2" : "map")
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text(importBatch.location)
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                    .fontWeight(.medium)
            }
            
            // Track preview
            if !importBatch.tracks.isEmpty {
                let previewTracks = Array(importBatch.tracks.prefix(3))
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    ForEach(previewTracks, id: \.id) { track in
                        HStack {
                            Text("• \(track.name)")
                                .font(.system(size: 13))
                                .foregroundColor(LociTheme.Colors.mainText)
                                .lineLimit(1)
                            
                            Text("by \(track.artist)")
                                .font(.system(size: 13))
                                .foregroundColor(LociTheme.Colors.subheadText)
                                .lineLimit(1)
                        }
                    }
                    
                    if importBatch.tracks.count > 3 {
                        Text("+ \(importBatch.tracks.count - 3) more tracks")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .italic()
                    }
                }
            }
            
            // Total duration
            let totalMinutes = importBatch.tracks.reduce(0) { $0 + $1.durationMinutes }
            Text("Total: \(Int(totalMinutes)) minutes")
                .font(.system(size: 12))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .fontWeight(.medium)
        }
        .padding(.vertical, LociTheme.Spacing.small)
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
