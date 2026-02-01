//
//  GoogleSignInView.swift
//  V4MinimalApp
//
//  Sign-in screen shown on first launch when not authenticated.
//

import SwiftUI

struct GoogleSignInView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.25),
                    Color(red: 0.08, green: 0.08, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon
                Image(systemName: "house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.Colors.primary)
                    .padding(.bottom, AppTheme.Spacing.l)

                // App title
                Text("Home Inventory")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Catalog your home with AI")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, AppTheme.Spacing.xs)

                Spacer()

                // Sign in button
                Button {
                    isSigningIn = true
                    AuthManager.shared.googleSignInManager?.signIn {
                        isSigningIn = false
                        appState.checkAuthStatus()
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.m) {
                        if isSigningIn {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title3)
                        }
                        Text("Sign In with Google")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .fill(AppTheme.Colors.primary)
                    )
                }
                .disabled(isSigningIn)
                .padding(.horizontal, AppTheme.Spacing.xxl)

                // Skip for now
                Button {
                    appState.skipAuth()
                } label: {
                    Text("Continue without signing in")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, AppTheme.Spacing.l)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
}
