import SwiftUI

struct LociHeaderView: View {
    var body: some View {
        Text("Loci")
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(Color(hex: "F5E1DA"))
            .shadow(color: Color(hex: "FF2D95").opacity(0.7), radius: 8, x: 0, y: 0)
    }
} 