
import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @State private var currentPage = 0
    @Binding var hasCompletedOnboarding: Bool
    
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
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
            
            // Skip button (except on last page)
            if currentPage < 4 {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            currentPage = 4
                        }
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .padding()
                    }
                    Spacer()
                }
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
                
                Text("Share your music taste with the world around you")
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
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
            
            Image("spotify-logo") // You'll need to add this asset
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            
            VStack(spacing: 16) {
                Text("Connect Spotify")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("We'll sync with your Spotify to track what you're listening to")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                Button(action: onConnect) {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect Spotify")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.11, green: 0.73, blue: 0.33)) // Spotify green
                    .cornerRadius(12)
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
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Start a session to begin sharing your music taste")
                    .font(.system(size: 18))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: onComplete) {
                Text("Start Using Loci")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LociTheme.Colors.primaryGradient)
                    .cornerRadius(12)
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
