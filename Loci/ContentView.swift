import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedDuration: SessionDuration = .twelveHours
    @State private var showingSessionHistory = false
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "0A001A").ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    LociHeaderView()
                    Spacer()
                    SettingsIcon()
                }
                .padding(.horizontal)
                .padding(.top, 24)
                if sessionManager.isSessionActive {
                    LiveIndicator()
                }
                SessionInfoLabel()
                SessionDurationPicker(selectedDuration: $selectedDuration)
                StartSessionButton(selectedDuration: $selectedDuration)
                HStack(spacing: 12) {
                    SpotifyStatusChip()
                    LocationStatusChip()
                }
                RecentSessionPreview(showingSessionHistory: $showingSessionHistory)
                SocialTeaserCard()
                Spacer()
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
        }
    }
}

struct StartSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedDuration: SessionDuration
    
    var body: some View {
        VStack(spacing: 40) {
            // Duration Picker
            VStack(spacing: 16) {
                Text("Session Duration")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(SessionDuration.allCases, id: \.self) { duration in
                        DurationButton(
                            duration: duration,
                            isSelected: selectedDuration == duration,
                            action: { selectedDuration = duration }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Start Button
            Button(action: {
                sessionManager.startSession(duration: selectedDuration)
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                    Text("Start Session")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "121212"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(hex: "1DB954"))
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }
}

struct DurationButton: View {
    let duration: SessionDuration
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(duration.displayText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? Color(hex: "121212") : .white)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(isSelected ? Color(hex: "1DB954") : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

struct ActiveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: 30) {
            // Session Status
            VStack(spacing: 12) {
                Text("Session Active")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "1DB954"))
                
                if let endTime = sessionManager.sessionEndTime {
                    TimeRemainingView(endTime: endTime)
                }
            }
            
            // Current Stats
            VStack(spacing: 20) {
                StatCard(
                    icon: "music.note",
                    label: "Tracks Logged",
                    value: "\(dataStore.currentSessionEvents.count)"
                )
                
                if let lastEvent = dataStore.currentSessionEvents.last {
                    LastTrackCard(event: lastEvent)
                }
            }
            .padding(.horizontal, 40)
            
            // Stop Button
            Button(action: {
                sessionManager.stopSession()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "stop.fill")
                    Text("End Session")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.vertical, 16)
                .padding(.horizontal, 32)
                .background(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(8)
            }
        }
    }
}

struct TimeRemainingView: View {
    let endTime: Date
    @State private var timeRemaining = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(timeRemaining)
            .font(.system(size: 36, weight: .light, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .onReceive(timer) { _ in
                updateTimeRemaining()
            }
            .onAppear {
                updateTimeRemaining()
            }
    }
    
    private func updateTimeRemaining() {
        let remaining = endTime.timeIntervalSince(Date())
        if remaining > 0 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let seconds = Int(remaining) % 60
            timeRemaining = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            timeRemaining = "00:00:00"
        }
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "1DB954"))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct LastTrackCard: View {
    let event: ListeningEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Track")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            
            Text(event.trackName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(event.artistName)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            
            if let building = event.buildingName {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.system(size: 12))
                    Text(building)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .foregroundColor(Color(hex: "1DB954"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

struct SessionHistoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "121212")
                    .ignoresSafeArea()
                
                if dataStore.sessionHistory.isEmpty {
                    Text("No sessions yet")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(dataStore.sessionHistory) { session in
                                SessionHistoryCard(session: SessionData(
                                    id: session.id,
                                    startTime: session.startTime,
                                    endTime: session.endTime,
                                    duration: session.duration,
                                    events: session.events
                                ))
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Session History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "1DB954"))
                }
            }
        }
    }
}

struct SessionHistoryCard: View {
    let session: SessionData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(session.duration.displayText)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "1DB954"))
            }
            
            HStack(spacing: 20) {
                Label("\(session.events.count) tracks", systemImage: "music.note")
                Label("\(session.uniqueLocations) locations", systemImage: "map")
            }
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.7))
            
            if let topArtist = session.topArtist {
                Text("Top Artist: \(topArtist)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
