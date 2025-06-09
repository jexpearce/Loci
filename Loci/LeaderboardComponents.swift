import SwiftUI

// MARK: - Scope Indicator

struct ScopeIndicator: View {
    let scopes: [LocationScope]
    let currentIndex: Int
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xSmall) {
            ForEach(0..<scopes.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                    .animation(LociTheme.Animation.bouncy, value: currentIndex)
            }
        }
    }
}

// MARK: - Leaderboard Type Switcher

struct LeaderboardTypeSwitcher: View {
    @Binding var selectedType: LeaderboardType
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardType.allCases) { type in
                Button(action: { selectedType = type }) {
                    VStack(spacing: LociTheme.Spacing.xSmall) {
                        Text(type.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedType == type ? LociTheme.Colors.mainText : LociTheme.Colors.subheadText)
                        
                        Text(type.description)
                            .font(.system(size: 11))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LociTheme.Spacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                            .fill(selectedType == type ? LociTheme.Colors.primaryAction.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(LociTheme.Colors.disabledState.opacity(0.3))
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

// MARK: - Scope Header

struct ScopeHeader: View {
    let scope: LocationScope
    let type: LeaderboardType
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            HStack {
                Image(systemName: scope.icon)
                    .font(.system(size: 20))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    if type == .artistMinutes, let artist = leaderboardManager.topArtist {
                        Text("Top \(artist) listeners")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    } else {
                        Text("Total listening time")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
                
                Spacer()
                
                if let summary = leaderboardManager.userSummary,
                   let bestRanking = summary.bestRanking,
                   bestRanking.scope == scope && bestRanking.type == type {
                    
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Text("#\(bestRanking.rank)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        
                        Text("YOU")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xSmall)
                    .background(LociTheme.Colors.secondaryHighlight.opacity(0.2))
                    .cornerRadius(LociTheme.CornerRadius.small)
                }
            }
        }
        .padding(.horizontal, LociTheme.Spacing.medium)
        .padding(.vertical, LociTheme.Spacing.small)
    }
}

// MARK: - Leaderboard List

struct LeaderboardList: View {
    let leaderboard: LeaderboardData
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        LazyVStack(spacing: LociTheme.Spacing.small) {
            // Show user's entry if not in top 20
            if let userEntry = leaderboard.userEntry,
               let userRank = leaderboard.userRank,
               userRank > 20 {
                
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Your Position")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .textCase(.uppercase)
                    
                    LeaderboardEntryCard(
                        entry: userEntry,
                        isUserEntry: true
                    )
                    
                    Divider()
                        .background(LociTheme.Colors.disabledState)
                        .padding(.vertical, LociTheme.Spacing.small)
                    
                    Text("Top \(leaderboard.entries.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
            }
            
            // Top entries
                                    ForEach(leaderboard.entries) { entry in
                            LeaderboardEntryCard(
                                entry: entry,
                                isUserEntry: entry.userId == (FirebaseManager.shared.currentUser?.id ?? "current-user")
                            )
                            .padding(.horizontal, LociTheme.Spacing.medium)
                        }
                    }
        .padding(.bottom, LociTheme.Spacing.xxLarge)
    }
}

// MARK: - Leaderboard Entry Card

struct LeaderboardEntryCard: View {
    let entry: LeaderboardEntry
    let isUserEntry: Bool
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            // Rank
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rankBackgroundColor)
                    .frame(width: 36, height: 36)
                
                Text("\(entry.rank)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(rankTextColor)
            }
            
            // Profile image
            Circle()
                .fill(profileGradient)
                .frame(width: 44, height: 44)
                .overlay(
                    Group {
                        if entry.isAnonymous {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        } else {
                            Text(String(entry.displayName.prefix(1)))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                )
            
            // User info
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Text(entry.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    if entry.isAnonymous {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
                
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Text(entry.formattedMinutes)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    if let artist = entry.artistName {
                        Text("• \(artist)")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Crown for top 3
            if entry.rank <= 3 {
                Image(systemName: crownIcon)
                    .font(.system(size: 20))
                    .foregroundColor(crownColor)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                        .stroke(cardBorderColor, lineWidth: isUserEntry ? 2 : 0.5)
                )
        )
        .scaleEffect(isUserEntry ? 1.02 : 1.0)
        .shadow(
            color: isUserEntry ? LociTheme.Colors.secondaryHighlight.opacity(0.3) : .clear,
            radius: isUserEntry ? 8 : 0
        )
    }
    
    private var rankBackgroundColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return LociTheme.Colors.disabledState
        }
    }
    
    private var rankTextColor: Color {
        entry.rank <= 3 ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText
    }
    
    private var profileGradient: LinearGradient {
        LinearGradient(
            colors: [LociTheme.Colors.primaryAction, LociTheme.Colors.secondaryHighlight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var crownIcon: String {
        switch entry.rank {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal"
        default: return ""
        }
    }
    
    private var crownColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .clear
        }
    }
    
    private var cardBackgroundColor: Color {
        if isUserEntry {
            return LociTheme.Colors.contentContainer
        } else {
            return LociTheme.Colors.contentContainer.opacity(0.7)
        }
    }
    
    private var cardBorderColor: Color {
        if isUserEntry {
            return LociTheme.Colors.secondaryHighlight
        } else {
            return LociTheme.Colors.disabledState.opacity(0.3)
        }
    }
}

// MARK: - Empty States

struct EmptyLeaderboardView: View {
    let scope: LocationScope
    let type: LeaderboardType
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            Spacer()
            
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(LociTheme.Colors.subheadText.opacity(0.5))
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("No Data Yet")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Start listening to see \(scope.displayName.lowercased()) leaderboards")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.large)
    }
}

struct LoadingLeaderboardView: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                .scaleEffect(1.5)
            
            Text("Loading...")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
        }
    }
}

