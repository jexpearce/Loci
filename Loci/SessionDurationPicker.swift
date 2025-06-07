import SwiftUI

// MARK: - Session Duration Picker (Updated for On-the-Move mode only)

struct SessionDurationPicker: View {
    @Binding var selectedDuration: SessionDuration
    let mode: SessionMode
    
    // Only show for On-the-Move mode, with 6-hour maximum
    private var availableOptions: [SessionDuration] {
        switch mode {
        case .onTheMove:
            return SessionDuration.onTheMoveOptions // Max 6 hours
        case .onePlace:
            return [] // One-place sessions don't use duration picker
        case .unknown:
            return []
        }
    }
    
    var body: some View {
        if mode == .onTheMove && !availableOptions.isEmpty {
            VStack(spacing: LociTheme.Spacing.medium) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                        Text("Session Duration")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("Choose how long to track (max 6 hours)")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    
                    Spacer()
                    
                    // Selected duration badge
                    Text(selectedDuration.displayText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.appBackground)
                        .padding(.horizontal, LociTheme.Spacing.small)
                        .padding(.vertical, LociTheme.Spacing.xxSmall)
                        .background(LociTheme.Colors.primaryAction)
                        .cornerRadius(LociTheme.CornerRadius.small)
                }
                
                // Duration chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LociTheme.Spacing.small) {
                        ForEach(availableOptions, id: \.self) { duration in
                            DurationChip(
                                duration: duration,
                                isSelected: selectedDuration == duration,
                                isRecommended: duration == .twoHours
                            ) {
                                withAnimation(LociTheme.Animation.smoothEaseInOut) {
                                    selectedDuration = duration
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LociTheme.Spacing.small)
                }
                
                // Info footer
                HStack(spacing: LociTheme.Spacing.small) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                    
                    Text("Session will automatically stop after the selected time to preserve battery")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(LociTheme.Spacing.small)
                .background(LociTheme.Colors.primaryAction.opacity(0.1))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}

// MARK: - Duration Chip (Enhanced)

struct DurationChip: View {
    let duration: SessionDuration
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: LociTheme.Spacing.xxSmall) {
                // Duration text
                Text(duration.displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(textColor)
                
                // Recommended badge
                if isRecommended && !isSelected {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                        .opacity(0.8)
                } else if isSelected {
                    Text("Selected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(LociTheme.Colors.appBackground.opacity(0.8))
                }
            }
            .frame(minWidth: 60)
            .padding(.horizontal, LociTheme.Spacing.medium)
            .padding(.vertical, LociTheme.Spacing.small)
            .background(backgroundView)
            .overlay(overlayView)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(LociTheme.Animation.bouncy, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColor: Color {
        if isSelected {
            return LociTheme.Colors.appBackground
        } else {
            return LociTheme.Colors.mainText
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
            .fill(
                isSelected
                    ? AnyShapeStyle(LociTheme.Colors.primaryGradient)
                    : AnyShapeStyle(isRecommended ? LociTheme.Colors.secondaryHighlight.opacity(0.1) : LociTheme.Colors.disabledState)
            )
    }
    
    @ViewBuilder
    private var overlayView: some View {
        if !isSelected {
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .stroke(
                    isRecommended ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState,
                    lineWidth: isRecommended ? 1.5 : 1
                )
        }
    }
}

// MARK: - Compact Duration Picker (For smaller spaces)

struct CompactSessionDurationPicker: View {
    @Binding var selectedDuration: SessionDuration
    let mode: SessionMode
    
    private var availableOptions: [SessionDuration] {
        switch mode {
        case .onTheMove:
            return SessionDuration.onTheMoveOptions
        case .onePlace:
            return []
        case .unknown:
            return []
        }
    }
    
    var body: some View {
        if mode == .onTheMove && !availableOptions.isEmpty {
            HStack(spacing: LociTheme.Spacing.small) {
                Text("Duration:")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Menu {
                    ForEach(availableOptions, id: \.self) { duration in
                        Button(duration.displayText) {
                            selectedDuration = duration
                        }
                    }
                } label: {
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Text(selectedDuration.displayText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xSmall)
                    .background(LociTheme.Colors.disabledState)
                    .cornerRadius(LociTheme.CornerRadius.small)
                }
                
                Spacer()
                
                Text("Max 6h")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
    }
}

// MARK: - Duration Info Card

struct DurationInfoCard: View {
    let selectedDuration: SessionDuration
    let mode: SessionMode
    
    var body: some View {
        if mode == .onTheMove {
            VStack(spacing: LociTheme.Spacing.small) {
                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    Text("Session Info")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                VStack(spacing: LociTheme.Spacing.small) {
                    InfoRow(
                        icon: "timer",
                        label: "Duration",
                        value: selectedDuration.displayText
                    )
                    
                    InfoRow(
                        icon: "location.circle",
                        label: "Tracking",
                        value: "Every 90 seconds"
                    )
                    
                    InfoRow(
                        icon: "bolt.circle",
                        label: "Battery",
                        value: batteryImpact
                    )
                    
                    InfoRow(
                        icon: "calendar.badge.clock",
                        label: "Auto-stops at",
                        value: endTime
                    )
                }
            }
            .padding(LociTheme.Spacing.medium)
            .background(LociTheme.Colors.contentContainer.opacity(0.5))
            .cornerRadius(LociTheme.CornerRadius.medium)
        }
    }
    
    private var batteryImpact: String {
        switch selectedDuration {
        case .thirtyMinutes: return "Minimal"
        case .oneHour: return "Low"
        case .twoHours: return "Low"
        case .fourHours: return "Moderate"
        case .sixHours: return "Moderate"
        default: return "Moderate"
        }
    }
    
    private var endTime: String {
        let endDate = Date().addingTimeInterval(selectedDuration.timeInterval)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endDate)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LociTheme.Colors.mainText)
        }
    }
}

// MARK: - Duration Comparison View

struct DurationComparisonView: View {
    @Binding var selectedDuration: SessionDuration
    
    private let durations = SessionDuration.onTheMoveOptions
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Text("Choose Your Duration")
                .font(LociTheme.Typography.subheading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            VStack(spacing: LociTheme.Spacing.small) {
                ForEach(durations, id: \.self) { duration in
                    DurationComparisonRow(
                        duration: duration,
                        isSelected: selectedDuration == duration,
                        batteryImpact: batteryImpactFor(duration),
                        useCase: useCaseFor(duration)
                    ) {
                        withAnimation(LociTheme.Animation.smoothEaseInOut) {
                            selectedDuration = duration
                        }
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
    
    private func batteryImpactFor(_ duration: SessionDuration) -> String {
        switch duration {
        case .thirtyMinutes: return "Minimal"
        case .oneHour: return "Low"
        case .twoHours: return "Low"
        case .fourHours: return "Moderate"
        case .sixHours: return "Higher"
        default: return "Moderate"
        }
    }
    
    private func useCaseFor(_ duration: SessionDuration) -> String {
        switch duration {
        case .thirtyMinutes: return "Quick coffee break"
        case .oneHour: return "Lunch or short study session"
        case .twoHours: return "Movie, workout, or meeting"
        case .fourHours: return "Work session or long commute"
        case .sixHours: return "Full work day or travel"
        default: return "General use"
        }
    }
}

// MARK: - Duration Comparison Row

struct DurationComparisonRow: View {
    let duration: SessionDuration
    let isSelected: Bool
    let batteryImpact: String
    let useCase: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(duration.displayText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text(useCase)
                        .font(.system(size: 13))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Battery: \(batteryImpact)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(batteryColor)
                    
                    if duration == .twoHours {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
            .padding(LociTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                    .fill(isSelected ? LociTheme.Colors.secondaryHighlight.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                            .stroke(
                                isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var batteryColor: Color {
        switch batteryImpact {
        case "Minimal", "Low": return LociTheme.Colors.secondaryHighlight
        case "Moderate": return LociTheme.Colors.primaryAction
        case "Higher": return Color.orange
        default: return LociTheme.Colors.subheadText
        }
    }
}

