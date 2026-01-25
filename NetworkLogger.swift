//
//  NetworkLogger.swift
//  V4MinimalApp
//
//  Streams logs to a Mac over UDP for debugging without Xcode
//

import Foundation
import Network

/// Singleton logger that sends logs to a Mac over UDP
class NetworkLogger {
    static let shared = NetworkLogger()

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "NetworkLogger")
    private var isConnected = false

    // Default to common Mac hostname - will be auto-discovered
    private var serverHost: String = ""
    private let serverPort: UInt16 = 9999

    private init() {
        // Auto-discover server on local network
        discoverServer()
    }

    /// Manually set the server address (e.g., "192.168.1.100" or "MyMac.local")
    func setServer(host: String, port: UInt16 = 9999) {
        serverHost = host
        setupConnection()
    }

    /// Discover the server by trying common local addresses
    private func discoverServer() {
        // Try to get the gateway/router IP and guess the Mac is on the same subnet
        // For now, we'll use broadcast or a known hostname

        // First, try the .local hostname approach
        if let computerName = Host.current().localizedName {
            let macHostname = computerName.replacingOccurrences(of: " ", with: "-") + ".local"
            serverHost = macHostname
            setupConnection()
            return
        }

        // Fallback: Use broadcast address (works for UDP)
        serverHost = "255.255.255.255"
        setupConnection()
    }

    private func setupConnection() {
        guard !serverHost.isEmpty else { return }

        let host = NWEndpoint.Host(serverHost)
        let port = NWEndpoint.Port(integerLiteral: serverPort)

        connection = NWConnection(host: host, port: port, using: .udp)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.log("📱 NetworkLogger connected to \(self?.serverHost ?? "unknown"):\(self?.serverPort ?? 0)")
            case .failed(let error):
                self?.isConnected = false
                print("NetworkLogger connection failed: \(error)")
            case .cancelled:
                self?.isConnected = false
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    /// Log a message to the network server
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(message)"

        // Also print locally
        print(logMessage)

        // Send over network
        send(logMessage)
    }

    /// Log with a category tag
    func log(_ message: String, category: String) {
        let logMessage = "[\(category)] \(message)"
        print(logMessage)
        send(logMessage)
    }

    /// Raw send without local print
    func send(_ message: String) {
        guard let connection = connection, isConnected || connection.state == .ready else {
            // Try to reconnect if not connected
            if connection == nil {
                setupConnection()
            }
            return
        }

        let data = message.data(using: .utf8) ?? Data()

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("NetworkLogger send error: \(error)")
            }
        })
    }

    /// Convenience methods
    func info(_ message: String) {
        log("ℹ️ \(message)", category: "INFO")
    }

    func debug(_ message: String) {
        log("🔍 \(message)", category: "DEBUG")
    }

    func error(_ message: String) {
        log("❌ \(message)", category: "ERROR")
    }

    func success(_ message: String) {
        log("✅ \(message)", category: "SUCCESS")
    }

    func warning(_ message: String) {
        log("⚠️ \(message)", category: "WARNING")
    }
}

// MARK: - Global convenience function

/// Global logging function - sends to both console and network
func netLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    NetworkLogger.shared.log(message, file: file, function: function, line: line)
}
