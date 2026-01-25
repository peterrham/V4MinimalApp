//
//  VideoSavedToast.swift
//  V4MinimalApp
//
//  Toast notification when video is saved to Photos
//

import SwiftUI

struct VideoSavedToast: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            if isShowing {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video Saved")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .padding(.horizontal)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowing)
            }
        }
    }
}

// MARK: - View Modifier

struct VideoSavedToastModifier: ViewModifier {
    @State private var isShowingToast = false
    @State private var toastMessage = ""
    
    func body(content: Content) -> some View {
        content
            .overlay(
                VideoSavedToast(message: toastMessage, isShowing: $isShowingToast)
            )
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VideoSavedToPhotos"))) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    showToast(message: "Saved to Photos Library")
                }
            }
    }
    
    private func showToast(message: String) {
        toastMessage = message
        withAnimation {
            isShowingToast = true
        }
        
        // Auto-dismiss after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                isShowingToast = false
            }
        }
    }
}

extension View {
    func videoSavedToast() -> some View {
        modifier(VideoSavedToastModifier())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VideoSavedToast(
            message: "Saved to Photos Library",
            isShowing: .constant(true)
        )
    }
}
