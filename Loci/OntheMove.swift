import SwiftUI
import MapKit
import CoreLocation

// MARK: - On-the-Move Session View

struct OnTheMoveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var dataStore: DataStore
    
    @State private var selectedDuration: SessionDuration = .twoHours
    @State private var showingDurationInfo = false
    @State private var showingLocationRequirements = false
    @State private var isCheckingPermissions = false
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LociTheme.Spacing.large) {
                    // Header
                    OnTheMoveSessionHeader()
                    
                    // Active Session Dashboard (if session is active)
                    if sessionManager.isSessionActive && sessionManager.sessionMode == .onTheMove {
                        OnTheMoveActiveSessionCard()
                    } else {
                        // Duration Selection
                        DurationSelectionCard(
                            selectedDuration: $selectedDuration,
                            showingInfo: $showingDurationInfo
                        )
                        
                        // Location Requirements
                        LocationRequirementsCard(
                            showingDetails: $showingLocationRequirements,
                            isChecking: $isCheckingPermissions
                        )
                        
                        // Features Overview
                        OnTheMoveFeaturesCard()
                        
                        // Start Button
                        StartOnTheMoveSessionButton(
                            duration: selectedDuration,
                            canStart: canStartSession,
                            onStart: startSession
                        )
                    }
                    
                    // Battery & Privacy Info
                    OnTheMoveInfoCards()
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.large)
            }
        }
        .sheet(isPresented: $showingDurationInfo) {
            DurationInfoSheet(selectedDuration: selectedDuration)
        }
        .sheet(isPresented: $showingLocationRequirements) {
            LocationRequirementsSheet()
        }
        .onAppear {
            checkLocationPermissions()
        }
    }
    
    // MARK: - Computed Properties
    
    private var canStartSession: Bool {
        locationManager.authorizationStatus == .authorizedAlways ||
        locationManager.authorizationStatus == .authorizedWhenInUse
    }
    
    // MARK: - Actions
    
    private func checkLocationPermissions() {
        isCheckingPermissions = true
        
        // Small delay to show checking state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isCheckingPermissions = false
        }
    }
    
    private func startSession() {
        sessionManager.startSession(
            mode: .onTheMove,
            duration: selectedDuration,
            initialBuilding: nil
        )
    }
}

// MARK: - On-the-Move Session Header

struct OnTheMoveSessionHeader: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.primaryAction)
                .glow(color: LociTheme.Colors.primaryAction, radius: 12)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("On-the-Move Session")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Perfect for when you're moving around. Track your music across multiple locations with precision.")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - On-the-Move Active Session Card

struct OnTheMoveActiveSessionCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var timeElapsed = ""
    @State private var timeRemaining = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Status Header
            HStack {
                HStack(spacing: LociTheme.Spacing.small) {
                    Circle()
                        .fill(LociTheme.Colors.primaryAction)
                        .frame(width: 12, height: 12)
                        .glow(color: LociTheme.Colors.primaryAction, radius: 4)
                    
                    Text("TRACKING IN PROGRESS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                }
                
                Spacer()
                
                Text("On-the-Move")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xxSmall)
                    .background(LociTheme.Colors.disabledState.opacity(0.5))
                    .cornerRadius(LociTheme.CornerRadius.small)
            }
            
            // Timer Display
            VStack(spacing: LociTheme.Spacing.small) {
                Text(timeElapsed)
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                if !timeRemaining.isEmpty {
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        Text("Auto-stops in \(timeRemaining)")
                            .font(.system(size: 13))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(LociTheme.Colors.disabledState)
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(LociTheme.Colors.primaryGradient)
                        .frame(width: geometry.size.width * progressPercentage, height: 4)
                        .cornerRadius(2)
                        .animation(.easeInOut(duration: 0.3), value: progressPercentage)
                }
            }
            .frame(height: 4)
            
            // Session Stats
            HStack(spacing: LociTheme.Spacing.medium) {
                OnTheMoveStatItem(
                    icon: "music.note",
                    value: "\(dataStore.currentSessionEvents.count)",
                    label: "Tracks"
                )
                
                OnTheMoveStatItem(
                    icon: "building.2",
                    value: "\(uniqueLocations)",
                    label: "Places"
                )
                
                OnTheMoveStatItem(
                    icon: "location.circle",
                    value: "Every 90s",
                    label: "Updates"
                )
            }
            
            // Quick Actions
            HStack(spacing: LociTheme.Spacing.small) {
                Button("View Map") {
                    // Show session map
                }
                .lociButton(.secondary)
                
                Button("End Session") {
                    sessionManager.stopSession()
                }
                .lociButton(.primary)
            }
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
    
    private var uniqueLocations: Int {
        Set(dataStore.currentSessionEvents.compactMap { $0.buildingName }).count
    }
    
    private var progressPercentage: Double {
        guard let timeRemaining = sessionManager.getSessionTimeRemaining(),
              let elapsed = sessionManager.getSessionElapsed() else { return 0 }
        
        let totalDuration = elapsed + timeRemaining
        return totalDuration > 0 ? elapsed / totalDuration : 0
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

// MARK: - On-the-Move Stat Item

struct OnTheMoveStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.primaryAction)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.small)
        .background(LociTheme.Colors.appBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Duration Selection Card

struct DurationSelectionCard: View {
    @Binding var selectedDuration: SessionDuration
    @Binding var showingInfo: Bool
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Session Duration")
                        .font(LociTheme.Typography.subheading)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Choose how long to track (max 6 hours)")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
                
                Button(action: { showingInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                }
            }
            
            // Duration Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: LociTheme.Spacing.small) {
                ForEach(SessionDuration.onTheMoveOptions, id: \.self) { duration in
                    DurationGridItem(
                        duration: duration,
                        isSelected: selectedDuration == duration,
                        isRecommended: duration == .twoHours
                    ) {
                        withAnimation(LociTheme.Animation.smoothEaseInOut) {
                            selectedDuration = duration
                        }
                    }
                }
            }
            
            // Selected Duration Info
            DurationSummaryRow(duration: selectedDuration)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Duration Grid Item

struct DurationGridItem: View {
    let duration: SessionDuration
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: LociTheme.Spacing.xSmall) {
                Text(duration.displayText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
                
                if isRecommended && !isSelected {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                } else if isSelected {
                    Text("Selected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(selectedTextColor)
                }
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .overlay(overlayBorder)
            .cornerRadius(LociTheme.CornerRadius.medium)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(LociTheme.Animation.bouncy, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColor: Color {
        isSelected ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText
    }
    
    private var selectedTextColor: Color {
        LociTheme.Colors.appBackground.opacity(0.8)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return LociTheme.Colors.primaryAction
        } else if isRecommended {
            return LociTheme.Colors.secondaryHighlight.opacity(0.1)
        } else {
            return LociTheme.Colors.disabledState
        }
    }
    
    @ViewBuilder
    private var overlayBorder: some View {
        if !isSelected && isRecommended {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .stroke(LociTheme.Colors.secondaryHighlight, lineWidth: 1.5)
        }
    }
}

// MARK: - Duration Summary Row

struct DurationSummaryRow: View {
    let duration: SessionDuration
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("Session will run for \(duration.displayText)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Ends at \(endTime) • Battery: \(batteryImpact)")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Image(systemName: batteryIcon)
                .font(.system(size: 16))
                .foregroundColor(batteryColor)
        }
        .padding(LociTheme.Spacing.small)
        .background(LociTheme.Colors.primaryAction.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
    
    private var endTime: String {
        let endDate = Date().addingTimeInterval(duration.timeInterval)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endDate)
    }
    
    private var batteryImpact: String {
        switch duration {
        case .thirtyMinutes: return "Minimal"
        case .oneHour: return "Low"
        case .twoHours: return "Low"
        case .fourHours: return "Moderate"
        case .sixHours: return "Higher"
        default: return "Moderate"
        }
    }
    
    private var batteryIcon: String {
        switch duration {
        case .thirtyMinutes, .oneHour: return "battery.100"
        case .twoHours: return "battery.75"
        case .fourHours: return "battery.50"
        case .sixHours: return "battery.25"
        default: return "battery.50"
        }
    }
    
    private var batteryColor: Color {
        switch duration {
        case .thirtyMinutes, .oneHour, .twoHours: return LociTheme.Colors.secondaryHighlight
        case .fourHours: return LociTheme.Colors.primaryAction
        case .sixHours: return Color.orange
        default: return LociTheme.Colors.primaryAction
        }
    }
}

// MARK: - Location Requirements Card

struct LocationRequirementsCard: View {
    @Binding var showingDetails: Bool
    @Binding var isChecking: Bool
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Location Requirements")
                        .font(LociTheme.Typography.subheading)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Continuous tracking needs location permission")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
                
                Button(action: { showingDetails = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                }
            }
            
            // Permission Status
            HStack(spacing: LociTheme.Spacing.medium) {
                Image(systemName: permissionIcon)
                    .font(.system(size: 20))
                    .foregroundColor(permissionColor)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(permissionTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(permissionDescription)
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
                
                if !hasRequiredPermission && !isChecking {
                    Button("Enable") {
                        locationManager.requestPermissions()
                    }
                    .lociButton(.secondary)
                } else if isChecking {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.primaryAction))
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
    
    private var hasRequiredPermission: Bool {
        locationManager.authorizationStatus == .authorizedAlways ||
        locationManager.authorizationStatus == .authorizedWhenInUse
    }
    
    private var permissionIcon: String {
        if hasRequiredPermission {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var permissionColor: Color {
        hasRequiredPermission ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.primaryAction
    }
    
    private var permissionTitle: String {
        if hasRequiredPermission {
            return "Location Access Enabled"
        } else {
            return "Location Access Required"
        }
    }
    
    private var permissionDescription: String {
        if hasRequiredPermission {
            return "Ready for continuous tracking"
        } else {
            return "Tap Enable to allow location tracking"
        }
    }
}

// MARK: - On-the-Move Features Card

struct OnTheMoveFeaturesCard: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("What You Get")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                OnTheMoveFeatureRow(
                    icon: "location.fill.viewfinder",
                    title: "Precise Tracking",
                    description: "GPS updates every 90 seconds for accurate location data"
                )
                
                OnTheMoveFeatureRow(
                    icon: "building.2.crop.circle",
                    title: "Multi-Location",
                    description: "Track music across different buildings and venues"
                )
                
                OnTheMoveFeatureRow(
                    icon: "clock.badge.checkmark",
                    title: "Auto-Stop",
                    description: "Session automatically ends at your chosen time"
                )
                
                OnTheMoveFeatureRow(
                    icon: "map.fill",
                    title: "Journey Map",
                    description: "See your music journey on an interactive map"
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - On-the-Move Feature Row

struct OnTheMoveFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.primaryAction)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
}

// MARK: - On-the-Move Info Cards

struct OnTheMoveInfoCards: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Battery Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Battery Usage")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Continuous GPS tracking uses more battery than one-place mode")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.primaryAction.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
            
            // Accuracy Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "target")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("High Accuracy")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Perfect for tracking music during commutes, workouts, or travel")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
        }
    }
}

