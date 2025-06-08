import SwiftUI

// MARK: - Scope Tab

struct ScopeTab: View {
    let scope: LocationScope
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: LociTheme.Spacing.xSmall) {
                Image(systemName: scope.icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(scope.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? LociTheme.Colors.appBackground : LociTheme.Colors.subheadText)
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.vertical, LociTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState.opacity(0.3))
                    .shadow(
                        color: isSelected ? LociTheme.Colors.secondaryHighlight.opacity(0.3) : .clear,
                        radius: isSelected ? 8 : 0
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(LociTheme.Animation.bouncy, value: isSelected)
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: LeaderboardCategory
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(textColor)
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.small)
                .background(backgroundColor)
                .cornerRadius(LociTheme.CornerRadius.medium)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColor: Color {
        if isSelected {
            return LociTheme.Colors.appBackground
        } else {
            return LociTheme.Colors.mainText
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return LociTheme.Colors.primaryAction
        } else {
            return LociTheme.Colors.disabledState.opacity(0.3)
        }
    }
}

// MARK: - Type Dropdown Selector

struct TypeDropdownSelector: View {
    @Binding var selectedType: LeaderboardType
    let availableTypes: [LeaderboardType]
    let category: LeaderboardCategory
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text(selectedType.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.contentContainer)
                .cornerRadius(LociTheme.CornerRadius.medium)
            }
            
            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: LociTheme.Spacing.xSmall) {
                        ForEach(availableTypes.prefix(10), id: \.id) { type in
                            TypeOptionRow(
                                type: type,
                                isSelected: type.id == selectedType.id
                            ) {
                                selectedType = type
                                isExpanded = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(LociTheme.Colors.contentContainer)
                .cornerRadius(LociTheme.CornerRadius.medium)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(LociTheme.Animation.smoothEaseInOut, value: isExpanded)
    }
}

// MARK: - Type Option Row

struct TypeOptionRow: View {
    let type: LeaderboardType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(type.displayName)
                    .font(.system(size: 15))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.vertical, LociTheme.Spacing.small)
            .background(isSelected ? LociTheme.Colors.secondaryHighlight.opacity(0.1) : Color.clear)
            .cornerRadius(LociTheme.CornerRadius.small)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Quick Stats Row

struct UserQuickStatsRow: View {
    let summary: UserLeaderboardSummary
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            if let bestRanking = summary.bestRanking {
                QuickStatItem(
                    title: "Best Rank",
                    value: "#\(bestRanking.rank)",
                    subtitle: bestRanking.scope.displayName,
                    color: LociTheme.Colors.secondaryHighlight
                )
            }
            
            QuickStatItem(
                title: "Leaderboards",
                value: "\(summary.availableLeaderboards.count)",
                subtitle: "Active",
                color: LociTheme.Colors.primaryAction
            )
            
            if !summary.recentChanges.isEmpty {
                let improvements = summary.recentChanges.filter { $0.isImprovement }.count
                QuickStatItem(
                    title: "This Week",
                    value: "+\(improvements)",
                    subtitle: "Improved",
                    color: LociTheme.Colors.notificationBadge
                )
            }
            
            Spacer()
        }
    }
}

// MARK: - Quick Stat Item

struct QuickStatItem: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(LociTheme.Colors.subheadText)
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
    }
}

// MARK: - Leaderboard List

struct LeaderboardList: View {
    let leaderboard: LeaderboardData
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: LociTheme.Spacing.small) {
                // Show user's entry if not in top 20
                if let userEntry = leaderboard.userEntry,
                   let userRank = leaderboard.userRank,
                   userRank > 20 {
                    
                    Text("Your Position")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .textCase(.uppercase)
                        .padding(.top, LociTheme.Spacing.medium)
                    
                    LeaderboardEntryCard(
                        entry: userEntry,
                        isUserEntry: true,
                        leaderboard: leaderboard
                    )
                    
                    Divider()
                        .background(LociTheme.Colors.disabledState)
                        .padding(.vertical, LociTheme.Spacing.small)
                    
                    Text("Top \(leaderboard.entries.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .textCase(.uppercase)
                }
                
                // Top entries
                ForEach(leaderboard.entries) { entry in
                    LeaderboardEntryCard(
                        entry: entry,
                        isUserEntry: entry.userId == (leaderboardManager.firebaseManager.currentUser?.id ?? "current-user"),
                        leaderboard: leaderboard
                    )
                }
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.bottom, LociTheme.Spacing.xxLarge)
        }
    }
}

// MARK: - Leaderboard Entry Card

struct LeaderboardEntryCard: View {
    let entry: LeaderboardEntry
    let isUserEntry: Bool
    let leaderboard: LeaderboardData
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            // Rank
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rankBackgroundColor)
                    .frame(width: 32, height: 32)
                
                Text("\(entry.rank)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(rankTextColor)
            }
            
            // Profile image placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [LociTheme.Colors.primaryAction, LociTheme.Colors.secondaryHighlight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(entry.username.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // User info
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(entry.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Text(entry.formattedScore)
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    if case .artist(let artist) = leaderboard.type {
                        Text("• \(artist)")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                    } else if case .genre(let genre) = leaderboard.type {
                        Text("• \(genre)")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
            
            Spacer()
            
            // Badge for top 3
            if entry.rank <= 3 {
                Image(systemName: badgeIcon)
                    .font(.system(size: 20))
                    .foregroundColor(badgeColor)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.large)
                        .stroke(cardBorderColor, lineWidth: isUserEntry ? 2 : 1)
                        .shadow(
                            color: isUserEntry ? LociTheme.Colors.secondaryHighlight.opacity(0.3) : .clear,
                            radius: isUserEntry ? 8 : 0
                        )
                )
        )
        .scaleEffect(isUserEntry ? 1.02 : 1.0)
        .animation(LociTheme.Animation.bouncy, value: isUserEntry)
    }
    
    private var rankBackgroundColor: Color {
        switch entry.rank {
        case 1: return Color.yellow
        case 2: return Color.gray
        case 3: return Color.orange
        default: return LociTheme.Colors.disabledState
        }
    }
    
    private var rankTextColor: Color {
        entry.rank <= 3 ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText
    }
    
    private var badgeIcon: String {
        switch entry.rank {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal"
        default: return ""
        }
    }
    
    private var badgeColor: Color {
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
                
                Text("Start listening to see leaderboards for \(scope.displayName.lowercased())")
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
            
            Text("Loading leaderboards...")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
        }
    }
}
