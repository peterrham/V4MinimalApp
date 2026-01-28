//
//  StreamingObjectDetectionView.swift
//  V4MinimalApp
//
//  Scrolling display of real-time detected objects
//

import SwiftUI

struct StreamingObjectDetectionView: View {
    let detectedObjects: [DetectedObject]
    let isAnalyzing: Bool
    var onSaveItem: ((DetectedObject) -> Void)? = nil
    var onSaveAll: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: isAnalyzing ? "eye.fill" : "eye.slash.fill")
                    .font(.callout)
                    .foregroundColor(isAnalyzing ? .green : .gray)
                    .symbolEffect(.pulse, isActive: isAnalyzing)

                Text(isAnalyzing ? "Live Detection" : "Detection Paused")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                if let onSaveAll = onSaveAll, !detectedObjects.isEmpty {
                    Button {
                        onSaveAll()
                    } label: {
                        Text("Save All")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.6))
                            )
                    }
                }

                Text("\(detectedObjects.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isAnalyzing ? Color.green.opacity(0.3) : Color.gray.opacity(0.3))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
            )
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Scrolling list of detected objects
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if detectedObjects.isEmpty {
                            // Empty state
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.top, 20)
                                
                                Text(isAnalyzing ? "Scanning for objects..." : "Start analyzing to detect objects")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.bottom, 20)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            // Show detected objects
                            ForEach(detectedObjects.reversed()) { object in
                                ObjectDetectionRow(object: object) {
                                    onSaveItem?(object)
                                }
                                .id(object.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .onChange(of: detectedObjects.count) { oldValue, newValue in
                    // Auto-scroll to newest detection
                    if let newest = detectedObjects.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(newest.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(0.95)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Object Detection Row

struct ObjectDetectionRow: View {
    let object: DetectedObject
    var onSave: (() -> Void)? = nil
    @State private var appeared = false
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            // Indicator dot — orange if bounding boxes loaded
            Circle()
                .fill(object.boundingBoxes != nil ? .orange : (saved ? .blue : .green))
                .frame(width: 6, height: 6)

            // Object name and details
            VStack(alignment: .leading, spacing: 1) {
                Text(object.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                let details = [object.brand, object.color, object.size]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Save button
            if let onSave = onSave {
                Button {
                    onSave()
                    withAnimation {
                        saved = true
                    }
                } label: {
                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(saved ? .blue : .green)
                }
                .disabled(saved)
            }

            // Live timestamp
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeAgo(from: object.timestamp, now: context.date))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(appeared ? 0.15 : 0.05))
        )
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
    
    private func timeAgo(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))

        if seconds < 5 {
            return "now"
        } else if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            StreamingObjectDetectionView(
                detectedObjects: [
                    DetectedObject(name: "Coffee mug", timestamp: Date().addingTimeInterval(-10)),
                    DetectedObject(name: "Laptop computer", timestamp: Date().addingTimeInterval(-8)),
                    DetectedObject(name: "Wireless mouse", timestamp: Date().addingTimeInterval(-5)),
                    DetectedObject(name: "Desk lamp", timestamp: Date().addingTimeInterval(-2)),
                    DetectedObject(name: "Notebook", timestamp: Date())
                ],
                isAnalyzing: true
            )
            .padding()
            
            Spacer()
        }
    }
}
