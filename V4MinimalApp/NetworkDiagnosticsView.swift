//
//  NetworkDiagnosticsView.swift
//  V4MinimalApp
//
//  Network connectivity testing for debug logging
//

import SwiftUI
import Network

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case idle
    case testing
    case success(latency: Int) // latency in ms
    case failed(String)

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .testing: return AppTheme.Colors.primary
        case .success: return AppTheme.Colors.success
        case .failed: return AppTheme.Colors.error
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle.dashed"
        case .testing: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .idle: return "Tap to test"
        case .testing: return "Testing..."
        case .success(let latency): return "Connected (\(latency)ms)"
        case .failed(let reason): return reason
        }
    }
}

// MARK: - Endpoint Model

struct Endpoint: Identifiable {
    let id = UUID()
    let name: String
    let host: String
    let port: UInt16
    let icon: String
    let description: String
    let fullName: String
    let path: String

    init(name: String, host: String, port: UInt16, icon: String, description: String, fullName: String = "", path: String = "/") {
        self.name = name
        self.host = host
        self.port = port
        self.icon = icon
        self.description = description
        self.fullName = fullName.isEmpty ? name : fullName
        self.path = path
    }
}

// MARK: - Network Diagnostics View

struct NetworkDiagnosticsView: View {
    @State private var logServerHost: String = ""
    @State private var logServerPort: String = "9999"
    @State private var screenshotServerPort: String = "9998"
    @State private var connectionStatuses: [UUID: ConnectionStatus] = [:]
    @State private var isTestingAll = false
    @State private var showingHelp = false
    @State private var debugServerLastTest: Date? = nil
    @State private var debugServerResult: String? = nil
    @State private var debugServerSuccess: Bool = false
    @State private var connectionLog: [String] = []
    @State private var isScreenshotStreaming: Bool = false
    @State private var screenshotInterval: Double = 2.0

    @State private var expandedEndpoints: Set<UUID> = []

    // Predefined endpoints
    let endpoints: [Endpoint] = [
        Endpoint(
            name: "Google",
            host: "google.com",
            port: 443,
            icon: "globe",
            description: "Internet connectivity",
            fullName: "Google HTTPS — basic connectivity check",
            path: "/"
        ),
        Endpoint(
            name: "Gemini Batch",
            host: "generativelanguage.googleapis.com",
            port: 443,
            icon: "brain",
            description: "Gemini REST API (detection)",
            fullName: "Google Gemini generateContent REST API (gemini-2.5-flash-lite)",
            path: "/v1beta/models/gemini-2.5-flash-lite:generateContent"
        ),
        Endpoint(
            name: "Gemini Live",
            host: "generativelanguage.googleapis.com",
            port: 443,
            icon: "waveform",
            description: "Gemini WebSocket (planned)",
            fullName: "Google Gemini BidiGenerateContent WebSocket (planned)",
            path: "/ws/google.ai.generativelanguage.v1beta.GenerativeService/BidiGenerateContent"
        ),
        Endpoint(
            name: "OpenAI Chat",
            host: "api.openai.com",
            port: 443,
            icon: "brain.head.profile",
            description: "Chat Completions REST API",
            fullName: "OpenAI Chat Completions v1 REST API (gpt-4o-mini)",
            path: "/v1/chat/completions"
        ),
        Endpoint(
            name: "OpenAI Realtime",
            host: "api.openai.com",
            port: 443,
            icon: "waveform.badge.mic",
            description: "Realtime Audio WebSocket",
            fullName: "OpenAI Realtime v1 WebSocket API (gpt-4o-realtime-preview)",
            path: "/v1/realtime?model=gpt-4o-realtime-preview"
        )
    ]

