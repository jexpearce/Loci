import SwiftUI

// MARK: - Session Mode Selection View

struct SessionModeSelectionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedMode: SessionMode?
    @State private var showingManualSession = false
    @State private var showingPassiveSession = false
    
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
                            description: "Pick any location manually. No GPS required.",
                            icon: "map.fill",
                            color: LociTheme.Colors.primaryAction,
                            features: [
                                "No location permissions needed",
                                "You choose the region name",
                                "Tracks collected at session end",
                                "Perfect for privacy-conscious users"
                            ],
                            isSelected: selectedMode == .manual
                        ) {
                            selectedMode = .manual
                            showingManualSession = true
                        }
                        
                        // Passive Mode
                        SessionModeCard(
                            mode: .passive,
                            title: "Stay-in-Place",
                            subtitle: "One-Time Location",
                            description: "Single GPS ping, then track music at that location.",
                            icon: "location.square.fill",
                            color: LociTheme.Colors.secondaryHighlight,
                            features: [
                                "One location check at start",
                                "Minimal battery usage",
                                "Perfect for coffee shops & libraries",
                                "\"When in Use\" permission only"
                            ],
                            isSelected: selectedMode == .passive
                        ) {
                            selectedMode = .passive
                            showingPassiveSession = true
                        }
                        
                        // Active Mode
                        SessionModeCard(
                            mode: .active,
                            title: "Live Tracking",
                            subtitle: "Real-Time Map",
                            description: "Continuous location tracking with live music mapping.",
                            icon: "location.fill.viewfinder",
                            color: LociTheme.Colors.notificationBadge,
                            features: [
                                "Real-time location updates",
                                "Live music mapping",
                                "Auto-stops after 6 hours",
                                "\"Always\" permission required"
                            ],
                            isSelected: selectedMode == .active
                        ) {
                            selectedMode = .active
                            sessionManager.startSession(mode: .active)
                        }
                    }
                    
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
    let action: () -> Void
    
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
                                Text(title)
                                    .font(LociTheme.Typography.subheading)
                                    .foregroundColor(LociTheme.Colors.mainText)
                                
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
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LociTheme.Colors.subheadText)
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