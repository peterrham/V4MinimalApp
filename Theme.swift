import SwiftUI

public enum AppTheme {
    public static let cornerRadius: CGFloat = 10
    public static let maxContentWidth: CGFloat = 480

    public enum Spacing {
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Colors {
        public static let surface = Color(.secondarySystemBackground)
        public static let background = Color(.systemBackground)
        public static let accent = Color.accentColor
        public static let destructive = Color.red
    }
}

public struct Card<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding()
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.cornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}
