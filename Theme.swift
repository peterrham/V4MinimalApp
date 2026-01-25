import SwiftUI

public enum AppTheme {
    public static let cornerRadius: CGFloat = 12
    public static let maxContentWidth: CGFloat = 480

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Colors {
        // Primary Brand Color - Indigo
        public static let primary = Color(hex: "#6366F1")
        public static let primaryLight = Color(hex: "#818CF8")
        public static let primaryDark = Color(hex: "#4F46E5")
        
        // Semantic Colors
        public static let success = Color(hex: "#10B981")
        public static let warning = Color(hex: "#F59E0B")
        public static let error = Color(hex: "#EF4444")
        
        // Background Colors
        public static let surface = Color(.secondarySystemBackground)
        public static let background = Color(.systemBackground)
        public static let backgroundDark = Color(hex: "#1E293B")
        
        // Legacy support
        public static let accent = Color.accentColor
        public static let destructive = Color.red
    }
    
    public enum Typography {
        public static let largeTitle: Font = .system(size: 34, weight: .bold, design: .default)
        public static let title: Font = .system(size: 28, weight: .bold, design: .default)
        public static let title2: Font = .system(size: 22, weight: .bold, design: .default)
        public static let headline: Font = .system(size: 17, weight: .semibold, design: .default)
        public static let body: Font = .system(size: 17, weight: .regular, design: .default)
        public static let callout: Font = .system(size: 16, weight: .regular, design: .default)
        public static let caption: Font = .system(size: 13, weight: .regular, design: .default)
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Card Component

public struct Card<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { 
        self.content = content() 
    }
    
    public var body: some View {
        content
            .padding(AppTheme.Spacing.l)
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.cornerRadius)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
// MARK: - Primary Action Card

public struct PrimaryActionCard<Content: View>: View {
    private let content: Content
    private let action: () -> Void
    
    public init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }
    
    public var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .padding(AppTheme.Spacing.l)
        }
        .background(AppTheme.Colors.primary.gradient)
        .foregroundColor(.white)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: AppTheme.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

