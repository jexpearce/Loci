import SwiftUI

struct LeaderboardView: View {
    @StateObject private var leaderboardManager = LeaderboardManager.shared
    @State private var selectedType: LeaderboardType = .totalMinutes
    @State private var currentScopeIndex = 1 // Start with Region (middle)
    
    private let scopes: [LocationScope] = [.building, .region, .global]
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    LeaderboardHeader()
                    
                    // Type Switcher
                    LeaderboardTypeSwitcher(selectedType: $selectedType)
                        .padding(.horizontal, LociTheme.Spacing.medium)
                        .padding(.bottom, LociTheme.Spacing.medium)
                    
                    // Scope Indicator
                    ScopeIndicator(scopes: scopes, currentIndex: currentScopeIndex)
                        .padding(.bottom, LociTheme.Spacing.small)
                    
                    // Swipeable Leaderboards
                    TabView(selection: $currentScopeIndex) {
                        ForEach(0..<scopes.count, id: \.self) { index in
                            LeaderboardPage(
                                scope: scopes[index],
                                type: selectedType
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onChange(of: selectedType) { _ in
                        // Reset to region when changing type
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentScopeIndex = 1
                        }
                    }
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
            }
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
                    Text("Leaderboards")
                        .font(LociTheme.Typography.heading)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .neonText()
                    
                    if let bestRanking = leaderboardManager.getBestUserRanking() {
                        Text(bestRanking.displayText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    } else {
                        Text("Start listening to see your ranks")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                }
                
                Spacer()
                
                // Loading indicator
                if leaderboardManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(.horizontal, LociTheme.Spacing.medium)
        .padding(.top, LociTheme.Spacing.large)
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Leaderboard Page

struct LeaderboardPage: View {
    let scope: LocationScope
    let type: LeaderboardType
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Scope header
            ScopeHeader(scope: scope, type: type)
                .padding(.bottom, LociTheme.Spacing.medium)
            
            // Leaderboard content
            ScrollView {
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
}
