import SwiftUI

@main
struct LociApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var spotifyManager = SpotifyManager.shared
    @StateObject private var dataStore = DataStore.shared
    @StateObject private var analyticsEngine = AnalyticsEngine.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var privacyManager = PrivacyManager.shared
    @StateObject private var matchingEngine = MatchingEngine.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(locationManager)
                .environmentObject(spotifyManager)
                .environmentObject(dataStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // Request location permissions on first launch
        locationManager.requestPermissions()
        
        // Setup any other initial configurations
        print("🎵 Loci: App launched")
    }
}

