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
    
    @State private var hasCompletedOnboarding = false
    
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
                } else if !hasCompletedOnboarding {
                    // Show onboarding flow after authentication
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environmentObject(spotifyManager)
                        .environmentObject(locationManager)
                } else {
                    // Show main app when authentication and onboarding are complete
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
                // Check if user has completed onboarding
                hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
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
            
            // Leaderboards tab
            LeaderboardView()
                .environmentObject(LeaderboardManager.shared)
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Leaderboards")
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
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var privacyManager = PrivacyManager.shared
    
    @State private var showingSignOutAlert = false
    @State private var showingSessionHistory = false
    @State private var showingSettings = false
    @State private var showingImagePicker = false
    @State private var showingAbout = false
    @State private var profileImage: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Enhanced gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.08, green: 0.05, blue: 0.2),
                        Color(red: 0.12, green: 0.08, blue: 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Enhanced Profile Header
                        profileHeaderSection
                        
                        // Quick Stats Card
                        quickStatsCard
                        
                        // Top Artists/Songs Section (Keep the one we just fixed)
                        ProfileTopItemsView()
                            .padding(.horizontal, 20)
                        
                        // Enhanced Action Cards
                        actionCardsSection
                        
                        // Account Management Section
                        accountManagementSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
                .environmentObject(dataStore)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(spotifyManager)
                .environmentObject(dataStore)
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profileImage)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
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
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        VStack(spacing: 20) {
            // Profile Picture with edit button
            ZStack {
                // Profile Image
                Button(action: { showingImagePicker = true }) {
                    ZStack {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.4, green: 0.2, blue: 0.8),
                                            Color(red: 0.6, green: 0.3, blue: 0.9),
                                            Color(red: 0.3, green: 0.7, blue: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.3), Color.clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 2
                                        )
                                )
                            
                            if let user = firebaseManager.currentUser {
                                Text(String(user.displayName.prefix(1)).uppercased())
                                    .font(.system(size: 42, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 42, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                        }
                        
                        // Edit overlay
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 120, height: 120)
                            .opacity(0)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .opacity(0)
                            )
                    }
                }
                
                // Edit button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingImagePicker = true }) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 36, height: 36)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .offset(x: -8, y: -8)
                    }
                }
                .frame(width: 120, height: 120)
            }
            
            // User Info with enhanced styling
            VStack(spacing: 8) {
                Text(firebaseManager.currentUser?.displayName ?? "User")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                Text(firebaseManager.currentUser?.email ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                // Member since badge
                if let user = firebaseManager.currentUser {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text("Member since \(memberSinceText(user.joinedDate))")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
    }
    
    // MARK: - Quick Stats Card
    
    private var quickStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Stats")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("View All") {
                    showingSessionHistory = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
            }
            
                         HStack(spacing: 20) {
                 ProfileStatItem(
                     icon: "music.note",
                     value: "\(totalTracks)",
                     label: "Total Tracks",
                     color: Color(red: 0.3, green: 0.7, blue: 1.0)
                 )
                 
                 ProfileStatItem(
                     icon: "clock.arrow.circlepath",
                     value: "\(dataStore.sessionHistory.count)",
                     label: "Sessions",
                     color: Color(red: 0.6, green: 0.3, blue: 0.9)
                 )
                 
                 ProfileStatItem(
                     icon: "building.2",
                     value: "\(uniqueLocations)",
                     label: "Locations",
                     color: Color(red: 1.0, green: 0.5, blue: 0.3)
                 )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Enhanced Action Cards
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                EnhancedProfileCard(
                    icon: "clock.arrow.circlepath",
                    title: "Session History",
                    subtitle: "View your \(dataStore.sessionHistory.count) listening sessions",
                    iconColor: Color(red: 0.3, green: 0.7, blue: 1.0),
                    hasData: !dataStore.sessionHistory.isEmpty
                ) {
                    showingSessionHistory = true
                }
                
                EnhancedProfileCard(
                    icon: "music.note",
                    title: "Music Preferences",
                    subtitle: spotifyManager.isAuthenticated ? "Connected to Spotify" : "Connect Spotify account",
                    iconColor: Color(red: 0.11, green: 0.73, blue: 0.33),
                    hasData: spotifyManager.isAuthenticated
                ) {
                    if !spotifyManager.isAuthenticated {
                        spotifyManager.startAuthorization()
                    }
                }
                
                EnhancedProfileCard(
                    icon: "lock.shield",
                    title: "Privacy & Settings",
                    subtitle: "Manage your data and privacy preferences",
                    iconColor: Color(red: 0.6, green: 0.3, blue: 0.9),
                    hasData: true
                ) {
                    showingSettings = true
                }
                
                EnhancedProfileCard(
                    icon: "info.circle",
                    title: "About Loci",
                    subtitle: "Learn more about the app",
                    iconColor: Color(red: 1.0, green: 0.5, blue: 0.3),
                    hasData: true
                ) {
                    showingAbout = true
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Account Management
    
    private var accountManagementSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Account")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Sign out button with better styling
            Button(action: { showingSignOutAlert = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text("Sign Out")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Helper Functions
    
    private func memberSinceText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    private var totalTracks: Int {
        let sessionTracks = dataStore.sessionHistory.reduce(0) { $0 + $1.events.count }
        let importTracks = dataStore.importBatches.reduce(0) { $0 + $1.tracks.count }
        return sessionTracks + importTracks
    }
    
    private var uniqueLocations: Int {
        let sessionLocations = Set(dataStore.sessionHistory.flatMap { session in
            session.events.compactMap { $0.buildingName }
        })
        let importLocations = Set(dataStore.importBatches.map { $0.location })
        return Set(sessionLocations).union(importLocations).count
    }
}

// MARK: - Supporting Views

struct ProfileStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EnhancedProfileCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let hasData: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon with colored background
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Status indicator and chevron
                VStack(spacing: 4) {
                    if hasData {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.08, green: 0.05, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                            
                            Text("Loci")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Music Discovery Through Location")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 40)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("About")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Loci connects your music taste with the places you visit. Track your listening habits, discover what's trending in your area, and connect with fellow music lovers.")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Version 1.0")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Built with privacy in mind")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("About")
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
}

