import SwiftUI

struct LeaderboardConsentView: View {
    @Binding var isPresented: Bool
    @Binding var privacySettings: LeaderboardPrivacySettings
    let onConsent: (LeaderboardPrivacySettings) -> Void
    
    @State private var selectedPrivacyLevel: LeaderboardPrivacyLevel = .publicGlobal
    @State private var shareArtistData = true
    @State private var shareTotalTime = true
    @State private var currentStep = 0
    
    private let steps = ["Introduction", "Privacy Level", "Data Types", "Review"]
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    ConsentProgressIndicator(currentStep: currentStep, totalSteps: steps.count)
                        .padding(.top, LociTheme.Spacing.medium)
                        .padding(.horizontal, LociTheme.Spacing.medium)
                    
                    // Content
                    TabView(selection: $currentStep) {
                        IntroductionStep()
                            .tag(0)
                        
                        PrivacyLevelStep(selectedLevel: $selectedPrivacyLevel)
                            .tag(1)
                        
                        DataTypesStep(
                            shareArtistData: $shareArtistData,
                            shareTotalTime: $shareTotalTime,
                            privacyLevel: selectedPrivacyLevel
                        )
                        .tag(2)
                        
                        ReviewStep(
                            privacyLevel: selectedPrivacyLevel,
                            shareArtistData: shareArtistData,
                            shareTotalTime: shareTotalTime
                        )
                        .tag(3)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)
                    
                    // Navigation buttons
                    ConsentNavigationButtons(
                        currentStep: $currentStep,
                        totalSteps: steps.count,
                        canProceed: canProceedFromCurrentStep,
                        onCancel: { isPresented = false },
                        onComplete: completeConsent
                    )
                    .padding(LociTheme.Spacing.medium)
                }
            }
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
    }
    
    private var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case 0: return true // Introduction
        case 1: return true // Privacy level always valid
        case 2: return selectedPrivacyLevel == .privateMode || shareArtistData || shareTotalTime
        case 3: return true // Review
        default: return false
        }
    }
    
    private func completeConsent() {
        let finalSettings = LeaderboardPrivacySettings(
            privacyLevel: selectedPrivacyLevel,
            shareArtistData: shareArtistData,
            shareTotalTime: shareTotalTime,
            hasGivenConsent: true,
            consentDate: Date()
        )
        
        privacySettings = finalSettings
        onConsent(finalSettings)
        isPresented = false
    }
}

// MARK: - Progress Indicator

struct ConsentProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            HStack {
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Spacer()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LociTheme.Colors.disabledState)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LociTheme.Colors.secondaryHighlight)
                        .frame(width: geometry.size.width * (Double(currentStep + 1) / Double(totalSteps)), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Step 1: Introduction

struct IntroductionStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: LociTheme.Spacing.large) {
                VStack(spacing: LociTheme.Spacing.medium) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
                    
                    Text("Join the Leaderboards")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                    
                    Text("See how your music taste compares with others in your area and around the world")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: LociTheme.Spacing.medium) {
                    Text("What You'll Get")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    VStack(spacing: LociTheme.Spacing.small) {
                        ConsentFeatureRow(
                            icon: "building.2",
                            title: "Building Leaderboards",
                            description: "Compete with people in your building or workplace"
                        )
                        
                        ConsentFeatureRow(
                            icon: "map",
                            title: "Regional Rankings",
                            description: "See how you rank in your neighborhood or city"
                        )
                        
                        ConsentFeatureRow(
                            icon: "globe",
                            title: "Global Competition",
                            description: "Compare with music lovers worldwide"
                        )
                        
                        ConsentFeatureRow(
                            icon: "music.note",
                            title: "Artist-Specific Rankings",
                            description: "Find other super fans of your favorite artists"
                        )
                    }
                }
                
                VStack(spacing: LociTheme.Spacing.small) {
                    HStack {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 16))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text("Your Privacy is Protected")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Spacer()
                    }
                    
                    Text("You control exactly what data you share and how you appear on leaderboards. You can change these settings anytime.")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.leading)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.primaryAction.opacity(0.1))
                .cornerRadius(LociTheme.CornerRadius.medium)
            }
            .padding(LociTheme.Spacing.medium)
        }
    }
}

// MARK: - Step 2: Privacy Level

struct PrivacyLevelStep: View {
    @Binding var selectedLevel: LeaderboardPrivacyLevel
    
