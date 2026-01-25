//
//  CameraManager+FrameCapture.swift
//  V4MinimalApp
//
//  Extension for capturing video frames for real-time analysis
//

import AVFoundation
import UIKit

extension CameraManager {
    
    /// Callback for streaming vision analysis
    nonisolated var onFrameCaptured: ((UIImage) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.onFrameCaptured) as? (UIImage) -> Void
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.onFrameCaptured, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Enable frame capture for streaming analysis
    func enableFrameCapture(handler: @escaping (UIImage) -> Void) {
        onFrameCaptured = handler
        
        // Video output should already be configured in setupCaptureSession
        // Just ensure we're getting frame callbacks
        print("✅ Frame capture enabled for streaming analysis")
    }
    
    /// Disable frame capture
    func disableFrameCapture() {
        onFrameCaptured = nil
        print("⏹️ Frame capture disabled")
    }
}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
    static var onFrameCaptured: UInt8 = 0
}
