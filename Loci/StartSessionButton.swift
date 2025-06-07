import SwiftUI

struct StartSessionButton: View {
    let mode: SessionMode
    let duration: SessionDuration?
    let location: String?
    let canStart: Bool
    
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        Button(action: startSession) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "play.fill")
                Text("Start \(mode.displayName) Session")
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.6)
    }
    
    private func startSession() {
        sessionManager.startSession(
            mode: mode,
            duration: duration,
            initialBuilding: location
        )
    }
}
