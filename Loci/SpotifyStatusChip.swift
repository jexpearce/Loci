import SwiftUI

struct SpotifyStatusChip: View {
    // Placeholder for actual Spotify auth state
    var isAuthorized: Bool = true
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isAuthorized ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundColor(isAuthorized ? Color(hex: "00E6FF") : Color(hex: "FFD700"))
                .font(.system(size: 16, weight: .regular))
            Text(isAuthorized ? "Spotify Connected" : "Connect Spotify")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(hex: "F5E1DA"))
            if !isAuthorized {
                Button(action: { /* Reconnect action */ }) {
                    Text("Reconnect")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "00E6FF"))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(hex: isAuthorized ? "150B26" : "2E004F"))
        .cornerRadius(12)
        .shadow(color: Color(hex: "5B259F").opacity(0.2), radius: 4, x: 0, y: 0)
    }
} 