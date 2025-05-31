import SwiftUI

struct MatchFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var matchingManager = MatchingManager.shared
    
    @State private var filters: MatchFilters
    @State private var preferences: MatchPreferences
    
    init() {
        let manager = MatchingManager.shared
        _filters = State(initialValue: manager.currentFilters)
        _preferences = State(initialValue: manager.userPreferences)
    }
    
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
                        // Match Preferences
                        preferencesSection
                        
                        // Filters
                        filtersSection
                        
                        // Advanced Settings
                        advancedSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Match Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applySettings()
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Match Preferences")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Adjust how much each factor matters in finding matches")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 20) {
                PreferenceSlider(
                    label: "Music Taste",
                    value: $preferences.musicWeight,
                    color: .purple,
                    icon: "music.note"
                )
                
                PreferenceSlider(
                    label: "Location Overlap",
                    value: $preferences.locationWeight,
                    color: .blue,
                    icon: "location.fill"
                )
                
                PreferenceSlider(
                    label: "Time Alignment",
                    value: $preferences.timeWeight,
                    color: .green,
                    icon: "clock.fill"
                )
                
                PreferenceSlider(
                    label: "Diversity Match",
                    value: $preferences.diversityWeight,
                    color: .orange,
                    icon: "shuffle"
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
    
    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                // Minimum Activity Filter
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Text("Minimum Activity Level")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("0")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Slider(
                            value: Binding(
                                get: { Double(filters.minimumActivity ?? 0) },
                                set: { filters.minimumActivity = Int($0) }
                            ),
                            in: 0...500,
                            step: 10
                        )
                        .accentColor(.blue)
                        
                        Text("500")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("\(filters.minimumActivity ?? 0) listening events minimum")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Diversity Range Filter
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("Diversity Range")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { filters.diversityRange != nil },
                            set: { enabled in
                                if enabled {
                                    filters.diversityRange = 0.3...0.9
                                } else {
                                    filters.diversityRange = nil
                                }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    }
                    
                    if filters.diversityRange != nil {
                        Text("Match users with similar music exploration styles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // Max Results
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "number")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.purple)
                        
                        Text("Maximum Results")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("10")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Slider(
                            value: Binding(
                                get: { Double(filters.maxResults) },
                                set: { filters.maxResults = Int($0) }
                            ),
                            in: 10...100,
                            step: 5
                        )
                        .accentColor(.purple)
                        
                        Text("100")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("Show up to \(filters.maxResults) matches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
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
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                // Reset to defaults
                Button(action: resetToDefaults) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text("Reset to Defaults")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                
                // Privacy note
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.green)
                        
                        Text("Privacy Protection")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    Text("All matching is done with anonymized data. Your personal information and exact listening history remain private.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
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
    
    private func applySettings() {
        // Normalize preferences to sum to 1.0
        let total = preferences.musicWeight + preferences.locationWeight + 
                   preferences.timeWeight + preferences.diversityWeight
        
        if total > 0 {
            preferences.musicWeight /= total
            preferences.locationWeight /= total
            preferences.timeWeight /= total
            preferences.diversityWeight /= total
        }
        
        matchingManager.updateFilters(filters)
        matchingManager.updatePreferences(preferences)
    }
    
    private func resetToDefaults() {
        filters = MatchFilters()
        preferences = MatchPreferences()
    }
}

struct PreferenceSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(Int(value * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }
            
            Slider(value: $value, in: 0...1, step: 0.05)
                .accentColor(color)
        }
    }
}

#Preview {
    MatchFiltersView()
} 