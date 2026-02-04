//
//  OpenAIRealtimeView.swift
//  V4MinimalApp
//
//  Voice conversation UI for OpenAI Realtime API with timing dashboard
//

import SwiftUI

struct OpenAIRealtimeView: View {
    @StateObject private var realtimeService = OpenAIRealtimeService()
    @State private var showEventLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.l) {
                // Connection Status Card
                connectionCard

                // Timing Metrics Card
                if realtimeService.connectionState == .connected ||
                   realtimeService.timingMetrics.wsConnectDurationMs != nil {
                    timingCard
                }

                // Error Banner
                if let error = realtimeService.error {
                    errorBanner(error)
                }

                // User Transcript
                transcriptCard(
                    title: "You Said:",
                    text: realtimeService.userTranscript,
                    icon: "person.fill",
                    color: .blue
                )

                // Assistant Transcript
                transcriptCard(
                    title: "Assistant:",
                    text: realtimeService.assistantTranscript,
                    icon: "brain.head.profile",
                    color: .green
                )

                // Hold-to-Talk Button
                if realtimeService.connectionState == .connected {
                    holdToTalkButton
                }
            }
            .padding(AppTheme.Spacing.l)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("OpenAI Realtime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEventLog = true
                    } label: {
                        Label("Event Log", systemImage: "list.bullet.rectangle")
                    }
                    Button(role: .destructive) {
                        realtimeService.clearLog()
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEventLog) {
            eventLogSheet
        }
        .onDisappear {
            realtimeService.disconnect()
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            HStack(spacing: AppTheme.Spacing.m) {
                // Status dot
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(connectionDotColor.opacity(0.4), lineWidth: 2)
                            .scaleEffect(realtimeService.connectionState == .connecting ? 1.5 : 1.0)
                            .opacity(realtimeService.connectionState == .connecting ? 1 : 0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: realtimeService.connectionState == .connecting)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenAI Realtime")
                        .font(.headline)
                    Text(realtimeService.connectionState.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if realtimeService.connectionState == .connected {
                        realtimeService.disconnect()
                    } else {
                        realtimeService.connect()
                    }
                } label: {
                    Text(realtimeService.connectionState == .connected ? "Disconnect" : "Connect")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(realtimeService.connectionState == .connected ? Color.red.opacity(0.15) : AppTheme.Colors.primary.opacity(0.15))
                        .foregroundStyle(realtimeService.connectionState == .connected ? .red : AppTheme.Colors.primary)
                        .cornerRadius(8)
                }
                .disabled(realtimeService.connectionState == .connecting)
            }

            if !realtimeService.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("OpenAI API key not configured. Add OpenAIAPIKey to Info.plist or Config.plist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(AppTheme.Spacing.s)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    private var connectionDotColor: Color {
        switch realtimeService.connectionState {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    // MARK: - Timing Card

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            Label("Timing", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppTheme.Spacing.s) {
                metricPill("WS Connect", value: formatMs(realtimeService.timingMetrics.wsConnectDurationMs))
                metricPill("TTFB", value: formatMs(realtimeService.timingMetrics.ttfbMs))
                metricPill("Total", value: formatMs(realtimeService.timingMetrics.totalResponseTimeMs))
                metricPill("Sent", value: formatBytes(realtimeService.timingMetrics.totalAudioBytesSent))
                metricPill("Chunks", value: "\(realtimeService.timingMetrics.totalAudioChunksSent)")
                metricPill("Deltas", value: "\(realtimeService.timingMetrics.totalResponseDeltasReceived)")
            }
        }
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    private func metricPill(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func formatMs(_ ms: Int?) -> String {
        guard let ms = ms else { return "--" }
        return "\(ms)ms"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "0B" }
        if bytes < 1024 { return "\(bytes)B" }
        return String(format: "%.1fKB", Double(bytes) / 1024.0)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(AppTheme.Spacing.m)
        .background(Color.red.opacity(0.1))
        .cornerRadius(AppTheme.cornerRadius)
    }

    // MARK: - Transcript Card

    private func transcriptCard(title: String, text: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            if text.isEmpty {
                Text("Waiting for audio...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    // MARK: - Hold-to-Talk

    private var holdToTalkButton: some View {
        VStack(spacing: AppTheme.Spacing.s) {
            ZStack {
                Circle()
                    .fill(realtimeService.isRecording ? Color.red.opacity(0.2) : AppTheme.Colors.primary.opacity(0.15))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(realtimeService.isRecording ? Color.red : AppTheme.Colors.primary)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: realtimeService.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    )
                    .scaleEffect(realtimeService.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: realtimeService.isRecording)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !realtimeService.isRecording {
                            realtimeService.startRecording()
                        }
                    }
                    .onEnded { _ in
                        realtimeService.stopRecording()
                    }
            )

            Text(realtimeService.isRecording ? "Release to send" : "Hold to talk")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.l)
    }

    // MARK: - Event Log Sheet

    private var eventLogSheet: some View {
        NavigationStack {
            List {
                if realtimeService.eventLog.isEmpty {
                    Text("No events yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(realtimeService.eventLog.reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.direction.arrow)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(directionColor(entry.direction))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.eventType)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)

                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Event Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        realtimeService.clearLog()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showEventLog = false
                    }
                }
            }
        }
    }

    private func directionColor(_ direction: RealtimeLogEntry.Direction) -> Color {
        switch direction {
        case .sent: return .blue
        case .received: return .green
        case .system: return .orange
        }
    }
}

#Preview {
    NavigationStack {
        OpenAIRealtimeView()
    }
}
