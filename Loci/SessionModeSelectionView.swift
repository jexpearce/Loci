import SwiftUI

// MARK: - Session Mode Selection View

struct SessionModeSelectionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var selectedMode: SessionMode?
    @State private var showingManualSession = false
    @State private var showingPassiveSession = false
    @State private var showingModeTooltip: SessionMode?
    @State private var showingPermissionEducation = false
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LociTheme.Spacing.large) {
                    // Header
                    SessionModeHeader()
                    
                    // Mode Selection Cards
                    VStack(spacing: LociTheme.Spacing.medium) {
                        // Manual Mode
                        SessionModeCard(
                            mode: .manual,
                            title: "Manual Region",
                            subtitle: "Maximum Privacy",
                            description: "Forgot to start? Assign your listening to any location manually.",
                            icon: "map.fill",
                            color: LociTheme.Colors.primaryAction,
                            features: [
                                "No location permissions needed",
                                "You choose the region name",
                                "Tracks collected at session end",
                                "Perfect for privacy-conscious users"
                            ],
                            isSelected: selectedMode == .manual,
                            isPremium: false,
                            onInfoTap: { showingModeTooltip = .manual },
                            action: {
                                selectedMode = .manual
                                showingManualSession = true
                            }
                        )
                        
                        // Passive Mode
                        SessionModeCard(
                            mode: .passive,
                            title: "Stay-in-Place",
                            subtitle: "One-Time Location",
                            description: "I'll stay in one spot—pin all songs to this building.",
                            icon: "location.square.fill",
                            color: LociTheme.Colors.secondaryHighlight,
                            features: [
                                "One location check at start",
                                "Minimal battery usage",
                                "Perfect for coffee shops & libraries",
                                "\"When in Use\" permission only"
                            ],
                            isSelected: selectedMode == .passive,
                            isPremium: false,
                            onInfoTap: { showingModeTooltip = .passive },
                            action: {
                                selectedMode = .passive
                                showingPassiveSession = true
                            }
                        )
                        
                        // Active Mode
                        SessionModeCard(
                            mode: .active,
                            title: "Live Tracking",
                            subtitle: "Real-Time Map",
                            description: "Follow me around and map every place I listen.",
                            icon: "location.fill.viewfinder",
                            color: LociTheme.Colors.notificationBadge,
                            features: [
                                "Real-time location updates",
                                "Live music mapping",
                                "Auto-stops after 6 hours",
                                "\"Always\" permission required"
                            ],
                            isSelected: selectedMode == .active,
                            isPremium: true,
                            onInfoTap: { showingModeTooltip = .active },
                            action: {
                                selectedMode = .active
                                if locationManager.authorizationStatus == .authorizedAlways {
                                    sessionManager.startSession(mode: .active)
                                } else {
                                    showingPermissionEducation = true
                                }
                            }
                        )
                    }
                    
                    // Permission Status
                    PermissionStatusCard(onLearnMore: { showingPermissionEducation = true })
                    
                    // Recommendation
                    RecommendationCard()
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.large)
            }
        }
        .sheet(isPresented: $showingManualSession) {
            ManualSessionView()
        }
        .sheet(isPresented: $showingPassiveSession) {
            PassiveSessionView()
        }
        .sheet(item: $showingModeTooltip) { mode in
            ModeTooltipView(mode: mode)
        }
        .sheet(isPresented: $showingPermissionEducation) {
            PermissionEducationView()
        }
    }
}

// MARK: - Session Mode Header

