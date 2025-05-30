import SwiftUI

struct SocialTeaserCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: "FFD700"))
                .frame(width: 8, height: 8)
                .opacity(0.8)
                .overlay(
                    Circle()
                        .stroke(Color(hex: "FFD700").opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.2)
                        .opacity(0.5)
                        .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: UUID())
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("3 people tracking now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "F5E1DA"))
                Text("Top song in this building: 'Neon Skyline'")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "CDA8FF"))
            }
            Spacer()
        }
        .padding()
        .background(Color(hex: "6C3A91"))
        .cornerRadius(12)
        .shadow(color: Color(hex: "5B259F").opacity(0.2), radius: 6, x: 0, y: 0)
        .padding(.horizontal)
    }
} 