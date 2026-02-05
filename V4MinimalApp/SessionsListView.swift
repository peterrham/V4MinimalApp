//
//  SessionsListView.swift
//  V4MinimalApp
//
//  Lists all detection sessions for browsing and review
//

import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var sessionStore: DetectionSessionStore
    @State private var showDeleteAllConfirmation = false

    var sortedSessions: [DetectionSession] {
        sessionStore.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Group {
        if sortedSessions.isEmpty {
            VStack(spacing: AppTheme.Spacing.l) {
                Spacer()

                Image(systemName: "tray")
                    .font(.system(size: 60))
                    .foregroundStyle(.tertiary)

                Text("No Sessions Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start a live scan to create detection sessions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
        } else {
            List {
                ForEach(sortedSessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
                .onDelete { offsets in
                    let sessionsToDelete = offsets.map { sortedSessions[$0] }
                    for session in sessionsToDelete {
                        sessionStore.deleteSession(session.id)
                    }
                }
            }
            .listStyle(.plain)
        }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !sortedSessions.isEmpty {
                    Button {
                        showDeleteAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Delete All Sessions?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
        } message: {
            Text("This will permanently delete all \(sortedSessions.count) sessions and their photos. This cannot be undone.")
        }
        .debugScreenName("SessionsListView")
    }

    private func deleteAllSessions() {
        let allIds = sessionStore.sessions.map { $0.id }
        for id in allIds {
            sessionStore.deleteSession(id)
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: DetectionSession

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(session.isMerged ? Color.green.opacity(0.1) : AppTheme.Colors.primary.opacity(0.1))

                Image(systemName: session.isMerged ? "checkmark.circle.fill" : "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(session.isMerged ? .green : AppTheme.Colors.primary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(session.itemCount)", systemImage: "cube.box")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(session.displayDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.isMerged {
                    Text("Merged")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Text(session.startedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
