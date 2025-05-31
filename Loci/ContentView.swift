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

// MARK: - Session Mode Selection View

struct SessionModeSelectionView: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Session Info
            VStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
                
                Text("Start a Tracking Session")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Loci will log your Spotify tracks and location every 90 seconds. Session will auto-stop after 6 hours or you can stop anytime.")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LociTheme.Spacing.medium)
            }
            .padding(.vertical, LociTheme.Spacing.medium)
            
            // Session Mode Buttons
            HStack(spacing: LociTheme.Spacing.medium) {
                Button(action: {
                    // Implement the action for starting a session in active mode
                }) {
                    Text("Start Live Session")
                        .font(LociTheme.Typography.button)
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                .lociButton(.gradient, isFullWidth: true)
                
                Button(action: {
                    // Implement the action for starting a session in passive mode
                }) {
                    Text("Start Passive Session")
                        .font(LociTheme.Typography.button)
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                .lociButton(.secondary, isFullWidth: true)
            }
        }
        .padding(.vertical, LociTheme.Spacing.medium)
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Live Indicator
            LiveSessionIndicator(endTime: sessionManager.sessionEndTime)
            
            // Session Stats
            SessionStatsView(events: dataStore.currentSessionEvents)
            
            // Stop Button
            Button(action: {
                sessionManager.stopSession()
            }) {
                HStack(spacing: LociTheme.Spacing.small) {
                    Image(systemName: "stop.fill")
                    Text("End Session")
                }
            }
            .lociButton(.secondary, isFullWidth: true)
        }
        .padding(.vertical, LociTheme.Spacing.medium)
    }
}

// MARK: - Live Session Indicator

struct LiveSessionIndicator: View {
    let endTime: Date?
    @State private var timeRemaining = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Pulsing Live Dot
            HStack(spacing: LociTheme.Spacing.xSmall) {
                Circle()
                    .fill(LociTheme.Colors.notificationBadge)
                    .frame(width: 8, height: 8)
                    .glow(color: LociTheme.Colors.notificationBadge, radius: 6)
                    .overlay(
                        Circle()
                            .stroke(LociTheme.Colors.notificationBadge.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                            .animation(LociTheme.Animation.pulse, value: UUID())
                    )
                
                Text("SESSION ACTIVE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.notificationBadge)
            }
            
            // Timer
            Text(timeRemaining)
                .font(LociTheme.Typography.timer)
                .foregroundColor(LociTheme.Colors.mainText)
                .monospacedDigit()
        }
        .padding(.vertical, LociTheme.Spacing.large)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .fill(LociTheme.Colors.contentContainer)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                        .stroke(LociTheme.Colors.notificationBadge.opacity(0.3), lineWidth: 1)
                )
        )
        .onReceive(timer) { _ in
            updateTimeRemaining()
        }
        .onAppear {
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        guard let endTime = endTime else { return }
        let remaining = endTime.timeIntervalSince(Date())
        if remaining > 0 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let seconds = Int(remaining) % 60
            timeRemaining = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            timeRemaining = "00:00:00"
        }
    }
}

// MARK: - Session Stats View

struct SessionStatsView: View {
    let events: [ListeningEvent]
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Stats Grid
            HStack(spacing: LociTheme.Spacing.small) {
                StatCard(
                    icon: "music.note",
                    value: "\(events.count)",
                    label: "Tracks",
                    color: LociTheme.Colors.secondaryHighlight
                )
                
                StatCard(
                    icon: "building.2",
                    value: "\(uniqueLocations)",
                    label: "Locations",
                    color: LociTheme.Colors.primaryAction
                )
            }
            
            // Last Track
            if let lastEvent = events.last {
                LastTrackView(event: lastEvent)
            }
        }
    }
    
    private var uniqueLocations: Int {
        Set(events.compactMap { $0.buildingName }).count
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(color)
            
            Text(value)
                .font(LociTheme.Typography.statNumber)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Last Track View

struct LastTrackView: View {
    let event: ListeningEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
            Text("NOW PLAYING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Text(event.trackName)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
                .lineLimit(1)
            
            Text(event.artistName)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                .lineLimit(1)
            
            if let building = event.buildingName {
                HStack(spacing: LociTheme.Spacing.xxSmall) {
                    Image(systemName: "building.2")
                        .font(.system(size: 10))
                    Text(building)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer, shadowEnabled: false)
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

