import SwiftUI
import FirebaseCore
import GoogleSignIn

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
    @State private var showingImagePicker = false
    @State private var showingAbout = false
    @State private var profileImage: UIImage?
    @State private var isUploadingImage = false
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Google Sign-In will be configured automatically by FirebaseManager
        print("🚀 Loci app initialized")
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
        // Location permissions are now handled during onboarding
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

// MARK: - Enhanced User Profile View with fixes

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
    @State private var showingEditProfile = false
    @State private var profileImage: UIImage?
    @State private var isUploadingImage = false
    
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
                        
                        // Top Artists/Songs Section
                        ProfileTopItemsView() // No userId = current user
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
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(firebaseManager)
        }
        .onChange(of: profileImage) { newImage in
            guard let newImage = newImage else { return }
            uploadProfileImage(newImage)
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
    
    // MARK: - Profile Header Section (Fixed Layout)
    
    private var profileHeaderSection: some View {
        VStack(spacing: 24) {
            // Profile Picture Container - Fixed Layout
            ZStack {
                // Profile Picture
                ZStack {
                    // Background Circle
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
                    
                    // Profile Image with better caching
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else if let imageURL = firebaseManager.currentUser?.profileImageURL, !imageURL.isEmpty {
                        CachedAsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } placeholder: {
                            // Show user initials while loading
                            if let displayName = firebaseManager.currentUser?.displayName {
                                Text(String(displayName.prefix(1)).uppercased())
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                    } else {
                        // Default avatar with user initials
                        if let displayName = firebaseManager.currentUser?.displayName {
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 120))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    // Upload indicator overlay
                    if isUploadingImage {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 120, height: 120)
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Uploading...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
                
                // Camera Button - Fixed positioning
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingImagePicker = true }) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(isUploadingImage)
                        .offset(x: -8, y: -8)
                    }
                }
                .frame(width: 120, height: 120)
            }
            
            // User Info Section - Improved Layout
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    if let user = firebaseManager.currentUser {
                        Text(user.displayName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        Text("@\(user.username)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Text("Member since \(DateFormatter.shortDate.string(from: user.joinedDate))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("Loading...")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Edit Profile Button
                Button(action: { showingEditProfile = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Edit Profile")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Quick Stats Card
    
    private var quickStatsCard: some View {
        VStack(spacing: 20) {
            Text("Your Music Stats")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                ProfileStatItem(
                    icon: "music.note",
                    value: "\(totalTracks)",
                    label: "Total Tracks",
                    color: Color(red: 0.9, green: 0.3, blue: 0.6)
                )
                
                ProfileStatItem(
                    icon: "clock.arrow.circlepath",
                    value: "\(dataStore.sessionHistory.count)",
                    label: "Sessions",
                    color: Color(red: 0.3, green: 0.7, blue: 1.0)
                )
                
                ProfileStatItem(
                    icon: "building.2",
                    value: "\(uniqueLocations)",
                    label: "Locations",
                    color: Color(red: 0.9, green: 0.6, blue: 0.2)
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Enhanced Action Cards
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            Text("Your Activity")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                EnhancedProfileCard(
                    icon: "clock.arrow.circlepath",
                    title: "Session History",
                    subtitle: "View your listening sessions",
                    iconColor: Color(red: 0.3, green: 0.7, blue: 1.0),
                    hasData: !dataStore.sessionHistory.isEmpty,
                    action: { showingSessionHistory = true }
                )
                
                EnhancedProfileCard(
                    icon: "square.and.arrow.down",
                    title: "Spotify Imports",
                    subtitle: "Music you've shared",
                    iconColor: Color(red: 0.9, green: 0.3, blue: 0.6),
                    hasData: !dataStore.importBatches.isEmpty,
                    action: { /* Show imports */ }
                )
                
                EnhancedProfileCard(
                    icon: "chart.bar.xaxis",
                    title: "Analytics",
                    subtitle: "Your listening insights",
                    iconColor: Color(red: 0.9, green: 0.6, blue: 0.2),
                    hasData: totalTracks > 0,
                    action: { /* Show analytics */ }
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Account Management
    
    private var accountManagementSection: some View {
        VStack(spacing: 16) {
            Text("Account")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                EnhancedProfileCard(
                    icon: "gearshape",
                    title: "Settings",
                    subtitle: "Privacy & preferences",
                    iconColor: .gray,
                    hasData: true,
                    action: { showingSettings = true }
                )
                
                EnhancedProfileCard(
                    icon: "info.circle",
                    title: "About Loci",
                    subtitle: "App info & support",
                    iconColor: .blue,
                    hasData: true,
                    action: { showingAbout = true }
                )
                
                Button(action: { showingSignOutAlert = true }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign Out")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                            
                            Text("Sign out of your account")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Helper Methods
    
    private func uploadProfileImage(_ image: UIImage) {
        isUploadingImage = true
        
        Task {
            do {
                // Compress image to reasonable size (max 1MB)
                guard let imageData = compressImage(image, maxSizeKB: 1024) else {
                    await MainActor.run {
                        isUploadingImage = false
                    }
                    return
                }
                
                // Upload to Firebase Storage
                let _ = try await firebaseManager.uploadProfilePicture(imageData)
                
                await MainActor.run {
                    isUploadingImage = false
                    // Clear the local profile image and cache so it reloads from Firebase
                    profileImage = nil
                    
                    // Clear cached version if it exists
                    if let imageURL = firebaseManager.currentUser?.profileImageURL {
                        ImageCache.shared.removeImage(for: imageURL)
                    }
                }
            } catch {
                await MainActor.run {
                    isUploadingImage = false
                    print("Error uploading profile image: \(error)")
                    // Could show an alert here
                }
            }
        }
    }
    
    private func compressImage(_ image: UIImage, maxSizeKB: Int) -> Data? {
        let maxBytes = maxSizeKB * 1024
        var compression: CGFloat = 1.0
        var imageData = image.jpegData(compressionQuality: compression)
        
        // Reduce quality until under size limit
        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }
        
        return imageData
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

// MARK: - Enhanced Cached Async Image for better persistence

struct CachedAsyncImage<Content, Placeholder>: View where Content: View, Placeholder: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var cachedImage: UIImage?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let cachedImage = cachedImage {
                content(Image(uiImage: cachedImage))
            } else if isLoading {
                placeholder()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url, cachedImage == nil, !isLoading else { return }
        
        isLoading = true
        
        // Check cache first
        if let cachedData = ImageCache.shared.image(for: url.absoluteString) {
            self.cachedImage = cachedData
            self.isLoading = false
            return
        }
        
        // Download image
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            // Cache the image
            ImageCache.shared.setImage(image, for: url.absoluteString)
            
            DispatchQueue.main.async {
                self.cachedImage = image
                self.isLoading = false
            }
        }.resume()
    }
}

// MARK: - Enhanced Image Cache with Persistent Storage

class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        // Create cache directory
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("ImageCache")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func setImage(_ image: UIImage, for key: String) {
        // Store in memory cache
        cache.setObject(image, forKey: NSString(string: key))
        
        // Store in persistent cache
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
        let fileURL = cacheDirectory.appendingPathComponent("\(filename).jpg")
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }
    
    func image(for key: String) -> UIImage? {
        // Check memory cache first
        if let cachedImage = cache.object(forKey: NSString(string: key)) {
            return cachedImage
        }
        
        // Check persistent cache
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
        let fileURL = cacheDirectory.appendingPathComponent("\(filename).jpg")
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // Store back in memory cache
            cache.setObject(image, forKey: NSString(string: key))
            return image
        }
        
        return nil
    }
    
    func removeImage(for key: String) {
        cache.removeObject(forKey: NSString(string: key))
        
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
        let fileURL = cacheDirectory.appendingPathComponent("\(filename).jpg")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @State private var displayName = ""
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isExistingAccount = false
    
    var body: some View {
        NavigationView {
            ZStack {
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
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("Edit Profile")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Name")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                TextField("", text: $displayName)
                                    .textFieldStyle(EditProfileTextFieldStyle())
                            }
                            
                            if !isExistingAccount {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Username")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    HStack {
                                        Text("@")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.white.opacity(0.6))
                                            .padding(.leading, 16)
                                        
                                        TextField("", text: $username)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .autocapitalization(.none)
                                            .foregroundColor(.white)
                                            .padding(.vertical, 16)
                                            .padding(.trailing, 16)
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                    
                                    if !username.isEmpty && !isValidUsername(username) {
                                        Text("Username must be 3-20 characters (letters, numbers, underscores only)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Username")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Text("@\(username)")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.05))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                                )
                                        )
                                    
                                    Text("Username editing temporarily disabled for existing accounts")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            
                            // Messages
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                            
                            if let successMessage = successMessage {
                                Text(successMessage)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.green)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Save Button
                            Button(action: saveProfile) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Save Changes")
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                }
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
                            .disabled(isLoading || !isFormValid)
                            .opacity(isLoading || !isFormValid ? 0.6 : 1.0)
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            print("📱 EditProfileView appeared")
            loadCurrentUserData()
        }
        .onReceive(firebaseManager.$currentUser) { user in
            print("👤 Current user updated: \(user?.displayName ?? "nil")")
            if user != nil {
                loadCurrentUserData()
            }
        }
    }
    
    private var isFormValid: Bool {
        if isExistingAccount {
            return !displayName.isEmpty
        } else {
            return !displayName.isEmpty && !username.isEmpty && isValidUsername(username)
        }
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        let regex = "^[a-zA-Z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: username)
    }
    
    private func loadCurrentUserData() {
        print("🔍 Loading current user data...")
        
        if let user = firebaseManager.currentUser {
            print("✅ User found: \(user.displayName), username: '\(user.username)'")
            displayName = user.displayName
            
            // Handle existing accounts that might not have username set properly
            if user.username.isEmpty || user.username == "Loading..." {
                print("⚠️ Username is empty or invalid, generating suggested username")
                // Generate a suggested username from display name or email
                let suggestedUsername = generateSuggestedUsername(from: user.displayName, email: user.email)
                username = suggestedUsername
                isExistingAccount = false // Allow them to set their username
                print("💡 Generated username: \(suggestedUsername)")
            } else {
                print("✅ Using existing username: \(user.username)")
                username = user.username
                isExistingAccount = true // Don't allow changing existing usernames
            }
        } else {
            print("❌ No current user found")
            // Set fallback values
            displayName = ""
            username = "user_" + String(Int.random(in: 1000...9999))
            isExistingAccount = false
        }
        
        print("📝 Final values - displayName: '\(displayName)', username: '\(username)', isExisting: \(isExistingAccount)")
    }
    
    private func generateSuggestedUsername(from displayName: String, email: String) -> String {
        // First try to create username from display name
        let cleanDisplayName = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        
        if cleanDisplayName.count >= 3 {
            return String(cleanDisplayName.prefix(15))
        }
        
        // Fallback to email prefix
        let emailPrefix = email.components(separatedBy: "@").first ?? "user"
        let cleanEmailPrefix = emailPrefix
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        
        return String(cleanEmailPrefix.prefix(15))
    }
    
    private func saveProfile() {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                // For existing accounts that might not have username field, 
                // we need to handle this more carefully
                var updates: [String: Any] = [
                    "displayName": displayName
                ]
                
                // Only update username if it's different, valid, and user is allowed to change it
                let currentUsername = firebaseManager.currentUser?.username ?? ""
                if !isExistingAccount && username.lowercased() != currentUsername.lowercased() && !username.isEmpty {
                    // Check if username is taken
                    try await checkUsernameAvailability()
                    updates["username"] = username.lowercased()
                } else if currentUsername.isEmpty || currentUsername == "Loading..." {
                    // Force update for accounts with missing/invalid usernames
                    if !username.isEmpty && isValidUsername(username) {
                        try await checkUsernameAvailability()
                        updates["username"] = username.lowercased()
                    }
                }
                
                // Try to update profile using safer method
                try await firebaseManager.safeUpdateUserProfile(updates)
                
                await MainActor.run {
                    isLoading = false
                    successMessage = "Profile updated successfully!"
                    
                    // Dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    
                    // Provide more helpful error messages
                    if error.localizedDescription.contains("permission") || error.localizedDescription.contains("insufficient") {
                        errorMessage = "Unable to update username. This might be due to account restrictions. Try updating just your display name for now."
                    } else if let firebaseError = error as? FirebaseError {
                        errorMessage = firebaseError.localizedDescription
                    } else {
                        errorMessage = "Update failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func checkUsernameAvailability() async throws {
        try await firebaseManager.checkUsernameAvailability(username: username, excludeCurrentUser: true)
    }
}

struct EditProfileTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
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

