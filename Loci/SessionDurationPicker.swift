import SwiftUI

struct SessionDurationPicker: View {
    @Binding var selectedDuration: SessionDuration
    let options: [SessionDuration] = [.thirtyMinutes, .oneHour, .twoHours, .fourHours, .eightHours, .twelveHours]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { duration in
                Button(action: { selectedDuration = duration }) {
                    Text(duration.displayText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(selectedDuration == duration ? Color(hex: "0A001A") : Color(hex: "F5E1DA"))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(selectedDuration == duration ? Color(hex: "00E6FF") : Color(hex: "2E004F"))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }
} 