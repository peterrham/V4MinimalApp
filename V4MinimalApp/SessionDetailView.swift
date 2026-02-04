//
//  SessionDetailView.swift
//  V4MinimalApp
//
//  Detail view for reviewing a detection session and merging into inventory
//

import SwiftUI

struct SessionDetailView: View {
    let session: DetectionSession
    @EnvironmentObject var sessionStore: DetectionSessionStore
    @EnvironmentObject var inventoryStore: InventoryStore
    @State private var showMergeAlert = false
    @State private var selectedItem: SessionItem?

    /// Live session data from the store (reflects merge state changes)
    private var liveSession: DetectionSession? {
        sessionStore.sessions.first { $0.id == session.id }
    }

    private var isMerged: Bool {
        liveSession?.isMerged ?? session.isMerged
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.l) {
                // Header card
                VStack(spacing: AppTheme.Spacing.m) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.title3)
                                .fontWeight(.bold)

                            Text(session.startedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isMerged {
                            Label("Merged", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.1))
                                )
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.xl) {
                        StatBadge(value: "\(session.itemCount)", label: "Items")
                        StatBadge(value: session.displayDuration, label: "Duration")
                    }
                }
                .padding(AppTheme.Spacing.l)
                .background(AppTheme.Colors.surface)
                .cornerRadius(AppTheme.cornerRadius)

                // Items grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.m),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.m)
                ], spacing: AppTheme.Spacing.m) {
                    ForEach(session.items) { item in
                        SessionItemCard(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }
            }
            .padding(AppTheme.Spacing.l)
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMerged {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMergeAlert = true
                    } label: {
                        Label("Merge All", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("Merge Session", isPresented: $showMergeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Merge \(session.itemCount) Items") {
                sessionStore.mergeSession(session.id, into: inventoryStore)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } message: {
            Text("Add all \(session.itemCount) items from this session to your inventory? Duplicates will be merged automatically.")
        }
        .fullScreenCover(item: $selectedItem) { item in
            SessionFrameViewer(item: item, allItems: session.items)
                .environmentObject(sessionStore)
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.Colors.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Item Card

struct SessionItemCard: View {
    let item: SessionItem
    @EnvironmentObject var sessionStore: DetectionSessionStore

    /// Load the full frame and crop to bounding box if available
    private var displayImage: UIImage? {
        guard let filename = item.photoFilename,
              let fullImage = UIImage(contentsOfFile: sessionStore.photoURL(for: filename).path) else {
            return nil
        }
        return DetectionSessionStore.cropImage(fullImage, to: item.boundingBox)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo — cropped from full frame via bounding box
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 120)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                let details = [item.brand, item.color, item.size].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Full Frame Viewer

/// Fullscreen viewer showing the full source frame with bounding box overlays.
/// Starts zoomed to the tapped item's box; pinch/zoom out to see the full frame.
struct SessionFrameViewer: View {
    let item: SessionItem
    let allItems: [SessionItem]
    @EnvironmentObject var sessionStore: DetectionSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingBoxes = true

    /// All items that share the same source frame
    private var frameItems: [SessionItem] {
        guard let filename = item.photoFilename else { return [] }
        return allItems.filter { $0.photoFilename == filename }
    }

    private var fullImage: UIImage? {
        guard let filename = item.photoFilename else { return nil }
        return UIImage(contentsOfFile: sessionStore.photoURL(for: filename).path)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let uiImage = fullImage {
                GeometryReader { geo in
                    let imageSize = uiImage.size
                    let fitScale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                    let displayW = imageSize.width * fitScale
                    let displayH = imageSize.height * fitScale

                    ZStack {
                        // Full frame image
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)

                        // Bounding box overlays — each element independently positioned
                        // to avoid ZStack sizing issues from labels wider than boxes
                        if showingBoxes {
                            ForEach(frameItems) { frameItem in
                                if let box = frameItem.boundingBox {
                                    let boxColor: Color = frameItem.id == item.id ? .yellow : .green
                                    let lineW: CGFloat = frameItem.id == item.id ? 3 : 2
                                    let x = CGFloat(box.xMin) * displayW
                                    let y = CGFloat(box.yMin) * displayH
                                    let w = CGFloat(box.xMax - box.xMin) * displayW
                                    let h = CGFloat(box.yMax - box.yMin) * displayH

                                    // Box rectangle
                                    Rectangle()
                                        .stroke(boxColor, lineWidth: lineW)
                                        .frame(width: w, height: h)
                                        .position(x: x + w / 2, y: y + h / 2)

                                    // Label above box
                                    Text(frameItem.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(boxColor.opacity(0.85))
                                        .cornerRadius(3)
                                        .fixedSize()
                                        .position(x: x + w / 2, y: max(10, y - 12))
                                }
                            }
                        }
                    }
                    .frame(width: displayW, height: displayH)
                    .scaleEffect(scale)
                    .offset(offset)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 0.5 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                // Zoom out to fit
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                // Zoom in to 3x
                                scale = 3.0
                                lastScale = 3.0
                            }
                        }
                    }
                }
            }

            // Controls overlay
            VStack {
                HStack {
                    // Toggle boxes
                    Button {
                        withAnimation { showingBoxes.toggle() }
                    } label: {
                        Image(systemName: showingBoxes ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }

                    Spacer()

                    // Item name
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)

                    Spacer()

                    // Close
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}
