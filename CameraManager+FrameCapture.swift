//
//  CameraManager+FrameCapture.swift
//  V4MinimalApp
//
//  Extension for capturing video frames for real-time analysis
//

import AVFoundation
import UIKit

extension CameraManager {

    /// Callback for streaming vision analysis (UIImage)
    nonisolated var onFrameCaptured: ((UIImage) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.onFrameCaptured) as? (UIImage) -> Void
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.onFrameCaptured, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Callback for raw pixel buffer access (YOLO / Vision framework)
    nonisolated var onPixelBufferCaptured: ((CVPixelBuffer) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.onPixelBufferCaptured) as? (CVPixelBuffer) -> Void
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.onPixelBufferCaptured, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Enable frame capture for streaming analysis
    func enableFrameCapture(handler: @escaping (UIImage) -> Void) {
        onFrameCaptured = handler

        // Video output should already be configured in setupCaptureSession
        // Just ensure we're getting frame callbacks
        print("✅ Frame capture enabled for streaming analysis")
    }

    /// Enable raw pixel buffer capture for on-device ML (YOLO)
    func enablePixelBufferCapture(handler: @escaping (CVPixelBuffer) -> Void) {
        onPixelBufferCaptured = handler
        print("✅ Pixel buffer capture enabled for YOLO")
    }

    /// Disable frame capture
    func disableFrameCapture() {
        onFrameCaptured = nil
        onPixelBufferCaptured = nil
        print("⏹️ Frame capture disabled")
    }
}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
    static var onFrameCaptured: UInt8 = 0
    static var onPixelBufferCaptured: UInt8 = 1
}
