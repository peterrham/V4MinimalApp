//
//  ScreenNameOverlay.swift
//  V4MinimalApp
//
//  Debug overlay that shows the current screen/view name below the status bar
//

import SwiftUI

/// ViewModifier that adds a debug screen name label below the status bar
struct ScreenNameOverlay: ViewModifier {
    let screenName: String
    @AppStorage("showScreenNameOverlay") private var showScreenNameOverlay = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if showScreenNameOverlay {
                Text(screenName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(.top, 50)  // Below the status bar / clock area
                    .allowsHitTesting(false)  // Don't intercept touches
            }
        }
    }
}

extension View {
    /// Adds a debug overlay showing the screen name when debug mode is enabled
    func debugScreenName(_ name: String) -> some View {
        modifier(ScreenNameOverlay(screenName: name))
    }
}