// MARK: - Start On-the-Move Session Button

struct StartOnTheMoveSessionButton: View {
    let duration: SessionDuration
    let canStart: Bool
    let onStart: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "play.fill")
                Text("Start \(duration.displayText) Session")
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.6)
    }
}

// MARK: - Duration Info Sheet

struct DurationInfoSheet: View {
    let selectedDuration: SessionDuration
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: LociTheme.Spacing.large) {
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Text("Session Duration Guide")
                            .font(LociTheme.Typography.heading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("Choose the right duration for your activity")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: LociTheme.Spacing.medium) {
                        ForEach(SessionDuration.onTheMoveOptions, id: \.self) { duration in
                            DurationInfoRow(
                                duration: duration,
                                isSelected: duration == selectedDuration
                            )
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Duration Info")
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

// MARK: - Duration Info Row

struct DurationInfoRow: View {
    let duration: SessionDuration
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                HStack {
                    Text(duration.displayText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    if isSelected {
                        Text("Selected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                            .padding(.horizontal, LociTheme.Spacing.xSmall)
                            .padding(.vertical, 2)
                            .background(LociTheme.Colors.secondaryHighlight.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(useCaseFor(duration))
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text("Battery: \(batteryImpactFor(duration))")
                    .font(.system(size: 12))
                    .foregroundColor(batteryColorFor(duration))
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .fill(isSelected ? LociTheme.Colors.secondaryHighlight.opacity(0.1) : LociTheme.Colors.contentContainer)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                        .stroke(isSelected ? LociTheme.Colors.secondaryHighlight : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private func useCaseFor(_ duration: SessionDuration) -> String {
        switch duration {
        case .thirtyMinutes: return "Quick coffee run or short commute"
        case .oneHour: return "Lunch break, gym session, or short trip"
        case .twoHours: return "Movie, study session, or moderate commute"
        case .fourHours: return "Work session, long trip, or day out"
        case .sixHours: return "Full work day, travel, or extended outing"
        default: return "General use"
        }
    }
    
    private func batteryImpactFor(_ duration: SessionDuration) -> String {
        switch duration {
        case .thirtyMinutes: return "Minimal impact"
        case .oneHour: return "Low impact"
        case .twoHours: return "Low to moderate impact"
        case .fourHours: return "Moderate impact"
        case .sixHours: return "Higher impact"
        default: return "Moderate impact"
        }
    }
    
    private func batteryColorFor(_ duration: SessionDuration) -> Color {
        switch duration {
        case .thirtyMinutes, .oneHour: return LociTheme.Colors.secondaryHighlight
        case .twoHours: return LociTheme.Colors.primaryAction
        case .fourHours: return Color.orange
        case .sixHours: return Color.red
        default: return LociTheme.Colors.primaryAction
        }
    }
}

// MARK: - Location Requirements Sheet

struct LocationRequirementsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: LociTheme.Spacing.large) {
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 48))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text("Location Access Required")
                            .font(LociTheme.Typography.heading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("On-the-Move sessions need continuous location access to track your music across different places accurately.")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: LociTheme.Spacing.medium) {
                        LocationRequirementRow(
                            icon: "location.fill",
                            title: "GPS Tracking",
                            description: "Updates your location every 90 seconds"
                        )
                        
                        LocationRequirementRow(
                            icon: "building.2",
                            title: "Building Detection",
                            description: "Automatically identifies the buildings you visit"
                        )
                        
                        LocationRequirementRow(
                            icon: "lock.shield",
                            title: "Privacy Protected",
                            description: "Location data stays on your device unless you share"
                        )
                    }
                    
                    if locationManager.authorizationStatus != .authorizedAlways &&
                       locationManager.authorizationStatus != .authorizedWhenInUse {
                        Button("Enable Location Access") {
                            locationManager.requestPermissions()
                        }
                        .lociButton(.primary, isFullWidth: true)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Location Requirements")
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

// MARK: - Location Requirement Row

struct LocationRequirementRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(LociTheme.Colors.primaryAction)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}
