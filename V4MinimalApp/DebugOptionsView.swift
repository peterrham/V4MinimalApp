//
//  DebugOptionsView.swift
//  V4MinimalApp
//
//  Debug Options - Toggle debug features and test UI interactions
//

import SwiftUI
import UIKit
import AudioToolbox
import os.log

struct DebugOptionsView: View {
    @AppStorage("showHomeDebugBar") private var showHomeDebugBar = false
    @AppStorage("verboseTapLogging") private var verboseTapLogging = false
    @AppStorage("homeUIConfig") private var homeUIConfig = "clean"

    @State private var plainButtonTaps = 0
    @State private var scaleButtonTaps = 0
    @State private var tapGestureTaps = 0
    @State private var scrollButtonTaps = 0
    @State private var showTestAlert = false
    @State private var lastTappedButton = ""
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Home UI Configuration
                debugSection("Home UI Configuration") {
                    VStack(spacing: 12) {
                        Picker("UI Config", selection: $homeUIConfig) {
                            Text("Original").tag("original")
                            Text("Clean").tag("clean")
                        }
                        .pickerStyle(.segmented)

                        Text(homeUIConfig == "original"
                             ? "Full home screen: welcome message, home title, scan button, photo thumbnails"
                             : "Minimal home screen: picker only, no scan button, category icons instead of photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Home Screen Debug Toggles
                debugSection("Home Screen Debug") {
                    VStack(spacing: 12) {
                        toggleRow(
                            icon: "rectangle.topthird.inset.filled",
                            title: "Show Debug Bar on Home",
                            subtitle: "Fixed bar above ScrollView with tap test",
                            isOn: $showHomeDebugBar
                        )

                        Divider()

                        toggleRow(
                            icon: "text.word.spacing",
                            title: "Verbose Tap Logging",
                            subtitle: "os_log for every button tap event",
                            isOn: $verboseTapLogging
                        )
                    }
                }

                // MARK: - Button Tap Tests (Outside ScrollView context)
                debugSection("Button Tap Tests") {
                    VStack(spacing: 12) {
                        Text("These buttons test different SwiftUI tap approaches.\nAll are outside a ScrollView here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Test 1: Plain Button (default style)
                        testButton(
                            label: "Plain Button",
                            count: plainButtonTaps,
                            color: .blue
                        ) {
                            plainButtonTaps += 1
                            haptic.impactOccurred()
                            AudioServicesPlaySystemSound(1104)
                            os_log("TEST: Plain Button tapped #%d", plainButtonTaps)
                        }

                        // Test 2: Button with ScaleButtonStyle
                        Button {
                            scaleButtonTaps += 1
                            haptic.impactOccurred()
                            AudioServicesPlaySystemSound(1104)
                            os_log("TEST: ScaleButton tapped #%d", scaleButtonTaps)
                        } label: {
                            testButtonLabel(
                                label: "ScaleButtonStyle",
                                count: scaleButtonTaps,
                                color: .orange
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())

                        // Test 3: .onTapGesture
                        testButtonLabel(
                            label: ".onTapGesture",
                            count: tapGestureTaps,
                            color: .green
                        )
                        .onTapGesture {
                            tapGestureTaps += 1
                            haptic.impactOccurred()
                            AudioServicesPlaySystemSound(1104)
                            os_log("TEST: onTapGesture tapped #%d", tapGestureTaps)
                        }
                    }
                }

                // MARK: - ScrollView Button Test
                debugSection("ScrollView Button Test") {
                    VStack(spacing: 12) {
                        Text("This button is inside a nested ScrollView to simulate HomeView conditions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ScrollView {
                            VStack(spacing: 12) {
                                Text("Content above button")
                                    .foregroundStyle(.secondary)

                                testButton(
                                    label: "Button Inside ScrollView",
                                    count: scrollButtonTaps,
                                    color: .purple
                                ) {
                                    scrollButtonTaps += 1
                                    haptic.impactOccurred()
                                    AudioServicesPlaySystemSound(1104)
                                    os_log("TEST: ScrollView Button tapped #%d", scrollButtonTaps)
                                }

                                Text("Content below button")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .frame(height: 200)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }

                // MARK: - Diagnostic Info
                debugSection("Diagnostic Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Plain Button taps", "\(plainButtonTaps)")
                        infoRow("ScaleButton taps", "\(scaleButtonTaps)")
                        infoRow("onTapGesture taps", "\(tapGestureTaps)")
                        infoRow("ScrollView Button taps", "\(scrollButtonTaps)")

                        Divider()

                        Button("Reset All Counters") {
                            plainButtonTaps = 0
                            scaleButtonTaps = 0
                            tapGestureTaps = 0
                            scrollButtonTaps = 0
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Debug Options")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            haptic.prepare()
        }
    }

    // MARK: - Helpers

    private func debugSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primary.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private func testButton(label: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            testButtonLabel(label: label, count: count, color: color)
        }
    }

    private func testButtonLabel(label: String, count: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(count % 2 == 0 ? color : color.opacity(0.7))
        )
        .contentShape(Rectangle())
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

#Preview {
    NavigationStack {
        DebugOptionsView()
    }
}
