import SwiftUI
import FirebaseCore

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
    @StateObject private var firebaseManager = FirebaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !firebaseManager.isAuthenticated {
                    // Show authentication if user is not signed in
                    AuthenticationView()
                        .environmentObject(firebaseManager)
                } else if !spotifyManager.isAuthenticated {
                    // Show Spotify onboarding if Firebase auth is complete but Spotify is not connected
                    SpotifyOnboardingView()
                        .environmentObject(spotifyManager)
                } else {
                    // Show main app when both Firebase and Spotify are authenticated
                    MainAppView()
                        .environmentObject(sessionManager)
                        .environmentObject(locationManager)
                        .environmentObject(spotifyManager)
                        .environmentObject(dataStore)
                        .environmentObject(firebaseManager)
                }
            }
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
        print("🎵 Loci: App launched with Firebase")
    }
}

struct MainAppView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home/Sessions tab
            ContentView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            // Discovery tab
            LocationDiscoveryView()
                .tabItem {
                    Image(systemName: "location.magnifyingglass")
                    Text("Discover")
                }
                .tag(1)
            
            // Matching tab
            MatchingView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Matches")
                }
                .tag(2)
            
            // Friends tab
            FriendsView()
                .tabItem {
                    Image(systemName: "person.2.fill")
                    Text("Friends")
                }
                .tag(3)
            
            // Profile tab
            UserProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}

struct UserProfileView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var showingSignOutAlert = false
    
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
                        // Profile header
                        VStack(spacing: 16) {
                            // Profile image placeholder
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.purple, Color.blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                
                                if let user = firebaseManager.currentUser {
                                    Text(String(user.displayName.prefix(1)).uppercased())
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            VStack(spacing: 4) {
                                Text(firebaseManager.currentUser?.displayName ?? "User")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text(firebaseManager.currentUser?.email ?? "")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.top, 40)
                        
                        // Profile sections
                        VStack(spacing: 16) {
                            ProfileSection(title: "Privacy Settings", icon: "lock.fill") {
                                // TODO: Privacy settings view
                            }
                            
                            ProfileSection(title: "Music Preferences", icon: "music.note") {
                                // TODO: Music preferences view
                            }
                            
                            ProfileSection(title: "Session History", icon: "clock.fill") {
                                // TODO: Session history view
                            }
                            
                            ProfileSection(title: "About", icon: "info.circle.fill") {
                                // TODO: About view
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Sign out button
                        Button(action: { showingSignOutAlert = true }) {
                            Text("Sign Out")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                        )
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                do {
                    try firebaseManager.signOut()
                } catch {
                    print("Error signing out: \(error)")
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
}

struct ProfileSection: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
}

