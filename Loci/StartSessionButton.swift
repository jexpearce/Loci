import SwiftUI

struct StartSessionButton: View {
    @Binding var selectedDuration: SessionDuration
    var body: some View {
        Button(action: { /* Start session action */ }) {
            Text("Start Session")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "F5E1DA"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color(hex: "FF2D95"), Color(hex: "00E6FF")]), startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: Color(hex: "FF2D95").opacity(0.2), radius: 8, x: 0, y: 0)
        }
        .padding(.horizontal)
    }
} 