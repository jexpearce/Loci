import SwiftUI

struct LiveIndicator: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color(hex: "FFD700"))
            .frame(width: 8, height: 8)
            .shadow(color: Color(hex: "FFD700").opacity(0.6), radius: 8, x: 0, y: 0)
            .scaleEffect(pulse ? 1.4 : 1.0)
            .opacity(pulse ? 0.4 : 1.0)
            .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .padding(.top, 8)
    }
} 