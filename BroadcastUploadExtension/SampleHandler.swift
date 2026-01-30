import ReplayKit
import Network
import CoreImage
import UIKit
import os

class SampleHandler: RPBroadcastSampleHandler {

    private let logger = Logger(subsystem: "Test-Organization.V2NoScopesApp.BroadcastUpload", category: "Broadcast")

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "BroadcastStreamer", qos: .utility)
    private var isConnected = false

    private let minFrameInterval: TimeInterval = 0.5  // ~2 fps
    private var lastFrameTime: CFTimeInterval = 0
    private let compressionQuality: CGFloat = 0.4
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Hardcoded server address (App Group sharing requires portal registration;
    // update this IP to match your Mac's local network address)
    private let serverHost = "10.0.141.70"
    private let serverPort: UInt16 = 9998

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        logger.info("Broadcast started")
        setupConnection()
    }

    override func broadcastPaused() {
        logger.info("Broadcast paused")
    }

    override func broadcastResumed() {
        logger.info("Broadcast resumed")
        if !isConnected { setupConnection() }
    }

    override func broadcastFinished() {
        logger.info("Broadcast finished")
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        // Scale down to half resolution to stay within ~50MB memory limit
        let scale = min(1.0, 640.0 / Double(width))
        let scaledW = Int(Double(width) * scale)
        let scaledH = Int(Double(height) * scale)

        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return }

        let uiImage: UIImage
        if scale < 1.0 {
            UIGraphicsBeginImageContextWithOptions(CGSize(width: scaledW, height: scaledH), true, 1.0)
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: scaledW, height: scaledH))
            uiImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage(cgImage: cgImage)
            UIGraphicsEndImageContext()
        } else {
            uiImage = UIImage(cgImage: cgImage)
        }

        guard let jpegData = uiImage.jpegData(compressionQuality: compressionQuality) else { return }

        let timestamp = formatter.string(from: Date())

        queue.async { [weak self] in
            self?.sendFrame(imageData: jpegData, timestamp: timestamp)
        }
    }

    // MARK: - TCP

    private func setupConnection() {
        connection?.cancel()

        guard !serverHost.isEmpty else {
            logger.warning("No server host configured")
            return
        }

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
                self.logger.info("Connected to \(self.serverHost):\(self.serverPort)")
            case .failed(let error):
                self.isConnected = false
                self.logger.error("Connection failed: \(error.localizedDescription)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.setupConnection()
                }
            case .cancelled:
                self.isConnected = false
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    private func sendFrame(imageData: Data, timestamp: String) {
        guard isConnected, let connection = connection else {
            if self.connection == nil || self.connection?.state == .cancelled {
                setupConnection()
            }
            return
        }

        // Protocol (same as ScreenshotStreamer):
        // 8 bytes ts_len (big-endian UInt64) + timestamp + 8 bytes img_len + JPEG
        var packet = Data()

        let timestampData = timestamp.data(using: .utf8) ?? Data()
        var tsLen = UInt64(timestampData.count).bigEndian
        packet.append(Data(bytes: &tsLen, count: 8))
        packet.append(timestampData)

        var imgLen = UInt64(imageData.count).bigEndian
        packet.append(Data(bytes: &imgLen, count: 8))
        packet.append(imageData)

        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Send failed: \(error.localizedDescription)")
            }
        })
    }
}
