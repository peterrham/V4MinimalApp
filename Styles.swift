import SwiftUI

// MARK: - Button Styles

/// Primary button style with enhanced shadows and animations
public struct UnifiedButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(configuration.isPressed ? 
                          AppTheme.Colors.primary.opacity(0.8) : 
                          AppTheme.Colors.primary)
                    .shadow(
                        color: AppTheme.Colors.primary.opacity(0.3),
                        radius: configuration.isPressed ? 4 : 8,
                        y: configuration.isPressed ? 2 : 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Prominent action button for primary CTAs
public struct ProminentButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.Colors.primary.gradient)
                    .shadow(
                        color: AppTheme.Colors.primary.opacity(0.4),
                        radius: configuration.isPressed ? 8 : 12,
                        y: configuration.isPressed ? 4 : 6
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies a unified navigation label style with primary color background
    func unifiedNavLabel() -> some View {
        self
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.Colors.primary)
                    .shadow(
                        color: AppTheme.Colors.primary.opacity(0.3),
                        radius: 6,
                        y: 3
                    )
            )
    }
    
    /// Applies a card-like container style with material background
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.Colors.surface)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            )
    }
    
    /// Applies consistent section spacing
    func sectionSpacing() -> some View {
        self.padding(.vertical, AppTheme.Spacing.s)
    }
    
    /// Applies a subtle pressed effect for custom tap gestures
    func pressableScale(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Shadow Helpers

public extension View {
    /// Applies a subtle elevation shadow
    func elevationShadow(level: ShadowLevel = .medium) -> some View {
        self.shadow(
            color: .black.opacity(level.opacity),
            radius: level.radius,
            y: level.y
        )
    }
}

public enum ShadowLevel {
    case low, medium, high
    
    var opacity: Double {
        switch self {
        case .low: return 0.05
        case .medium: return 0.08
        case .high: return 0.12
        }
    }
    
    var radius: CGFloat {
        switch self {
        case .low: return 4
        case .medium: return 8
        case .high: return 12
        }
    }
    
    var y: CGFloat {
        switch self {
        case .low: return 2
        case .medium: return 4
        case .high: return 6
        }
    }
}
// MARK: - Custom Shapes

public struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Color Extensions

public extension Color {
    static let cardBackground = Color(.systemBackground)
    static let secondaryCardBackground = Color(.secondarySystemBackground)
    
    /// Adaptive color that works in light and dark mode
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

