import SwiftUI

// MARK: - Shadow Definition
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Theme System

struct LociTheme {
    // MARK: - Colors
    struct Colors {
        // Backgrounds
        static let appBackground = Color(hex: "0A001A")
        static let contentContainer = Color(hex: "150B26")
        static let cardBackground = Color(hex: "5B259F")
        static let secondaryCardBackground = Color(hex: "6C3A91")
        
        // Actions
        static let primaryAction = Color(hex: "FF2D95")
        static let secondaryHighlight = Color(hex: "00E6FF")
        
        // Text
        static let mainText = Color(hex: "F5E1DA")
        static let subheadText = Color(hex: "CDA8FF")
        
        // Accents
        static let notificationBadge = Color(hex: "FFD700")
        static let disabledState = Color(hex: "2E004F")
        
        // Gradients
        static let primaryGradient = LinearGradient(
            gradient: Gradient(colors: [primaryAction, secondaryHighlight]),
            startPoint: .leading,
            endPoint: .trailing
        )
        
        static let primaryGradientVertical = LinearGradient(
            gradient: Gradient(colors: [primaryAction, secondaryHighlight]),
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let subtleGradient = LinearGradient(
            gradient: Gradient(colors: [
                cardBackground.opacity(0.8),
                secondaryCardBackground.opacity(0.8)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Typography
    struct Typography {
        static let heading = Font.system(size: 24, weight: .semibold)
        static let subheading = Font.system(size: 16, weight: .regular)
        static let body = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let button = Font.system(size: 16, weight: .semibold)
        static let buttonSmall = Font.system(size: 14, weight: .semibold)
        
        // Special fonts
        static let timer = Font.system(size: 36, weight: .light, design: .monospaced)
        static let statNumber = Font.system(size: 20, weight: .semibold)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 40
    }
    
    // MARK: - Shadows
    struct Shadows {
        static let cardShadow = Shadow(
            color: Color(hex: "5B259F").opacity(0.2),
            radius: 6,
            x: 0,
            y: 0
        )
        
        static let glowShadow = Shadow(
            color: Color(hex: "FF2D95").opacity(0.6),
            radius: 8,
            x: 0,
            y: 0
        )
        
        static let subtleShadow = Shadow(
            color: Color(hex: "5B259F").opacity(0.2),
            radius: 4,
            x: 0,
            y: 0
        )
    }
    
    // MARK: - Animation
    struct Animation {
        static let defaultSpring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let smoothEaseInOut = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        static let bouncy = SwiftUI.Animation.interpolatingSpring(stiffness: 300, damping: 20)
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
    }
}

// MARK: - View Modifiers

struct LociCardStyle: ViewModifier {
    var backgroundColor: Color = LociTheme.Colors.cardBackground
    var shadowEnabled: Bool = true
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(LociTheme.CornerRadius.medium)
            .if(shadowEnabled) { view in
                view.shadow(
                    color: LociTheme.Shadows.cardShadow.color,
                    radius: LociTheme.Shadows.cardShadow.radius,
                    x: LociTheme.Shadows.cardShadow.x,
                    y: LociTheme.Shadows.cardShadow.y
                )
            }
    }
}

struct LociButtonStyle: ButtonStyle {
    enum ButtonType {
        case primary
        case secondary
        case subtle
        case gradient
    }
    
    var type: ButtonType = .primary
    var isFullWidth: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LociTheme.Typography.button)
            .foregroundColor(foregroundColor)
            .if(isFullWidth) { view in
                view.frame(maxWidth: .infinity)
            }
            .padding(.vertical, LociTheme.Spacing.medium)
            .padding(.horizontal, isFullWidth ? 0 : LociTheme.Spacing.large)
            .background(backgroundView)
            .cornerRadius(LociTheme.CornerRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(LociTheme.Animation.defaultSpring, value: configuration.isPressed)
    }
    
    private var foregroundColor: Color {
        switch type {
        case .primary:
            return LociTheme.Colors.appBackground
        case .secondary:
            return LociTheme.Colors.mainText
        case .subtle:
            return LociTheme.Colors.secondaryHighlight
        case .gradient:
            return LociTheme.Colors.mainText
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch type {
        case .primary:
            LociTheme.Colors.primaryAction
        case .secondary:
            LociTheme.Colors.disabledState
        case .subtle:
            Color.clear
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                        .stroke(LociTheme.Colors.secondaryHighlight, lineWidth: 1)
                )
        case .gradient:
            LociTheme.Colors.primaryGradient
                .shadow(
                    color: LociTheme.Shadows.glowShadow.color,
                    radius: LociTheme.Shadows.glowShadow.radius,
                    x: LociTheme.Shadows.glowShadow.x,
                    y: LociTheme.Shadows.glowShadow.y
                )
        }
    }
}

struct GlowModifier: ViewModifier {
    var color: Color = LociTheme.Colors.primaryAction
    var radius: CGFloat = 8
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius, x: 0, y: 0)
    }
}

struct NeonTextModifier: ViewModifier {
    var color: Color = LociTheme.Colors.primaryAction
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(LociTheme.Colors.mainText)
            .shadow(color: color.opacity(0.7), radius: 8, x: 0, y: 0)
    }
}

