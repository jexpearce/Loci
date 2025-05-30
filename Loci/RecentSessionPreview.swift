import SwiftUI

struct RecentSessionPreview: View {
    @Binding var showingSessionHistory: Bool
    // Placeholder data
    let recentSessions: [SessionData] = [
        SessionData(id: UUID(), startTime: Date().addingTimeInterval(-3600), endTime: Date(), duration: .oneHour, events: []),
        SessionData(id: UUID(), startTime: Date().addingTimeInterval(-7200), endTime: Date().addingTimeInterval(-3600), duration: .oneHour, events: [])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hex: "CDA8FF"))
            ForEach(recentSessions.prefix(2)) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.startTime, style: .date)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "F5E1DA"))
                        Text(session.duration.displayText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "CDA8FF"))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Top Track: -")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "F5E1DA"))
                        Text("Top Artist: -")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "CDA8FF"))
                        Text("Buildings: 0")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "CDA8FF"))
                    }
                }
                .padding()
                .background(Color(hex: "5B259F"))
                .cornerRadius(12)
                .shadow(color: Color(hex: "5B259F").opacity(0.2), radius: 6, x: 0, y: 0)
            }
            Button(action: { showingSessionHistory = true }) {
                Text("View All History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "00E6FF"))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }
} 