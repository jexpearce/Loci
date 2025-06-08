import SwiftUI

struct LeaderboardView: View {
    @StateObject private var leaderboardManager = LeaderboardManager.shared
    @State private var selectedScope: LocationScope = .region
    @State private var selectedCategory: LeaderboardCategory = .overall
    @State private var selectedType: LeaderboardType = .overall
    @State private var availableTypes: [LeaderboardType] = [.overall]
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with user's best ranking
                    LeaderboardHeader()
                    
                    // Location scope tabs
                    LocationScopeSelector(
                        selectedScope: $selectedScope,
                        onScopeChange: updateAvailableTypes
                    )
                    
                    // Category and type selectors
                    CategoryTypeSelector(
                        selectedCategory: $selectedCategory,
                        selectedType: $selectedType,
                        availableTypes: availableTypes,
                        scope: selectedScope
                    )
                    
                    // Leaderboard content
                    LeaderboardContent(
                        scope: selectedScope,
                        type: selectedType
                    )
                }
            }
            .navigationBarHidden(true)
            .refreshable {
                await leaderboardManager.loadLeaderboards(forceRefresh: true)
            }
        }
        .onAppear {
            Task {
                await leaderboardManager.loadLeaderboards()
                updateAvailableTypes()
                setDefaultScope()
            }
        }
        .onChange(of: selectedCategory) { _ in
            updateSelectedType()
        }
    }
    
    private func updateAvailableTypes() {
        var types: [LeaderboardType] = [.overall]
        
        if selectedScope != .building {
            // Add top artists
            types += leaderboardManager.availableArtists.prefix(5).map { .artist($0) }
            // Add top genres
            types += leaderboardManager.availableGenres.prefix(3).map { .genre($0) }
        }
        
        availableTypes = types
        updateSelectedType()
    }
    
    private func updateSelectedType() {
        switch selectedCategory {
        case .overall:
            selectedType = .overall
        case .artist:
            selectedType = availableTypes.first { $0.category == .artist } ?? .overall
        case .genre:
            selectedType = availableTypes.first { $0.category == .genre } ?? .overall
        }
    }
    
    private func setDefaultScope() {
        // Set default to user's best ranking scope
        if let bestRanking = leaderboardManager.getBestUserRanking() {
            selectedScope = bestRanking.scope
            selectedType = bestRanking.type
            selectedCategory = bestRanking.type.category
        }
    }
}

// MARK: - Leaderboard Header

struct LeaderboardHeader: View {
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                    Text("Your Leaderboards")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .neonText()
                    
                    if let bestRanking = leaderboardManager.getBestUserRanking() {
                        Text(bestRanking.displayText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
                
                Spacer()
                
                // Refresh indicator
                if leaderboardManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                        .scaleEffect(0.8)
                }
            }
            
            // Quick stats
            if let summary = leaderboardManager.userSummary {
                UserQuickStatsRow(summary: summary)
            }
        }
        .padding(.horizontal, LociTheme.Spacing.medium)
        .padding(.top, LociTheme.Spacing.large)
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Location Scope Selector

struct LocationScopeSelector: View {
    @Binding var selectedScope: LocationScope
    let onScopeChange: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LociTheme.Spacing.small) {
                ForEach(LocationScope.allCases) { scope in
                    ScopeTab(
                        scope: scope,
                        isSelected: selectedScope == scope
                    ) {
                        withAnimation(LociTheme.Animation.smoothEaseInOut) {
                            selectedScope = scope
                            onScopeChange()
                        }
                    }
                }
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
        }
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Category Type Selector

struct CategoryTypeSelector: View {
    @Binding var selectedCategory: LeaderboardCategory
    @Binding var selectedType: LeaderboardType
    let availableTypes: [LeaderboardType]
    let scope: LocationScope
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            // Category selector
            HStack(spacing: LociTheme.Spacing.small) {
                ForEach(availableCategories, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        isDisabled: !isCategoryAvailable(category)
                    ) {
                        selectedCategory = category
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, LociTheme.Spacing.medium)
            
            // Type dropdown for artists/genres
            if selectedCategory != .overall {
                TypeDropdownSelector(
                    selectedType: $selectedType,
                    availableTypes: typesForCategory(selectedCategory),
                    category: selectedCategory
                )
                .padding(.horizontal, LociTheme.Spacing.medium)
            }
        }
        .padding(.bottom, LociTheme.Spacing.medium)
    }
    
    private var availableCategories: [LeaderboardCategory] {
        scope == .building ? [.overall] : LeaderboardCategory.allCases
    }
    
    private func isCategoryAvailable(_ category: LeaderboardCategory) -> Bool {
        switch category {
        case .overall: return true
        case .artist: return !leaderboardManager.availableArtists.isEmpty && scope != .building
        case .genre: return !leaderboardManager.availableGenres.isEmpty && scope != .building
        }
    }
    
    private func typesForCategory(_ category: LeaderboardCategory) -> [LeaderboardType] {
        switch category {
        case .overall: return [.overall]
        case .artist: return leaderboardManager.availableArtists.map { .artist($0) }
        case .genre: return leaderboardManager.availableGenres.map { .genre($0) }
        }
    }
}

// MARK: - Leaderboard Content

struct LeaderboardContent: View {
    let scope: LocationScope
    let type: LeaderboardType
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        Group {
            if let leaderboard = leaderboardManager.getLeaderboard(scope: scope, type: type) {
                if leaderboard.isEmpty {
                    EmptyLeaderboardView(scope: scope, type: type)
                } else {
                    LeaderboardList(leaderboard: leaderboard)
                }
            } else if leaderboardManager.isLoading {
                LoadingLeaderboardView()
            } else {
                EmptyLeaderboardView(scope: scope, type: type)
            }
        }
    }
}
