import SwiftUI
import FirebaseAuth

struct MatchingView: View {
    @StateObject private var matchingManager = MatchingManager.shared
    @State private var selectedMatch: Match?
    @State private var showingFilters = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Tab selector
                    tabSelector
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        matchesListView
                            .tag(0)
                        
                        compatibilityView
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedMatch) { match in
            MatchDetailView(match: match)
        }
        .sheet(isPresented: $showingFilters) {
            MatchFiltersView()
        }
        .onAppear {
            matchingManager.refreshMatches()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Matches")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(matchingManager.matches.count) music connections")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // Filters button
                Button(action: { showingFilters = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Refresh button
                Button(action: { matchingManager.refreshMatches() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Matches", isSelected: selectedTab == 0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 0
                }
            }
            
            TabButton(title: "Compatibility", isSelected: selectedTab == 1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 1
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var matchesListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if matchingManager.isLoading {
                    loadingView
                } else if matchingManager.matches.isEmpty {
                    emptyMatchesView
                } else {
                    ForEach(matchingManager.matches) { match in
                        MatchCard(match: match) {
                            selectedMatch = match
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var compatibilityView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Compatibility score overview
                CompatibilityOverviewCard()
                
                // Music taste analysis
                MusicTasteCard()
                
                // Location patterns
                LocationPatternsCard()
                
                // Listening habits
                ListeningHabitsCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Finding your music matches...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 60)
    }
    
    private var emptyMatchesView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Matches Yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Keep listening to music in different locations to find people with similar taste!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: { matchingManager.refreshMatches() }) {
                Text("Refresh Matches")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }
}

struct MatchCard: View {
    let match: Match
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with match type and score
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(match.matchType.emoji)
                                .font(.system(size: 24))
                            
                            Text(matchTypeTitle(match.matchType))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("\(Int(match.score.overall * 100))% compatibility")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Match strength indicator
                    VStack(spacing: 4) {
                        Circle()
                            .fill(matchColor(for: match.score.overall))
                            .frame(width: 12, height: 12)
                        
                        Text(matchStrength(for: match.score.overall))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(matchColor(for: match.score.overall))
                    }
                }
                
                // Score breakdown
                VStack(spacing: 8) {
                    ScoreBar(
                        label: "Music Taste",
                        score: match.score.musicTaste,
                        color: .purple
                    )
                    
                    ScoreBar(
                        label: "Location Overlap",
                        score: match.score.locationOverlap,
                        color: .blue
                    )
                    
                    ScoreBar(
                        label: "Time Alignment",
                        score: match.score.timeAlignment,
                        color: .green
                    )
                }
                
                // Shared interests preview
                if !match.sharedInterests.topSharedArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared Artists")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        
                        HStack {
                            ForEach(Array(match.sharedInterests.topSharedArtists.prefix(3)), id: \.self) { artist in
                                Text(artist)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.purple.opacity(0.3))
                                    )
                            }
                            
                            if match.sharedInterests.topSharedArtists.count > 3 {
                                Text("+\(match.sharedInterests.topSharedArtists.count - 3)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                // Timestamp
                HStack {
                    Text("Found \(timeAgo(from: match.timestamp))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
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
        .buttonStyle(PlainButtonStyle())
    }
    
    private func matchTypeTitle(_ type: MatchType) -> String {
        switch type {
        case .strong: return "Strong Match"
        case .musicTwin: return "Music Twin"
        case .neighbor: return "Neighbor"
        case .scheduleMatch: return "Schedule Match"
        case .casual: return "Casual Match"
        }
    }
    
    private func matchColor(for score: Double) -> Color {
        if score >= 0.8 { return .green }
        else if score >= 0.6 { return .yellow }
        else { return .orange }
    }
    
    private func matchStrength(for score: Double) -> String {
        if score >= 0.8 { return "HIGH" }
        else if score >= 0.6 { return "MED" }
        else { return "LOW" }
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 3600 {
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

struct ScoreBar: View {
    let label: String
    let score: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 80, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * score, height: 6)
                }
            }
            .frame(height: 6)
            
            Text("\(Int(score * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 35, alignment: .trailing)
        }
    }
}

// MARK: - Compatibility Cards

struct CompatibilityOverviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Compatibility Profile")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("85%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                    
                    Text("Avg Match")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                VStack(spacing: 8) {
                    Text("12")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("Total Matches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                VStack(spacing: 8) {
                    Text("3")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.purple)
                    
                    Text("Strong Matches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
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

struct MusicTasteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Music Taste Analysis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Most Compatible Genres")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                }
                
                HStack {
                    ForEach(["Indie Rock", "Electronic", "Jazz"], id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple.opacity(0.3))
                            )
                    }
                    
                    Spacer()
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

struct LocationPatternsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Location Patterns")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("Most active in Coffee Shops & Libraries")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                    
                    Text("Peak listening: 2-4 PM")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
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

struct ListeningHabitsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Listening Habits")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Diversity Score")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("High")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Discovery Rate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("Medium")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.yellow)
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

#Preview {
    MatchingView()
} 