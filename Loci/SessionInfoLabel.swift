import SwiftUI

struct SessionInfoLabel: View {
    var body: some View {
        Text("Loci will log your Spotify tracks and location every 90 seconds. You can stop anytime.")
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(Color(hex: "F5E1DA"))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
} 