    var body: some View {
        ScrollView {
            VStack(spacing: LociTheme.Spacing.large) {
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Choose Your Privacy Level")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                    
                    Text("How do you want to appear on leaderboards?")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: LociTheme.Spacing.medium) {
                    ForEach(LeaderboardPrivacyLevel.allCases, id: \.self) { level in
                        PrivacyLevelCard(
                            level: level,
                            isSelected: selectedLevel == level
                        ) {
                            selectedLevel = level
                        }
                    }
                }
            }
            .padding(LociTheme.Spacing.medium)
        }
    }
}

struct PrivacyLevelCard: View {
    let level: LeaderboardPrivacyLevel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.medium) {
                HStack {
                    Image(systemName: iconForLevel)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.displayName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text(level.description)
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                }
                
                if level != .privateMode {
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        Text("Appears on:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .textCase(.uppercase)
                        
                        HStack(spacing: LociTheme.Spacing.small) {
                            ForEach(LocationScope.allCases) { scope in
                                if level.includesScope(scope) {
                                    ScopeTag(scope: scope, isIncluded: true)
                                } else {
                                    ScopeTag(scope: scope, isIncluded: false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(LociTheme.Spacing.medium)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .cornerRadius(LociTheme.CornerRadius.large)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(LociTheme.Animation.bouncy, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconForLevel: String {
        switch level {
        case .privateMode: return "lock.fill"
        case .anonymous: return "person.circle"
        case .publicRegional: return "map.circle"
        case .publicGlobal: return "globe"
        }
    }
    
    private var iconColor: Color {
        isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.subheadText
    }
    
    private var backgroundColor: Color {
        isSelected ? LociTheme.Colors.contentContainer : LociTheme.Colors.contentContainer.opacity(0.5)
    }
    
    @ViewBuilder
    private var borderOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .stroke(LociTheme.Colors.secondaryHighlight, lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .stroke(LociTheme.Colors.disabledState.opacity(0.3), lineWidth: 1)
        }
    }
}

struct ScopeTag: View {
    let scope: LocationScope
    let isIncluded: Bool
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: scope.icon)
                .font(.system(size: 10))
            
            Text(scope.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isIncluded ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
        .padding(.horizontal, LociTheme.Spacing.xSmall)
        .padding(.vertical, 2)
        .background(
            isIncluded ? 
            LociTheme.Colors.secondaryHighlight.opacity(0.2) :
            LociTheme.Colors.disabledState.opacity(0.1)
        )
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Step 3: Data Types

struct DataTypesStep: View {
    @Binding var shareArtistData: Bool
    @Binding var shareTotalTime: Bool
    let privacyLevel: LeaderboardPrivacyLevel
    
    var body: some View {
        ScrollView {
            VStack(spacing: LociTheme.Spacing.large) {
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("What Data to Share")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                    
                    if privacyLevel == .privateMode {
                        Text("You selected private mode, so no data will be shared.")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Choose what music data you want to include in leaderboards")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    }
                }
                
                if privacyLevel != .privateMode {
                    VStack(spacing: LociTheme.Spacing.medium) {
                        DataTypeCard(
                            dataType: .totalListeningTime,
                            isEnabled: $shareTotalTime,
                            privacyLevel: privacyLevel
                        )
                        
                        DataTypeCard(
                            dataType: .topArtists,
                            isEnabled: $shareArtistData,
                            privacyLevel: privacyLevel
                        )
                        
                        // Location is always included if not private
                        StaticDataTypeCard(
                            dataType: .location,
                            privacyLevel: privacyLevel
                        )
                    }
                    
                    if !shareArtistData && !shareTotalTime {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(LociTheme.Colors.primaryAction)
                            
                            Text("You must select at least one data type to participate in leaderboards")
                                .font(.system(size: 14))
                                .foregroundColor(LociTheme.Colors.primaryAction)
                        }
                        .padding(LociTheme.Spacing.medium)
                        .background(LociTheme.Colors.primaryAction.opacity(0.1))
                        .cornerRadius(LociTheme.CornerRadius.medium)
                    }
                } else {
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 48))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        Text("Your data will remain completely private")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("You can always change this later in Settings")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(LociTheme.Spacing.large)
                    .background(LociTheme.Colors.contentContainer.opacity(0.5))
                    .cornerRadius(LociTheme.CornerRadius.large)
                }
            }
            .padding(LociTheme.Spacing.medium)
        }
    }
}

struct DataTypeCard: View {
    let dataType: LeaderboardDataType
    @Binding var isEnabled: Bool
    let privacyLevel: LeaderboardPrivacyLevel
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            HStack(spacing: LociTheme.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: dataType.icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                    Text(dataType.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(dataType.description)
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: LociTheme.Colors.secondaryHighlight))
            }
            .padding(LociTheme.Spacing.medium)
            .background(backgroundColor)
            .cornerRadius(LociTheme.CornerRadius.medium)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconColor: Color {
        isEnabled ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.subheadText
    }
    
    private var iconBackgroundColor: Color {
        isEnabled ? LociTheme.Colors.secondaryHighlight.opacity(0.2) : LociTheme.Colors.disabledState.opacity(0.2)
    }
    
    private var backgroundColor: Color {
        isEnabled ? LociTheme.Colors.contentContainer : LociTheme.Colors.contentContainer.opacity(0.5)
    }
}

struct StaticDataTypeCard: View {
    let dataType: LeaderboardDataType
    let privacyLevel: LeaderboardPrivacyLevel
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(LociTheme.Colors.primaryAction.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: dataType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(LociTheme.Colors.primaryAction)
            }
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                Text(dataType.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Required for regional leaderboards")
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.primaryAction)
            }
            
            Spacer()
            
            Text("Always")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(LociTheme.Colors.primaryAction)
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.primaryAction.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Step 4: Review

struct ReviewStep: View {
    let privacyLevel: LeaderboardPrivacyLevel
    let shareArtistData: Bool
    let shareTotalTime: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: LociTheme.Spacing.large) {
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Review Your Choices")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                    
                    Text("Here's what you've selected. You can change these settings anytime.")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: LociTheme.Spacing.medium) {
                    ReviewSection(title: "Privacy Level") {
                        ReviewItem(
                            icon: iconForPrivacyLevel,
                            title: privacyLevel.displayName,
                            description: privacyLevel.description
                        )
                    }
                    
                    if privacyLevel != .privateMode {
                        ReviewSection(title: "Data Sharing") {
                            if shareTotalTime {
                                ReviewItem(
                                    icon: "clock",
                                    title: "Total Listening Time",
                                    description: "Your total minutes will appear on leaderboards"
                                )
                            }
                            
                            if shareArtistData {
                                ReviewItem(
                                    icon: "music.note",
                                    title: "Top Artists",
                                    description: "Your most played artists will appear on leaderboards"
                                )
                            }
                            
                            ReviewItem(
                                icon: "location.circle",
                                title: "General Location",
                                description: "Needed to show you in regional leaderboards"
                            )
                        }
                        
                        ReviewSection(title: "Leaderboard Participation") {
                            ForEach(LocationScope.allCases) { scope in
                                if privacyLevel.includesScope(scope) {
                                    ReviewItem(
                                        icon: scope.icon,
                                        title: scope.displayName,
                                        description: participationDescription(for: scope)
                                    )
                                }
                            }
                        }
                    }
                }
                
                VStack(spacing: LociTheme.Spacing.small) {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        
                        Text("Privacy Reminder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Spacer()
                    }
                    
                    Text("• You can change these settings anytime in the app\n• Your exact location is never shared\n• You can delete your data anytime\n• Only aggregated, anonymized data is used")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.leading)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
                .cornerRadius(LociTheme.CornerRadius.medium)
            }
            .padding(LociTheme.Spacing.medium)
        }
    }
    
    private var iconForPrivacyLevel: String {
        switch privacyLevel {
        case .privateMode: return "lock.fill"
        case .anonymous: return "person.circle"
        case .publicRegional: return "map.circle"
        case .publicGlobal: return "globe"
        }
    }
    
    private func participationDescription(for scope: LocationScope) -> String {
        let nameType = privacyLevel.showsRealName ? "with your username" : "anonymously"
        
        switch scope {
        case .building: return "Compete with people in your building \(nameType)"
        case .region: return "Compete with people in your area \(nameType)"
        case .global: return "Compete with users worldwide \(nameType)"
        }
    }
}

struct ReviewSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: LociTheme.Spacing.xSmall) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.contentContainer)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

struct ReviewItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
        }
    }
}

// MARK: - Supporting Views

struct ConsentFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
        }
    }
}

struct ConsentNavigationButtons: View {
    @Binding var currentStep: Int
    let totalSteps: Int
    let canProceed: Bool
    let onCancel: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation(.easeInOut) {
                        currentStep -= 1
                    }
                }
                .lociButton(.secondary)
            } else {
                Button("Cancel") {
                    onCancel()
                }
                .lociButton(.secondary)
            }
            
            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation(.easeInOut) {
                        currentStep += 1
                    }
                }
                .lociButton(.primary)
                .disabled(!canProceed)
            } else {
                Button("Join Leaderboards") {
                    onComplete()
                }
                .lociButton(.gradient, isFullWidth: true)
                .disabled(!canProceed)
            }
        }
    }
} 