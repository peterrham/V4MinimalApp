//
//  ScreenshotStreamer.swift
//  V4MinimalApp
//
//  Captures screenshots periodically and streams them to the Mac for debugging.
//  Works alongside the log server for correlated visual + log debugging.
//

import Foundation
import UIKit
import Network
import os

/// Singleton that captures and streams screenshots to the Mac
class ScreenshotStreamer {
    static let shared = ScreenshotStreamer()

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "ScreenshotStreamer", qos: .utility)
    private var isConnected = false
    private var captureTimer: Timer?
    private var isStreaming = false

    /// Screenshot capture interval in seconds
    var captureInterval: TimeInterval = 2.0

    /// JPEG compression quality (0.0 - 1.0)
    var compressionQuality: CGFloat = 0.5

    /// Server settings from UserDefaults
    private var serverHost: String {
        UserDefaults.standard.string(forKey: "logServerHost") ?? ""
    }
    private var serverPort: UInt16 {
        UInt16(UserDefaults.standard.string(forKey: "screenshotServerPort") ?? "9998") ?? 9998
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "V4MinimalApp", category: "Screenshot")

    private init() {}

    /// Start streaming screenshots
    func startStreaming() {
        guard !isStreaming else {
            logger.info("Screenshot streaming already active")
            return
        }

        guard !serverHost.isEmpty else {
            logger.warning("No server host configured for screenshots")
            return
        }

        isStreaming = true
        setupConnection()

        // Start capture timer on main thread (needs access to UI)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.captureTimer = Timer.scheduledTimer(withTimeInterval: self.captureInterval, repeats: true) { [weak self] _ in
                self?.captureAndSend()
            }
            // Capture immediately
            self.captureAndSend()
        }

        logger.info("Screenshot streaming started (interval: \(self.captureInterval)s)")
        NetworkLogger.shared.info("Screenshot streaming started (interval: \(self.captureInterval)s)", category: "Screenshot")
    }

    /// Stop streaming screenshots
    func stopStreaming() {
        isStreaming = false

        DispatchQueue.main.async { [weak self] in
            self?.captureTimer?.invalidate()
            self?.captureTimer = nil
        }

        connection?.cancel()
        connection = nil
        isConnected = false

        logger.info("Screenshot streaming stopped")
        NetworkLogger.shared.info("Screenshot streaming stopped", category: "Screenshot")
    }

    /// Check if streaming is active
    var isActive: Bool {
        return isStreaming
    }

    private func setupConnection() {
        connection?.cancel()

        let host = NWEndpoint.Host(serverHost)
        let port = NWEndpoint.Port(integerLiteral: serverPort)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        connection = NWConnection(host: host, port: port, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                self.isConnected = true
                self.logger.info("Screenshot connection ready to \(self.serverHost):\(self.serverPort)")

            case .failed(let error):
                self.isConnected = false
                self.logger.error("Screenshot connection failed: \(error.localizedDescription)")
                // Retry if still streaming
                if self.isStreaming {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.setupConnection()
                    }
                }

            case .cancelled:
                self.isConnected = false

            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    private func captureAndSend() {
        guard isStreaming else { return }

        // Must be called on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.captureAndSend()
            }
            return
        }

        // Find the key window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            logger.warning("Could not find key window for screenshot")
            return
        }

        // Capture the screenshot
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        // Compress to JPEG
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            logger.error("Failed to compress screenshot to JPEG")
            return
        }

        // Get timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())

        // Send on background queue
        queue.async { [weak self] in
            self?.sendScreenshot(imageData: imageData, timestamp: timestamp)
        }
    }

    private func sendScreenshot(imageData: Data, timestamp: String) {
        guard isConnected, let connection = connection else {
            // Try to reconnect if not connected
            if isStreaming && (self.connection == nil || self.connection?.state == .cancelled) {
                setupConnection()
            }
            return
        }

        // Protocol:
        // 1. 8 bytes: timestamp length (big-endian UInt64)
        // 2. N bytes: timestamp string (UTF-8)
        // 3. 8 bytes: image size (big-endian UInt64)
        // 4. M bytes: image data (JPEG)

        var packet = Data()

        // Timestamp
        let timestampData = timestamp.data(using: .utf8) ?? Data()
        var tsLen = UInt64(timestampData.count).bigEndian
        packet.append(Data(bytes: &tsLen, count: 8))
        packet.append(timestampData)

        // Image
        var imgLen = UInt64(imageData.count).bigEndian
        packet.append(Data(bytes: &imgLen, count: 8))
        packet.append(imageData)

        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send screenshot: \(error.localizedDescription)")
            } else {
                let sizeKB = Double(imageData.count) / 1024.0
                self?.logger.debug("Screenshot sent: \(String(format: "%.1f", sizeKB)) KB")
            }
        })
    }
}