// MARK: - View Extensions

extension View {
    func lociCard(backgroundColor: Color = LociTheme.Colors.cardBackground, shadowEnabled: Bool = true) -> some View {
        modifier(LociCardStyle(backgroundColor: backgroundColor, shadowEnabled: shadowEnabled))
    }
    
    func lociButton(_ type: LociButtonStyle.ButtonType = .primary, isFullWidth: Bool = false) -> some View {
        buttonStyle(LociButtonStyle(type: type, isFullWidth: isFullWidth))
    }
    
    func glow(color: Color = LociTheme.Colors.primaryAction, radius: CGFloat = 8) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
    
    func neonText(color: Color = LociTheme.Colors.primaryAction) -> some View {
        modifier(NeonTextModifier(color: color))
    }
    
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Common Components

struct LociChip: View {
    let text: String
    let icon: String?
    let isActive: Bool
    let action: (() -> Void)?
    
    init(text: String, icon: String? = nil, isActive: Bool = true, action: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.xSmall) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isActive ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.notificationBadge)
            }
            
            Text(text)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
            
            if let action = action {
                Button(action: action) {
                    Text(isActive ? "Fix" : "Connect")
                        .font(LociTheme.Typography.buttonSmall)
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
        }
        .padding(.vertical, LociTheme.Spacing.xSmall)
        .padding(.horizontal, LociTheme.Spacing.small)
        .background(isActive ? LociTheme.Colors.contentContainer : LociTheme.Colors.disabledState)
        .cornerRadius(LociTheme.CornerRadius.medium)
        .shadow(
            color: LociTheme.Shadows.subtleShadow.color,
            radius: LociTheme.Shadows.subtleShadow.radius,
            x: LociTheme.Shadows.subtleShadow.x,
            y: LociTheme.Shadows.subtleShadow.y
        )
    }
}

struct LociDivider: View {
    var body: some View {
        Rectangle()
            .fill(LociTheme.Colors.disabledState)
            .frame(height: 1)
            .opacity(0.5)
    }
}

// MARK: - Preview Helpers

struct ThemePreview: View {
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: LociTheme.Spacing.large) {
                Text("Loci Theme Preview")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .neonText()
                
                Text("Subheading Text")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                HStack(spacing: LociTheme.Spacing.small) {
                    Button("Primary") {}
                        .lociButton(.primary)
                    
                    Button("Secondary") {}
                        .lociButton(.secondary)
                }
                
                Button("Gradient Button") {}
                    .lociButton(.gradient, isFullWidth: true)
                
                VStack {
                    Text("Card Example")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .lociCard()
                
                HStack(spacing: LociTheme.Spacing.small) {
                    LociChip(text: "Connected", icon: "checkmark.circle", isActive: true)
                    LociChip(text: "Disconnected", icon: "exclamationmark.triangle", isActive: false, action: {})
                }
            }
            .padding()
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
