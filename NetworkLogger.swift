//
//  NetworkLogger.swift
//  V4MinimalApp
//
//  Streams logs to a Mac over TCP for debugging without Xcode.
//  Works alongside Apple's unified logging (os.Logger).
//

import Foundation
import Network
import os

/// Singleton logger that sends logs to a Mac over TCP
/// Reads server configuration from UserDefaults (set in NetworkDiagnosticsView)
class NetworkLogger {
    static let shared = NetworkLogger()

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "NetworkLogger", qos: .utility)
    private var isConnected = false
    private var pendingMessages: [String] = []
    private let maxPendingMessages = 100

    // Server settings from UserDefaults (set in NetworkDiagnosticsView)
    private var serverHost: String {
        UserDefaults.standard.string(forKey: "logServerHost") ?? "10.0.141.70"
    }
    private var serverPort: UInt16 {
        UInt16(UserDefaults.standard.string(forKey: "logServerPort") ?? "9999") ?? 9999
    }

    /// Enable/disable network logging
    var isEnabled: Bool = true

    private init() {
        // Auto-connect if settings exist
        if !serverHost.isEmpty {
            setupConnection()
        }
    }

    /// Manually trigger connection (e.g., after settings change)
    func connect() {
        guard !serverHost.isEmpty else {
            os_log("NetworkLogger: No server host configured", type: .info)
            return
        }
        setupConnection()
    }

    /// Disconnect from the server
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func setupConnection() {
        // Cancel existing connection
        connection?.cancel()

        let host = NWEndpoint.Host(serverHost)
        let port = NWEndpoint.Port(integerLiteral: serverPort)

        // TCP parameters
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 30

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        connection = NWConnection(host: host, port: port, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                self.isConnected = true
                os_log("NetworkLogger: Connected to %{public}@:%{public}d", type: .info, self.serverHost, self.serverPort)
                // Flush any pending messages
                self.flushPendingMessages()

            case .failed(let error):
                self.isConnected = false
                os_log("NetworkLogger: Connection failed - %{public}@", type: .error, error.localizedDescription)
                // Retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.setupConnection()
                }

            case .waiting(let error):
                os_log("NetworkLogger: Waiting - %{public}@", type: .debug, error.localizedDescription)

            case .cancelled:
                self.isConnected = false

            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    private func flushPendingMessages() {
        for message in pendingMessages {
            sendImmediate(message)
        }
        pendingMessages.removeAll()
    }

    /// Send a formatted log message
    func send(level: String, category: String, message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }

        // Format: [LEVEL] [Category] [file:line] message function
        let fileName = file.components(separatedBy: "/").last ?? file
        let logMessage = "[\(level.uppercased())] [\(category)] [\(fileName):\(line)] \(message) \(function)"

        if isConnected {
            sendImmediate(logMessage)
        } else {
            // Queue message for when we connect
            if pendingMessages.count < maxPendingMessages {
                pendingMessages.append(logMessage)
            }
            // Try to connect if not already
            if connection == nil || connection?.state == .cancelled {
                setupConnection()
            }
        }
    }

    private func sendImmediate(_ message: String) {
        guard let connection = connection, isConnected else { return }

        // Add newline for TCP stream parsing
        let data = (message + "\n").data(using: .utf8) ?? Data()

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                os_log("NetworkLogger: Send error - %{public}@", type: .error, error.localizedDescription)
            }
        })
    }

    // MARK: - Convenience logging methods

    func debug(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "DEBUG", category: category, message: message, file: file, function: function, line: line)
    }

    func info(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "INFO", category: category, message: message, file: file, function: function, line: line)
    }

    func notice(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "NOTICE", category: category, message: message, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "WARNING", category: category, message: message, file: file, function: function, line: line)
    }

    func error(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "ERROR", category: category, message: message, file: file, function: function, line: line)
    }

    func fault(_ message: String, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
        send(level: "FAULT", category: category, message: message, file: file, function: function, line: line)
    }
}

// MARK: - Global convenience functions

/// Log to both unified logging and network
func appLog(_ message: String, level: OSLogType = .info, category: String = "App", file: String = #fileID, function: String = #function, line: Int = #line) {
    // Unified logging
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "V4MinimalApp", category: category)

    switch level {
    case .debug:
        logger.debug("\(message, privacy: .public)")
        NetworkLogger.shared.debug(message, category: category, file: file, function: function, line: line)
    case .info:
        logger.info("\(message, privacy: .public)")
        NetworkLogger.shared.info(message, category: category, file: file, function: function, line: line)
    case .error:
        logger.error("\(message, privacy: .public)")
        NetworkLogger.shared.error(message, category: category, file: file, function: function, line: line)
    case .fault:
        logger.fault("\(message, privacy: .public)")
        NetworkLogger.shared.fault(message, category: category, file: file, function: function, line: line)
    default:
        logger.log("\(message, privacy: .public)")
        NetworkLogger.shared.info(message, category: category, file: file, function: function, line: line)
    }
}