    var logServerEndpoint: Endpoint {
        Endpoint(
            name: "Debug Server",
            host: logServerHost.isEmpty ? "Not configured" : logServerHost,
            port: UInt16(logServerPort) ?? 9999,
            icon: "server.rack",
            description: "Mac log receiver (TCP)"
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Header Card
                headerCard

                // Log Server Configuration
                serverConfigCard

                // Screenshot Streaming
                screenshotStreamingCard

                // Endpoint Tests
                endpointTestsCard

                // Test All Button
                testAllButton
            }
            .padding(AppTheme.Spacing.l)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            helpSheet
        }
        .onAppear {
            loadSavedSettings()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "network")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.Colors.primary)
            }

            Text("Network Diagnostics")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Test connectivity to services used by the app")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xl)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    // MARK: - Server Config Card

    private var serverConfigCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            Label("Debug Server", systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.primary)

            Text("Enter your Mac's IP address (shown when you run log_server.py)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host / IP Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("e.g. 10.0.141.70", text: $logServerHost)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: logServerHost) { _ in
                            saveSettings()
                            // Reset status when host changes
                            connectionStatuses[logServerEndpoint.id] = .idle
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("9999", text: $logServerPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .onChange(of: logServerPort) { _ in saveSettings() }
                }
            }

            // Test button for log server
            Button {
                if !logServerHost.isEmpty {
                    testDebugServer()
                }
            } label: {
                HStack {
                    let status = connectionStatuses[logServerEndpoint.id] ?? .idle

                    if status == .testing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: status.icon)
                            .foregroundStyle(status.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(logServerHost.isEmpty ? "Enter IP address above" : "Test Connection")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(status.label)
                            .font(.caption)
                            .foregroundStyle(status.color)
                    }

                    Spacer()

                    if !logServerHost.isEmpty && status != .testing {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.Colors.primary)
                    }
                }
                .padding(AppTheme.Spacing.m)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(logServerHost.isEmpty)
            .opacity(logServerHost.isEmpty ? 0.6 : 1)

            // Inline status display
            if let lastTest = debugServerLastTest {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Last tested:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastTest.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    if let result = debugServerResult {
                        HStack {
                            Image(systemName: debugServerSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(debugServerSuccess ? AppTheme.Colors.success : AppTheme.Colors.error)
                                .font(.caption)

                            Text(result)
                                .font(.caption)
                                .foregroundStyle(debugServerSuccess ? AppTheme.Colors.success : AppTheme.Colors.error)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.s)
            }

            // Connection log (TCP details)
            if !connectionLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Connection Log", systemImage: "text.alignleft")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            connectionLog.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(connectionLog, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(logColor(for: log))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .padding(AppTheme.Spacing.s)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }
        }
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    // MARK: - Screenshot Streaming Card

    private var screenshotStreamingCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            Label("Screenshot Streaming", systemImage: "camera.viewfinder")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.primary)

            Text("Stream screenshots to Mac for visual debugging (correlated with logs)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Port configuration
            HStack {
                Text("Screenshot Port")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("9998", text: $screenshotServerPort)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .onChange(of: screenshotServerPort) { _ in
                        UserDefaults.standard.set(screenshotServerPort, forKey: "screenshotServerPort")
                    }
            }

            // Interval slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Capture Interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(String(format: "%.1f", screenshotInterval))s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.Colors.primary)
                }

                Slider(value: $screenshotInterval, in: 0.5...5.0, step: 0.5)
                    .tint(AppTheme.Colors.primary)
                    .onChange(of: screenshotInterval) { newValue in
                        ScreenshotStreamer.shared.captureInterval = newValue
                    }
            }

            // Toggle button
            Button {
                toggleScreenshotStreaming()
            } label: {
                HStack {
                    Image(systemName: isScreenshotStreaming ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isScreenshotStreaming ? AppTheme.Colors.error : AppTheme.Colors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isScreenshotStreaming ? "Stop Streaming" : "Start Streaming")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(isScreenshotStreaming ? "Screenshots being sent to Mac" : "Tap to begin capturing screenshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isScreenshotStreaming {
                        Circle()
                            .fill(AppTheme.Colors.error)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.Colors.error.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(1.5)
                            )
                    }
                }
                .padding(AppTheme.Spacing.m)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(logServerHost.isEmpty)
            .opacity(logServerHost.isEmpty ? 0.6 : 1)

            if logServerHost.isEmpty {
                Text("Configure server host above to enable streaming")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
        .onAppear {
            screenshotServerPort = UserDefaults.standard.string(forKey: "screenshotServerPort") ?? "9998"
            isScreenshotStreaming = ScreenshotStreamer.shared.isActive
        }
    }

    private func toggleScreenshotStreaming() {
        if isScreenshotStreaming {
            ScreenshotStreamer.shared.stopStreaming()
            isScreenshotStreaming = false
        } else {
            ScreenshotStreamer.shared.captureInterval = screenshotInterval
            ScreenshotStreamer.shared.startStreaming()
            isScreenshotStreaming = true
        }
    }

    // MARK: - Endpoint Tests Card

    private var endpointTestsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            Label("Service Connectivity", systemImage: "checkmark.shield")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.primary)

            ForEach(endpoints) { endpoint in
                endpointRow(endpoint)
            }
        }
        .padding(AppTheme.Spacing.l)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    private func endpointRow(_ endpoint: Endpoint) -> some View {
        let isExpanded = expandedEndpoints.contains(endpoint.id)
        let status = connectionStatuses[endpoint.id] ?? .idle

        return VStack(spacing: 0) {
            // Main row
            HStack(spacing: AppTheme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if status == .testing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: endpoint.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(status.color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(endpoint.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: status.icon)
                        .foregroundStyle(status.color)

                    Text(status.label)
                        .font(.caption2)
                        .foregroundStyle(status.color)
                }

                // Expand chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.m)
            .contentShape(Rectangle())
            .onTapGesture {
                testEndpoint(endpoint)
            }
            .onLongPressGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedEndpoints.remove(endpoint.id)
                    } else {
                        expandedEndpoints.insert(endpoint.id)
                    }
                }
            }

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.horizontal, 4)

                    HStack(spacing: 6) {
                        Text("DNS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        Text(endpoint.host)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 6) {
                        Text("Port")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        Text("\(endpoint.port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Text("Path")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        Text(endpoint.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Text("API")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        Text(endpoint.fullName)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.bottom, AppTheme.Spacing.s)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - Test All Button

    private var testAllButton: some View {
        Button {
            testAllEndpoints()
        } label: {
            HStack {
                if isTestingAll {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "play.fill")
                }

                Text(isTestingAll ? "Testing..." : "Test All Connections")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.l)
            .background(isTestingAll ? Color.gray : AppTheme.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(AppTheme.cornerRadius)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isTestingAll)
    }

    // MARK: - Help Sheet

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    helpSection(
                        icon: "server.rack",
                        title: "Debug Server Setup",
                        content: """
                        1. On your Mac, open Terminal
                        2. Navigate to the project:
                           cd tools/log-server
                        3. Start the server:
                           python3 log_server.py
                        4. Note the IP address shown
                        5. Enter that IP here
                        """
                    )

                    helpSection(
                        icon: "wifi",
                        title: "Connection Requirements",
                        content: """
                        • iPhone and Mac must be on the same WiFi network
                        • Mac firewall must allow incoming connections on port 9999
                        • Use your Mac's local IP (shown by server, usually 10.x.x.x or 192.168.x.x)
                        """
                    )

                    helpSection(
                        icon: "exclamationmark.triangle",
                        title: "Troubleshooting",
                        content: """
                        • Verify Mac IP: Run 'ipconfig getifaddr en0' in Terminal
                        • Check firewall: System Settings → Network → Firewall
                        • Try temporarily disabling firewall to test
                        • Ensure not on guest/isolated WiFi network
                        """
                    )
                }
                .padding(AppTheme.Spacing.l)
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingHelp = false
                    }
                }
            }
        }
    }

    private func helpSection(icon: String, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.primary)

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppTheme.cornerRadius)
    }

    // MARK: - Network Testing

    private func addLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        connectionLog.append("[\(timestamp)] \(message)")
        // Keep only last 20 entries
        if connectionLog.count > 20 {
            connectionLog.removeFirst()
        }
    }

    private func logColor(for log: String) -> Color {
        if log.contains("READY") || log.contains("success") || log.contains("complete") {
            return AppTheme.Colors.success
        } else if log.contains("FAILED") || log.contains("TIMEOUT") || log.contains("error") {
            return AppTheme.Colors.error
        } else if log.contains("WAITING") || log.contains("→") {
            return .orange
        } else if log.contains("PREPARING") || log.contains("SYN") {
            return AppTheme.Colors.primary
        }
        return .secondary
    }

    private func testDebugServer() {
        let endpoint = logServerEndpoint
        connectionStatuses[endpoint.id] = .testing
        debugServerLastTest = Date()
        debugServerResult = nil
        connectionLog.removeAll()

        addLog("Starting TCP connection to \(endpoint.host):\(endpoint.port)")

        // TCP test - establish connection and send a test message
        let host = NWEndpoint.Host(endpoint.host)
        let port = NWEndpoint.Port(integerLiteral: endpoint.port)

        // Create TCP parameters with options
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let connection = NWConnection(host: host, port: port, using: params)

        let startTime = Date()

        // Monitor path updates for network info
        connection.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                var pathInfo = "Path: "
                if path.usesInterfaceType(.wifi) {
                    pathInfo += "WiFi"
                } else if path.usesInterfaceType(.cellular) {
                    pathInfo += "Cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    pathInfo += "Ethernet"
                } else {
                    pathInfo += "Unknown"
                }
                if path.isExpensive { pathInfo += ", Expensive" }
                if path.isConstrained { pathInfo += ", Constrained" }
                addLog(pathInfo)

                // Log available interfaces
                if let localEndpoint = path.localEndpoint {
                    addLog("Local endpoint: \(localEndpoint)")
                }
            }
        }

        // Monitor better queue for state changes
        connection.betterPathUpdateHandler = { hasBetterPath in
            if hasBetterPath {
                DispatchQueue.main.async {
                    addLog("Better path available")
                }
            }
        }

        connection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

                switch state {
                case .setup:
                    addLog("[\(elapsed)ms] State: SETUP (initializing)")

                case .preparing:
                    addLog("[\(elapsed)ms] State: PREPARING (DNS + TCP SYN sent)")

                case .ready:
                    addLog("[\(elapsed)ms] State: READY (TCP handshake complete!)")
                    addLog("  → SYN-ACK received, connection established")

                    // Get connection metadata
                    if let metadata = connection.metadata(definition: NWProtocolTCP.definition) as? NWProtocolTCP.Metadata {
                        addLog("  → Local port: \(metadata.availableReceiveBuffer)")
                    }

                    // TCP connected! Send a test message
                    let testMessage = "[INFO] [NetworkTest] Connection test from iPhone\n"
                    addLog("Sending test message...")

                    connection.send(content: testMessage.data(using: .utf8), completion: .contentProcessed { error in
                        DispatchQueue.main.async {
                            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                            if let error = error {
                                addLog("[\(latency)ms] SEND FAILED: \(error.localizedDescription)")
                                connectionStatuses[endpoint.id] = .failed("Send failed")
                                debugServerResult = "Send failed: \(error.localizedDescription)"
                                debugServerSuccess = false
                            } else {
                                addLog("[\(latency)ms] Message sent successfully")
                                addLog("[\(latency)ms] State: FIN (closing)")
                                connectionStatuses[endpoint.id] = .success(latency: latency)
                                debugServerResult = "Connected successfully (\(latency)ms)"
                                debugServerSuccess = true
                            }
                            connection.cancel()
                        }
                    })

                case .waiting(let error):
                    addLog("[\(elapsed)ms] State: WAITING - \(error.localizedDescription)")
                    addLog("  → Possible causes: No route, firewall blocking SYN")

                    // Give it a moment, then timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if case .testing = connectionStatuses[endpoint.id] {
                            addLog("[\(elapsed + 3000)ms] TIMEOUT in WAITING state")
                            connectionStatuses[endpoint.id] = .failed("Timeout")
                            debugServerResult = "Timeout - no SYN-ACK received"
                            debugServerSuccess = false
                            connection.cancel()
                        }
                    }

                case .failed(let error):
                    addLog("[\(elapsed)ms] State: FAILED - \(error.localizedDescription)")

                    // Parse specific errors
                    if let posixError = error as? NWError, case .posix(let code) = posixError {
                        switch code {
                        case .ECONNREFUSED:
                            addLog("  → RST received (port closed or refused)")
                        case .ETIMEDOUT:
                            addLog("  → No response (SYN sent, no SYN-ACK)")
                        case .EHOSTUNREACH:
                            addLog("  → Host unreachable (no route)")
                        case .ENETUNREACH:
                            addLog("  → Network unreachable")
                        default:
                            addLog("  → POSIX error: \(code)")
                        }
                    }

                    connectionStatuses[endpoint.id] = .failed("Connection failed")
                    debugServerResult = "Failed: \(error.localizedDescription)"
                    debugServerSuccess = false
                    connection.cancel()

                case .cancelled:
                    addLog("Connection closed")

                @unknown default:
                    addLog("[\(elapsed)ms] Unknown state")
                }
            }
        }

        addLog("Calling connection.start() - sending SYN...")
        connection.start(queue: .global())

        // Overall timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if case .testing = connectionStatuses[endpoint.id] {
                addLog("[5000ms] OVERALL TIMEOUT")
                connectionStatuses[endpoint.id] = .failed("Timeout")
                debugServerResult = "Timeout - server not responding"
                debugServerSuccess = false
                connection.cancel()
            }
        }
    }

    private func testEndpoint(_ endpoint: Endpoint) {
        connectionStatuses[endpoint.id] = .testing

        let startTime = Date()

        // Use NWConnection for TCP connectivity test
        let host = NWEndpoint.Host(endpoint.host)
        let port = NWEndpoint.Port(integerLiteral: endpoint.port)
        let connection = NWConnection(host: host, port: port, using: .tcp)

        connection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                    connectionStatuses[endpoint.id] = .success(latency: latency)
                    connection.cancel()

                case .failed(let error):
                    connectionStatuses[endpoint.id] = .failed(error.localizedDescription)
                    connection.cancel()

                case .waiting(_):
                    // Timeout after 5 seconds of waiting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if case .testing = connectionStatuses[endpoint.id] {
                            connectionStatuses[endpoint.id] = .failed("Timeout")
                            connection.cancel()
                        }
                    }

                default:
                    break
                }
            }
        }

        connection.start(queue: .global())

        // Overall timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if case .testing = connectionStatuses[endpoint.id] {
                connectionStatuses[endpoint.id] = .failed("Timeout")
                connection.cancel()
            }
        }
    }

    private func testAllEndpoints() {
        isTestingAll = true

        // Test all endpoints including log server if configured
        for endpoint in endpoints {
            testEndpoint(endpoint)
        }

        if !logServerHost.isEmpty {
            testDebugServer()
        }

        // Reset flag after tests complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            isTestingAll = false
        }
    }

    // MARK: - Settings Persistence

    private func loadSavedSettings() {
        logServerHost = UserDefaults.standard.string(forKey: "logServerHost") ?? "10.0.141.70"
        logServerPort = UserDefaults.standard.string(forKey: "logServerPort") ?? "9999"
    }

    private func saveSettings() {
        UserDefaults.standard.set(logServerHost, forKey: "logServerHost")
        UserDefaults.standard.set(logServerPort, forKey: "logServerPort")
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NetworkDiagnosticsView()
    }
}