struct SessionModeHeader: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "music.note.house")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
            
            Text("Choose Your Session Mode")
                .font(LociTheme.Typography.heading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text("Different modes for different needs. All track your Spotify listening with location context.")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Session Mode Card

struct SessionModeCard: View {
    let mode: SessionMode
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: Color
    let features: [String]
    let isSelected: Bool
    let isPremium: Bool
    let onInfoTap: () -> Void
    let action: () -> Void
    
    init(mode: SessionMode, title: String, subtitle: String, description: String, icon: String, color: Color, features: [String], isSelected: Bool, isPremium: Bool = false, onInfoTap: @escaping () -> Void, action: @escaping () -> Void) {
        self.mode = mode
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.icon = icon
        self.color = color
        self.features = features
        self.isSelected = isSelected
        self.isPremium = isPremium
        self.onInfoTap = onInfoTap
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        HStack(spacing: LociTheme.Spacing.small) {
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(color)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: LociTheme.Spacing.xSmall) {
                                    Text(title)
                                        .font(LociTheme.Typography.subheading)
                                        .foregroundColor(LociTheme.Colors.mainText)
                                    
                                    if isPremium {
                                        Text("PREMIUM")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(LociTheme.Colors.appBackground)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(LociTheme.Colors.notificationBadge)
                                            .cornerRadius(4)
                                    }
                                }
                                
                                Text(subtitle)
                                    .font(LociTheme.Typography.caption)
                                    .foregroundColor(color)
                            }
                        }
                        
                        Text(description)
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: LociTheme.Spacing.xSmall) {
                        Button(action: onInfoTap) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(LociTheme.Colors.subheadText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
                
                // Features
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: LociTheme.Spacing.xSmall) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(color.opacity(0.7))
                            
                            Text(feature)
                                .font(LociTheme.Typography.caption)
                                .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(LociTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                    .fill(LociTheme.Colors.contentContainer)
                    .overlay(
                        RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                            .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Permission Status Card

struct PermissionStatusCard: View {
    @EnvironmentObject var locationManager: LocationManager
    let onLearnMore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            HStack {
                Image(systemName: permissionIcon)
                    .font(.system(size: 16))
                    .foregroundColor(permissionColor)
                
                Text("Location Permissions")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Button("Learn More", action: onLearnMore)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
            Text(permissionStatusText)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
        }
        .padding(LociTheme.Spacing.medium)
        .background(permissionColor.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
    
    private var permissionIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "checkmark.circle.fill"
        case .authorizedWhenInUse:
            return "location.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    private var permissionColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return LociTheme.Colors.secondaryHighlight
        case .authorizedWhenInUse:
            return LociTheme.Colors.notificationBadge
        case .denied, .restricted:
            return LociTheme.Colors.primaryAction
        default:
            return LociTheme.Colors.subheadText
        }
    }
    
    private var permissionStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "✅ All modes available. Live Tracking can run in background."
        case .authorizedWhenInUse:
            return "⚠️ Manual and Stay-in-Place available. Live Tracking needs \"Always\" permission."
        case .denied, .restricted:
            return "❌ Only Manual mode available. Enable location access for other modes."
        default:
            return "❓ Location permission not determined. Tap modes to request access."
        }
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("Recommendation")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            Text("New to Loci? Start with **Stay-in-Place** mode for the best balance of privacy and functionality. You can always upgrade to Live Tracking later.")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Mode Tooltip View

struct ModeTooltipView: View {
    let mode: SessionMode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.large) {
                    // Header
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                        HStack {
                            Image(systemName: modeIcon)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(modeColor)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(modeTitle)
                                    .font(LociTheme.Typography.heading)
                                    .foregroundColor(LociTheme.Colors.mainText)
                                
                                Text(modeSubtitle)
                                    .font(LociTheme.Typography.body)
                                    .foregroundColor(modeColor)
                            }
                            
                            Spacer()
                        }
                        
                        Text(modeDescription)
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                    }
                    
                    // How it works
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                        Text("How it works")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
                            ForEach(Array(modeSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: LociTheme.Spacing.small) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(LociTheme.Colors.appBackground)
                                        .frame(width: 24, height: 24)
                                        .background(modeColor)
                                        .clipShape(Circle())
                                    
                                    Text(step)
                                        .font(LociTheme.Typography.body)
                                        .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // Best for
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                        Text("Best for")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                            ForEach(modeBestFor, id: \.self) { useCase in
                                HStack(spacing: LociTheme.Spacing.xSmall) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(modeColor)
                                    
                                    Text(useCase)
                                        .font(LociTheme.Typography.body)
                                        .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // Privacy & permissions
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                        Text("Privacy & Permissions")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text(modePrivacyInfo)
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                    }
                }
                .padding(LociTheme.Spacing.medium)
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Mode Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
        }
    }
    
    private var modeIcon: String {
        switch mode {
        case .manual: return "map.fill"
        case .passive: return "location.square.fill"
        case .active: return "location.fill.viewfinder"
        case .unknown: return "questionmark.circle"
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
    
    private var modeTitle: String {
        switch mode {
        case .manual: return "Manual Region"
        case .passive: return "Stay-in-Place"
        case .active: return "Live Tracking"
        case .unknown: return "Unknown Mode"
        }
    }
    
    private var modeSubtitle: String {
        switch mode {
        case .manual: return "Maximum Privacy"
        case .passive: return "One-Time Location"
        case .active: return "Real-Time Map"
        case .unknown: return "Unknown"
        }
    }
    
    private var modeDescription: String {
        switch mode {
        case .manual:
            return "Perfect for when you forgot to start a session or want complete control over your location data. You manually assign your listening history to any location you choose."
        case .passive:
            return "Ideal for stationary listening sessions. We check your location once at the start, then track all your music to that single building without any further location requests."
        case .active:
            return "The full Loci experience. Real-time location tracking creates a live map of your music journey as you move between different places throughout your day."
        case .unknown:
            return "Unknown session mode."
        }
    }
    
    private var modeSteps: [String] {
        switch mode {
        case .manual:
            return [
                "Choose any location from a map or search",
                "Start your session with that location",
                "Listen to music normally on Spotify",
                "End session to collect your listening history",
                "All tracks are assigned to your chosen location"
            ]
        case .passive:
            return [
                "Grant \"When in Use\" location permission",
                "We check your current location once",
                "Session starts with that building locked in",
                "Listen to music normally on Spotify",
                "All tracks are mapped to that single location"
            ]
        case .active:
            return [
                "Grant \"Always\" location permission",
                "Session starts with continuous tracking",
                "Move around and listen to music normally",
                "Each track is mapped to where you heard it",
                "Session auto-stops after 6 hours for battery"
            ]
        case .unknown:
            return []
        }
    }
    
    private var modeBestFor: [String] {
        switch mode {
        case .manual:
            return [
                "Privacy-conscious users",
                "Retrospective session logging",
                "When you forgot to start tracking",
                "Shared or public devices",
                "No location permissions needed"
            ]
        case .passive:
            return [
                "Coffee shops and cafes",
                "Libraries and study spaces",
                "Home listening sessions",
                "Minimal battery usage",
                "Balanced privacy and functionality"
            ]
        case .active:
            return [
                "Walking or commuting",
                "Exploring new neighborhoods",
                "Music discovery journeys",
                "Creating detailed listening maps",
                "Social sharing and discovery"
            ]
        case .unknown:
            return []
        }
    }
    
    private var modePrivacyInfo: String {
        switch mode {
        case .manual:
            return "🔒 Maximum privacy. No location permissions required. You have complete control over what location data is stored. Location is only what you manually specify."
        case .passive:
            return "🛡️ Minimal location usage. Only one location check at session start. Requires \"When in Use\" permission. Your exact location is stored but not continuously tracked."
        case .active:
            return "📍 Continuous location tracking. Requires \"Always\" permission for background operation. Creates detailed location history for the most accurate music mapping experience."
        case .unknown:
            return "Unknown privacy implications."
        }
    }
}

// MARK: - Permission Education View

struct PermissionEducationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.large) {
                    // Header
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                            .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
                        
