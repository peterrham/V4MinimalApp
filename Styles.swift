import SwiftUI

public struct UnifiedButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.7) : Color.accentColor)
            .cornerRadius(10)
    }
}

public extension View {
    func unifiedNavLabel() -> some View {
        self
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor)
            .cornerRadius(10)
    }
}