// MARK: - Consent Required View

struct LeaderboardConsentRequiredView: View {
    let onShowConsent: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            Spacer()
            
            VStack(spacing: LociTheme.Spacing.medium) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    .glow(color: LociTheme.Colors.secondaryHighlight, radius: 16)
                
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Join the Leaderboards")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                    
                    Text("Compete with other music lovers in your area and around the world")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LociTheme.Spacing.large)
                }
            }
            
            VStack(spacing: LociTheme.Spacing.medium) {
                ConsentFeaturePreview(
                    icon: "building.2",
                    title: "Building Rankings",
                    description: "See who's listening in your building"
                )
                
                ConsentFeaturePreview(
                    icon: "map",
                    title: "Regional Competition",
                    description: "Compete with your neighborhood"
                )
                
                ConsentFeaturePreview(
                    icon: "globe",
                    title: "Global Leaderboards",
                    description: "Join music lovers worldwide"
                )
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                Button("Get Started") {
                    onShowConsent()
                }
                .lociButton(.gradient, isFullWidth: true)
                
                Text("We'll ask for your privacy preferences first")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.large)
    }
}

struct ConsentFeaturePreview: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(LociTheme.Colors.secondaryHighlight.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
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
        .padding(.horizontal, LociTheme.Spacing.medium)
    }
}

// MARK: - Private Mode View

struct LeaderboardPrivateModeView: View {
    @Binding var privacySettings: LeaderboardPrivacySettings
    let onChangeSettings: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.large) {
            Spacer()
            
            VStack(spacing: LociTheme.Spacing.medium) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                VStack(spacing: LociTheme.Spacing.small) {
                    Text("Private Mode")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Your music data is completely private")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: LociTheme.Spacing.medium) {
                PrivateModeFeature(
                    icon: "eye.slash",
                    title: "No Data Shared",
                    description: "Your listening habits stay on your device"
                )
                
                PrivateModeFeature(
                    icon: "person.circle",
                    title: "Complete Anonymity",
                    description: "You don't appear on any leaderboards"
                )
                
                PrivateModeFeature(
                    icon: "gear",
                    title: "Change Anytime",
                    description: "You can join leaderboards whenever you want"
                )
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                Button("Change Privacy Settings") {
                    onChangeSettings()
                }
                .lociButton(.primary, isFullWidth: true)
                
                Text("Join leaderboards to see how you compare with other music lovers")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LociTheme.Spacing.medium)
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.large)
    }
}

struct PrivateModeFeature: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(LociTheme.Colors.disabledState.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
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
        .padding(.horizontal, LociTheme.Spacing.medium)
    }
}
