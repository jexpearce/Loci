import SwiftUI

struct MatchDetailView: View {
    let match: Match
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var showingAddFriend = false
    
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
                    VStack(spacing: 24) {
                        // Header
                        matchHeaderView
                        
                        // Compatibility breakdown
                        compatibilityBreakdownView
                        
                        // Shared interests
                        sharedInterestsView
                        
                        // Actions
                        actionsView
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .alert("Add Friend", isPresented: $showingAddFriend) {
            Button("Cancel", role: .cancel) { }
            Button("Send Request") {
                // TODO: Send friend request to this match
            }
        } message: {
            Text("Would you like to send a friend request to this music match?")
        }
    }
    
    private var matchHeaderView: some View {
        VStack(spacing: 16) {
            // Match type and emoji
            VStack(spacing: 8) {
                Text(match.matchType.emoji)
                    .font(.system(size: 64))
                
                Text(matchTypeTitle(match.matchType))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(Int(match.score.overall * 100))% compatibility")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Match strength indicator
            HStack(spacing: 12) {
                Circle()
                    .fill(matchColor(for: match.score.overall))
                    .frame(width: 16, height: 16)
                
                Text(matchStrength(for: match.score.overall) + " MATCH")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(matchColor(for: match.score.overall))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(matchColor(for: match.score.overall), lineWidth: 2)
            )
        }
        .padding(.top, 20)
    }
    
    private var compatibilityBreakdownView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compatibility Breakdown")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                DetailedScoreBar(
                    label: "Music Taste",
                    score: match.score.musicTaste,
                    color: .purple,
                    description: musicTasteDescription(match.score.musicTaste)
                )
                
                DetailedScoreBar(
                    label: "Location Overlap",
                    score: match.score.locationOverlap,
                    color: .blue,
                    description: locationDescription(match.score.locationOverlap)
                )
                
                DetailedScoreBar(
                    label: "Time Alignment",
                    score: match.score.timeAlignment,
                    color: .green,
                    description: timeDescription(match.score.timeAlignment)
                )
                
                DetailedScoreBar(
                    label: "Diversity Match",
                    score: match.score.diversityMatch,
                    color: .orange,
                    description: diversityDescription(match.score.diversityMatch)
                )
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
    
    private var sharedInterestsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shared Interests")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            // Shared artists
            if !match.sharedInterests.topSharedArtists.isEmpty {
                SharedInterestSection(
                    title: "Artists",
                    icon: "music.mic",
                    items: match.sharedInterests.topSharedArtists,
                    color: .purple
                )
            }
            
            // Shared genres
            if !match.sharedInterests.topSharedGenres.isEmpty {
                SharedInterestSection(
                    title: "Genres",
                    icon: "music.note.list",
                    items: match.sharedInterests.topSharedGenres,
                    color: .blue
                )
            }
            
            // Shared locations
            if !match.sharedInterests.sharedLocations.isEmpty {
                SharedInterestSection(
                    title: "Locations",
                    icon: "location.fill",
                    items: match.sharedInterests.sharedLocations,
                    color: .green
                )
            }
            
            // Shared listening times
            if !match.sharedInterests.sharedListeningTimes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("Listening Times")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    HStack {
                        ForEach(match.sharedInterests.sharedListeningTimes, id: \.self) { time in
                            Text(time.displayString)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.3))
                                )
                        }
                        
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
    
    private var actionsView: some View {
        VStack(spacing: 16) {
            // Connect button
            Button(action: { showingAddFriend = true }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Connect as Friend")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
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
            
            // View profile button (placeholder)
            Button(action: {
                // TODO: View anonymous profile
            }) {
                HStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text("View Music Profile")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // Helper functions
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
        else if score >= 0.6 { return "MEDIUM" }
        else { return "LOW" }
    }
    
    private func musicTasteDescription(_ score: Double) -> String {
        if score >= 0.8 { return "Very similar music taste" }
        else if score >= 0.6 { return "Good music compatibility" }
        else { return "Some shared preferences" }
    }
    
    private func locationDescription(_ score: Double) -> String {
        if score >= 0.8 { return "Frequent same locations" }
        else if score >= 0.6 { return "Some location overlap" }
        else { return "Occasional same places" }
    }
    
    private func timeDescription(_ score: Double) -> String {
        if score >= 0.8 { return "Very similar listening times" }
        else if score >= 0.6 { return "Some time overlap" }
        else { return "Different schedules" }
    }
    
    private func diversityDescription(_ score: Double) -> String {
        if score >= 0.8 { return "Similar music exploration" }
        else if score >= 0.6 { return "Moderate diversity match" }
        else { return "Different discovery styles" }
    }
}

struct DetailedScoreBar: View {
    let label: String
    let score: Double
    let color: Color
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(Int(score * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: geometry.size.width * score, height: 8)
                }
            }
            .frame(height: 8)
            
            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct SharedInterestSection: View {
    let title: String
    let icon: String
    let items: [String]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(Array(items.prefix(6)), id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(color.opacity(0.3))
                        )
                        .lineLimit(1)
                }
                
                if items.count > 6 {
                    Text("+\(items.count - 6) more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(color.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// Extension for TimeOfDay display
extension TimeOfDay {
    var displayString: String {
        switch self {
        case .earlyMorning: return "Early Morning"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .lateNight: return "Late Night"
        }
    }
}

#Preview {
    MatchDetailView(match: Match(
        userId: UUID(),
        score: MatchScore(
            overall: 0.85,
            musicTaste: 0.9,
            locationOverlap: 0.7,
            timeAlignment: 0.8,
            diversityMatch: 0.75
        ),
        matchType: .strong,
        sharedInterests: SharedInterests(
            topSharedArtists: ["Arctic Monkeys", "Tame Impala", "The Strokes"],
            topSharedGenres: ["Indie Rock", "Alternative"],
            sharedListeningTimes: [.afternoon, .evening],
            sharedLocations: ["Coffee Shop", "Library"]
        ),
        timestamp: Date()
    ))
} 