                        Text("Why Location Permissions?")
                            .font(LociTheme.Typography.heading)
                            .foregroundColor(LociTheme.Colors.mainText)
                            .multilineTextAlignment(.center)
                        
                        Text("Loci maps your music to places. Here's exactly how we use location data for each mode.")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    
                    // Permission levels
                    VStack(spacing: LociTheme.Spacing.medium) {
                        PermissionLevelCard(
                            title: "No Permission",
                            subtitle: "Manual Mode Only",
                            icon: "hand.raised.fill",
                            color: LociTheme.Colors.primaryAction,
                            description: "You manually choose locations. Perfect for privacy.",
                            features: ["Complete privacy control", "No GPS usage", "Manual location assignment"]
                        )
                        
                        PermissionLevelCard(
                            title: "\"When in Use\"",
                            subtitle: "Stay-in-Place Mode",
                            icon: "location.circle.fill",
                            color: LociTheme.Colors.secondaryHighlight,
                            description: "One location check when you start a session.",
                            features: ["Single location ping", "Minimal battery usage", "Only when app is open"]
                        )
                        
                        PermissionLevelCard(
                            title: "\"Always\"",
                            subtitle: "Live Tracking Mode",
                            icon: "location.fill",
                            color: LociTheme.Colors.notificationBadge,
                            description: "Continuous tracking for real-time music mapping.",
                            features: ["Background location updates", "Real-time music mapping", "Auto-stops after 6 hours"]
                        )
                    }
                    
                    // Privacy commitment
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                        Text("Our Privacy Commitment")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
                            PrivacyPointView(
                                icon: "lock.shield.fill",
                                text: "Location data stays on your device"
                            )
                            PrivacyPointView(
                                icon: "eye.slash.fill",
                                text: "We never sell or share your location"
                            )
                            PrivacyPointView(
                                icon: "trash.fill",
                                text: "Delete sessions anytime in Settings"
                            )
                            PrivacyPointView(
                                icon: "hand.raised.fill",
                                text: "You control what gets shared socially"
                            )
                        }
                    }
                    
                    // Action buttons
                    VStack(spacing: LociTheme.Spacing.medium) {
                        if locationManager.authorizationStatus == .notDetermined {
                            Button("Grant Location Permission") {
                                locationManager.requestPermissions()
                            }
                            .lociButton(.primary, isFullWidth: true)
                        }
                        
                        Button("Open Settings") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .lociButton(.secondary, isFullWidth: true)
                    }
                }
                .padding(LociTheme.Spacing.medium)
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Location Permissions")
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

// MARK: - Supporting Views

struct PermissionLevelCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let description: String
    let features: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LociTheme.Typography.subheading)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(subtitle)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(color)
                }
                
                Spacer()
            }
            
            Text(description)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(color.opacity(0.7))
                        
                        Text(feature)
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

struct PrivacyPointView: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            Text(text)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
            
            Spacer()
        }
    }
} 