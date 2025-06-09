
import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @State private var currentPage = 0
    @Binding var hasCompletedOnboarding: Bool
    
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    
    private let totalPages = 5
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            VStack {
                // Progress indicator
                if currentPage > 0 && currentPage < 4 {
                    HStack {
                        Spacer()
                        ProgressView(value: Double(currentPage), total: Double(totalPages - 1))
                            .progressViewStyle(LinearProgressViewStyle(tint: LociTheme.Colors.primaryAction))
                            .frame(width: 100)
                        Text("\(currentPage)/\(totalPages - 1)")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.horizontal)
                }
                
                TabView(selection: $currentPage) {
                // Page 1: Welcome
                OnboardingWelcomePage()
                    .tag(0)
                
                // Page 2: How it works
                OnboardingHowItWorksPage()
                    .tag(1)
                
                // Page 3: Spotify Connect
                OnboardingSpotifyPage(
                    isConnected: spotifyManager.isAuthenticated,
                    onConnect: { spotifyManager.startAuthorization() }
                )
                .tag(2)
                
                // Page 4: Location Permission
                OnboardingLocationPage(
                    authStatus: locationManager.authorizationStatus,
                    onRequestPermission: { locationManager.requestPermissions() }
                )
                .tag(3)
                
                // Page 5: Get Started
                OnboardingCompletePage(
                    onComplete: {
                        hasCompletedOnboarding = true
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    }
                )
                .tag(4)
                }
                .tabViewStyle(PageTabViewStyle())
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                // Navigation controls
                HStack {
                    // Back button
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage -= 1
                            }
                        }
                        .foregroundColor(LociTheme.Colors.subheadText)
                    } else {
                        Spacer()
                            .frame(width: 50)
                    }
                    
                    Spacer()
                    
                    // Next/Skip button
                    if currentPage < 4 {
                        HStack(spacing: 20) {
                            if currentPage < 3 {
                                Button("Next") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentPage += 1
                                    }
                                }
                                .foregroundColor(LociTheme.Colors.primaryAction)
                                .font(.system(size: 16, weight: .medium))
                            }
                            
                            Button("Skip") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPage = 4
                                }
                            }
                            .foregroundColor(LociTheme.Colors.subheadText)
                        }
                    } else {
                        Spacer()
                            .frame(width: 50)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Welcome Page

struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 20)
            
            VStack(spacing: 16) {
                Text("Welcome to Loci")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Thanks for joining! Let's get you set up to share your music taste with the world around you.")
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.wave.2.fill")
                        .foregroundColor(LociTheme.Colors.primaryAction)
                    Text("Connect with music lovers nearby")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.mainText)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    Text("See what's trending in your area")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.mainText)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(LociTheme.Colors.notificationBadge)
                    Text("Discover new music through location")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.mainText)
                    Spacer()
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - How It Works Page

struct OnboardingHowItWorksPage: View {
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Text("How It Works")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: 30) {
                OnboardingFeatureRow(
                    icon: "location.square.fill",
                    iconColor: LociTheme.Colors.secondaryHighlight,
                    title: "Track Your Music",
                    description: "Your Spotify plays are tagged with your location"
                )
                
                OnboardingFeatureRow(
                    icon: "chart.bar.xaxis",
                    iconColor: LociTheme.Colors.primaryAction,
                    title: "See Local Trends",
                    description: "Discover what's popular in your building or area"
                )
                
                OnboardingFeatureRow(
                    icon: "person.2.fill",
                    iconColor: LociTheme.Colors.notificationBadge,
                    title: "Find Your People",
                    description: "Connect with others who share your music taste"
                )
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 30)
    }
}

// MARK: - Spotify Connect Page

struct OnboardingSpotifyPage: View {
    let isConnected: Bool
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Use music note icon if Spotify logo isn't available
            Image(systemName: "music.note.list")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.11, green: 0.73, blue: 0.33))
                .glow(color: Color(red: 0.11, green: 0.73, blue: 0.33), radius: 15)
            
            VStack(spacing: 16) {
                Text("Connect Spotify")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Loci uses your listening data to create live, location-based music charts and matches. Your privacy is always protected.")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Privacy benefits
            VStack(spacing: 16) {
                OnboardingPrivacyPoint(
                    icon: "shield.fill",
                    text: "Your listening data stays secure"
                )
                
                OnboardingPrivacyPoint(
                    icon: "chart.bar.fill",
                    text: "Only anonymized trends are shared"
                )
            }
            .padding(.horizontal, 40)
            
            if isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("✅ Connected to Spotify!")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                Button(action: onConnect) {
                    HStack {
                        Image(systemName: "music.note")
                        Text("Connect to Spotify")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.11, green: 0.73, blue: 0.33)) // Spotify green
                    .cornerRadius(12)
                    .shadow(color: LociTheme.Colors.secondaryHighlight.opacity(0.3), radius: 8, x: 0, y: 0)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Location Permission Page

struct OnboardingLocationPage: View {
    let authStatus: CLAuthorizationStatus
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "location.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(LociTheme.Colors.primaryAction)
            
            VStack(spacing: 16) {
                Text("Enable Location")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("We use your location to tag your music and show you what's trending nearby")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 20) {
                OnboardingPrivacyPoint(
                    icon: "lock.shield.fill",
                    text: "Your location is never shared without permission"
                )
                
                OnboardingPrivacyPoint(
                    icon: "battery.100",
                    text: "Smart tracking minimizes battery usage"
                )
            }
            .padding(.horizontal, 40)
            
            if authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Location Enabled")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                Button(action: onRequestPermission) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Enable Location")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LociTheme.Colors.primaryAction)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Complete Page

struct OnboardingCompletePage: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "party.popper.fill")
                .font(.system(size: 80))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 20)
            
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Welcome to the Loci community! You're ready to start sharing your music taste and discovering what's trending around you.")
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 16) {
                Text("Next steps:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text("1.")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        Text("Start a listening session")
                            .font(.system(size: 16))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Text("2.")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        Text("Play music on Spotify")
                            .font(.system(size: 16))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Text("3.")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        Text("Discover trends & connect with others")
                            .font(.system(size: 16))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Button(action: onComplete) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Using Loci")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(LociTheme.Colors.primaryGradient)
                .cornerRadius(12)
                .shadow(color: LociTheme.Colors.primaryAction.opacity(0.3), radius: 8, x: 0, y: 0)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Helper Views

struct OnboardingFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(iconColor)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
}

struct OnboardingPrivacyPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(LociTheme.Colors.primaryAction)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.mainText)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
    }
}
