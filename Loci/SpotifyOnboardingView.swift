import SwiftUI

struct SpotifyOnboardingView: View {
    @ObservedObject var spotifyManager = SpotifyManager.shared

    var body: some View {
        ZStack {
            Color(hex: "0A001A").ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Text("Welcome to Loci")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(hex: "00E6FF"))
                    .padding(.bottom, 8)
                Text("To get started, connect your Spotify account. Loci uses your listening data to create live, location-based music charts and matches. Your privacy is always protected.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "CDA8FF"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                if spotifyManager.isAuthenticated {
                    Text("✅ Connected to Spotify!")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "1DB954"))
                        .padding()
                } else {
                    Button(action: {
                        spotifyManager.startAuthorization()
                    }) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Connect to Spotify")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "121212"))
                        .padding(.vertical, 16)
                        .padding(.horizontal, 40)
                        .background(Color(hex: "1DB954"))
                        .cornerRadius(12)
                        .shadow(color: Color(hex: "00E6FF").opacity(0.2), radius: 8, x: 0, y: 0)
                    }
                }
                Spacer()
            }
        }
    }
}


