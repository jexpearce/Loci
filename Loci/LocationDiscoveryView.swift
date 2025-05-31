import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

struct LocationDiscoveryView: View {
    @StateObject private var firebaseManager = FirebaseManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var nearbyActivity: [BuildingActivity] = []
    @State private var selectedActivity: BuildingActivity?
    @State private var showingMap = false
    @State private var isLoading = true
    @State private var activityListener: ListenerRegistration?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
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
                    
                    if isLoading {
                        loadingView
                    } else if nearbyActivity.isEmpty {
                        emptyStateView
                    } else {
                        // Activity list
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(nearbyActivity) { activity in
                                    BuildingActivityCard(
                                        activity: activity,
                                        onTap: { selectedActivity = activity }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                startLocationDiscovery()
            }
            .onDisappear {
                stopLocationDiscovery()
            }
            .sheet(item: $selectedActivity) { activity in
                BuildingDetailView(activity: activity)
            }
            .sheet(isPresented: $showingMap) {
                DiscoveryMapView(activities: nearbyActivity)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Music happening around you")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Button(action: { showingMap = true }) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
            
            // Stats bar
            HStack(spacing: 20) {
                StatItem(
                    icon: "building.2.fill",
                    value: "\(nearbyActivity.count)",
                    label: "Active Buildings"
                )
                
                StatItem(
                    icon: "person.2.fill",
                    value: "\(nearbyActivity.reduce(0) { $0 + $1.activeUsers })",
                    label: "Listeners"
                )
                
                StatItem(
                    icon: "music.note",
                    value: "\(nearbyActivity.flatMap { $0.currentTracks }.count)",
                    label: "Tracks"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Finding music around you...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "music.note.house")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 12) {
                Text("No Music Activity Nearby")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Be the first to start a session in this area! Your music activity will appear here for others to discover.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
    
    private func startLocationDiscovery() {
        guard let location = locationManager.currentLocation else {
            // Request location permission if needed
            locationManager.requestPermissions()
            return
        }
        
        // Start real-time listener
        activityListener = firebaseManager.listenToNearbyActivity(location: location) { activities in
            DispatchQueue.main.async {
                self.nearbyActivity = activities.sorted { $0.activeUsers > $1.activeUsers }
                self.isLoading = false
            }
        }
    }
    
    private func stopLocationDiscovery() {
        activityListener?.remove()
        activityListener = nil
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

struct BuildingActivityCard: View {
    let activity: BuildingActivity
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.buildingName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("\(activity.activeUsers) listening")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // Live indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .scaleEffect(1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: UUID()
                            )
                        
                        Text("LIVE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                
                // Recent tracks
                if !activity.currentTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Now Playing")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        
                        ForEach(Array(activity.currentTracks.prefix(3).enumerated()), id: \.offset) { index, track in
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.purple)
                                    .frame(width: 20)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Text(track.artist)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Text(timeAgo(from: track.timestamp))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
                
                // Distance (if available)
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("Nearby") // TODO: Calculate actual distance
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        }
    }
}

struct BuildingDetailView: View {
    let activity: BuildingActivity
    @Environment(\.dismiss) private var dismiss
    
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
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Text(activity.buildingName)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                    
                                    Text("\(activity.activeUsers) listening")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    
                                    Text("LIVE")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        
                        // All tracks
                        if !activity.currentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Recent Activity")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                
                                ForEach(Array(activity.currentTracks.enumerated()), id: \.offset) { index, track in
                                    HStack(spacing: 16) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.purple, Color.blue],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 48, height: 48)
                                            
                                            Image(systemName: "music.note")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(track.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                            
                                            Text(track.artist)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(timeAgo(from: track.timestamp))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DiscoveryMapView: View {
    let activities: [BuildingActivity]
    @Environment(\.dismiss) private var dismiss
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        NavigationView {
            Map(coordinateRegion: $region, annotationItems: activities) { activity in
                MapAnnotation(coordinate: CLLocationCoordinate2D(
                    latitude: activity.latitude,
                    longitude: activity.longitude
                )) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 32, height: 32)
                            
                            Text("\(activity.activeUsers)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text(activity.buildingName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .shadow(radius: 2)
                            )
                    }
                }
            }
            .navigationTitle("Music Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let firstActivity = activities.first {
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: firstActivity.latitude,
                        longitude: firstActivity.longitude
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }
}

#Preview {
    LocationDiscoveryView()
} 
