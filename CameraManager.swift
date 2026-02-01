//
//  CameraManager.swift
//  V4MinimalApp
//
//  Camera Management with AVFoundation
//

import AVFoundation
import SwiftUI
import UIKit
import Photos

@MainActor
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isAuthorized = false
    @Published var isCameraUnavailable = false
    @Published var error: CameraError?
    @Published var isSessionRunning = false
    
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var photoOutput = AVCapturePhotoOutput()
    var movieOutput = AVCaptureMovieFileOutput()
    
    private var deviceInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false

    // Cached CIContext — creating per-frame is expensive
    // nonisolated(unsafe) because captureOutput is called from a non-main queue
    nonisolated(unsafe) private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Flash control
    @Published var isFlashOn = false
    
    // Video recording
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    var recordingTimer: Timer?
    var recordingStartTime: Date?
    var currentVideoURL: URL?
    
    // Photo identification
    @Published var lastCapturedImage: UIImage?
    @Published var photoIdentification: String = ""
    @Published var isIdentifyingPhoto = false
    
    override init() {
        super.init()
        Task {
            await checkAuthorization()
        }
    }
    
    deinit {
        recordingTimer?.invalidate()
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            await setupCaptureSession()
        case .notDetermined:
            // Request permission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                isAuthorized = true
                await setupCaptureSession()
            } else {
                isAuthorized = false
            }
        case .denied, .restricted:
            isAuthorized = false
            error = .permissionDenied
        @unknown default:
            isAuthorized = false
        }
    }
    
    // MARK: - Camera Setup
    
    private func setupCaptureSession() async {
        guard !isSessionConfigured else { 
            appBootLog.debugWithContext("Session already configured")
            return 
        }
        
        appBootLog.infoWithContext("Setting up camera session...")
        
        // Setup video input
        do {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                appBootLog.errorWithContext("No camera device found")
                await MainActor.run {
                    isCameraUnavailable = true
                }
                return
            }
            
            currentDevice = videoDevice

            // Configure autofocus and exposure for inventory scanning (0.5-2m range)
            let settings = DetectionSettings.shared
            do {
                try videoDevice.lockForConfiguration()

                if settings.enableAutoFocus && videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoDevice.focusMode = .continuousAutoFocus
                    if videoDevice.isAutoFocusRangeRestrictionSupported {
                        videoDevice.autoFocusRangeRestriction = .near
                    }
                    appBootLog.infoWithContext("Autofocus: continuous, near-range")
                }

                if settings.enableAutoExposure && videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoDevice.exposureMode = .continuousAutoExposure
                    appBootLog.infoWithContext("Auto-exposure: continuous")
                }

                if videoDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    videoDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                videoDevice.unlockForConfiguration()
            } catch {
                appBootLog.warningWithContext("Could not configure focus/exposure: \(error.localizedDescription)")
            }

            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            
            session.beginConfiguration()

            // Use preset from DetectionSettings (default .hd1280x720 — much smaller than .photo 4032x3024)
            let presetString = DetectionSettings.shared.sessionPreset
            let preset: AVCaptureSession.Preset = {
                switch presetString {
                case "vga640x480": return .vga640x480
                case "hd1280x720": return .hd1280x720
                case "hd1920x1080": return .hd1920x1080
                case "photo": return .photo
                default: return .hd1280x720
                }
            }()
            session.sessionPreset = preset
            appBootLog.infoWithContext("Session preset: \(presetString)")
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                deviceInput = videoInput
                appBootLog.infoWithContext("Camera input added")
            } else {
                appBootLog.errorWithContext("Cannot add camera input")
                await MainActor.run {
                    error = .cannotAddInput
                }
                session.commitConfiguration()
                return
            }
            
            // Setup photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
                photoOutput.maxPhotoQualityPrioritization = .quality
                appBootLog.infoWithContext("Photo output added")
            } else {
                appBootLog.errorWithContext("Cannot add photo output")
            }
            
            // Setup movie output for video recording
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                appBootLog.infoWithContext("Movie output added")
            } else {
                appBootLog.errorWithContext("Cannot add movie output")
            }
            
            // Setup audio input for video recording
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                    if session.canAddInput(audioDeviceInput) {
                        session.addInput(audioDeviceInput)
                        self.audioInput = audioDeviceInput
                        appBootLog.infoWithContext("Audio input added")
                    }
                } catch {
                    appBootLog.errorWithContext("Could not add audio input: \(error.localizedDescription)")
                }
            }
            
            // Setup video output for frame processing
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.processing"))
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                appBootLog.infoWithContext("Video output added")
            } else {
                appBootLog.errorWithContext("Cannot add video output")
            }
            
            session.commitConfiguration()
            isSessionConfigured = true
            appBootLog.infoWithContext("Camera session configured successfully")
            
            // Automatically start the session after configuration
            await startSessionInternal()
            
        } catch {
            appBootLog.errorWithContext("Camera setup error: \(error.localizedDescription)")
            await MainActor.run {
                self.error = .cannotAddInput
            }
        }
    }
    
    // MARK: - Session Control
    
    private func startSessionInternal() async {
        guard !session.isRunning else {
            appBootLog.debugWithContext("Session already running")
            await MainActor.run {
                isSessionRunning = true
            }
            return
        }
        
        appBootLog.infoWithContext("Starting camera session...")
        
        // Start on background thread
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self.session.startRunning()
                
                Task { @MainActor in
                    self.isSessionRunning = true
                    appBootLog.infoWithContext("✅ Camera session started and running")
                }
                
                continuation.resume()
            }
        }
    }
    
    func startSession() {
        Task {
            guard isAuthorized else {
                appBootLog.errorWithContext("Cannot start session: not authorized")
                return
            }
            
            guard isSessionConfigured else {
                appBootLog.errorWithContext("Cannot start session: not configured yet")
                return
            }
            
            await startSessionInternal()
        }
    }
    
    func stopSession() {
        guard session.isRunning else { 
            appBootLog.debugWithContext("Session not running")
            Task { @MainActor in
                isSessionRunning = false
            }
            return 
        }
        
        appBootLog.infoWithContext("Stopping camera session...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            
            Task { @MainActor in
                self.isSessionRunning = false
                appBootLog.infoWithContext("Camera session stopped")
            }
        }
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto() {
        appBootLog.infoWithContext("Capture photo requested. Session running: \(session.isRunning), Configured: \(isSessionConfigured)")
        
        guard isSessionConfigured else {
            appBootLog.errorWithContext("Cannot capture: session not configured")
            error = .captureError("Camera session not configured")
            return
        }
        
        guard session.isRunning else {
            appBootLog.errorWithContext("Cannot capture: session not running")
            error = .captureError("Camera session not running. Please wait for camera to initialize.")
            return
        }
        
        let settings = AVCapturePhotoSettings()
        
        // Configure flash
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = isFlashOn ? .on : .off
        }
        
        appBootLog.infoWithContext("Initiating photo capture...")
        
        // Capture photo on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
            appBootLog.infoWithContext("Photo capture command sent")
        }
    }
    
    // MARK: - Flash Control
    
    func toggleFlash() {
        guard let device = currentDevice, device.hasFlash else { return }
        isFlashOn.toggle()
    }
    
    func setFlash(_ enabled: Bool) {
        guard let device = currentDevice, device.hasFlash else { return }
        isFlashOn = enabled
    }
    
    // MARK: - Video Recording
    
    func startRecording() {
        guard !isRecording else { return }
        guard session.isRunning else {
            error = .captureError("Camera session not running")
            return
        }
        
        // Create temporary file URL
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "recording_\(Date().timeIntervalSince1970).mov"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        // Remove any existing file at this location
        try? FileManager.default.removeItem(at: fileURL)
        
        currentVideoURL = fileURL
        
        appBootLog.infoWithContext("Starting video recording to: \(fileURL.path)")
        
        // Start recording
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        
        // Start timer to update duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        appBootLog.infoWithContext("Stopping video recording")
        
        movieOutput.stopRecording()
        
        // Timer will be invalidated in the delegate callback
    }
    
    private func cleanupRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
        isRecording = false
        recordingDuration = 0
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Get the callback handler
        guard let handler = onFrameCaptured else { return }

        // Convert CMSampleBuffer to UIImage
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Call the handler on main thread
        Task { @MainActor in
            handler(image)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            appBootLog.infoWithContext("✅ Recording started successfully")
        }
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.cleanupRecording()
            
            if let error = error {
                appBootLog.errorWithContext("Recording error: \(error.localizedDescription)")
                self.error = .captureError("Recording failed: \(error.localizedDescription)")
                return
            }
            
            appBootLog.infoWithContext("✅ Recording saved to: \(outputFileURL.path)")
            
            // Save to Photos Library
            appBootLog.infoWithContext("📱 Saving video to Photos Library...")
            await self.saveVideoToLibrary(outputFileURL)
            
            // Add to upload queue
            VideoUploadQueue.shared.addVideo(outputFileURL)
            
            // Notify that recording is complete and ready for upload
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoRecordingComplete"),
                object: nil,
                userInfo: ["url": outputFileURL]
            )
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.error = .captureError(error.localizedDescription)
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            Task { @MainActor in
                self.error = .captureError("No image data")
            }
            return
        }
        
        guard let image = UIImage(data: imageData) else {
            Task { @MainActor in
                self.error = .captureError("Could not create image")
            }
            return
        }
        
        Task { @MainActor in
            appBootLog.infoWithContext("Photo captured: \(imageData.count) bytes")

            // Store the captured image (CameraScanView watches this to trigger identification)
            self.lastCapturedImage = image

            // Save to Photo Library
            await self.savePhotoToLibrary(image)

            // Notify that photo was captured
            NotificationCenter.default.post(
                name: NSNotification.Name("PhotoCaptureComplete"),
                object: nil,
                userInfo: ["image": image]
            )
        }
    }
    
    private func savePhotoToLibrary(_ image: UIImage) async {
        // Check authorization
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        var authorized = false
        
        switch status {
        case .notDetermined:
            // Request permission
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            authorized = (newStatus == .authorized)
            
        case .authorized, .limited:
            authorized = true
            
        case .restricted, .denied:
            self.error = .captureError("Photo library access denied. Enable in Settings.")
            return
            
        @unknown default:
            return
        }
        
        guard authorized else {
            self.error = .captureError("Photo library access denied")
            return
        }
        
        // Save to photos
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            
            appBootLog.infoWithContext("✅ Photo saved to Photos Library")
            
        } catch {
            appBootLog.errorWithContext("Failed to save photo: \(error.localizedDescription)")
            self.error = .captureError("Failed to save photo: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Save Video to Library
    
    func saveVideoToLibrary(_ videoURL: URL) async {
        // Check authorization
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        var authorized = false
        
        switch status {
        case .notDetermined:
            // Request permission
            appBootLog.infoWithContext("Requesting photo library permission...")
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            authorized = (newStatus == .authorized)
            appBootLog.infoWithContext("Permission result: \(newStatus == .authorized ? "granted" : "denied")")
            
        case .authorized, .limited:
            authorized = true
            
        case .restricted, .denied:
            appBootLog.warningWithContext("⚠️ Photo library access denied")
            self.error = .captureError("Photo library access denied. Enable in Settings.")
            return
            
        @unknown default:
            return
        }
        
        guard authorized else {
            self.error = .captureError("Photo library access denied")
            return
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            appBootLog.errorWithContext("❌ Video file not found at: \(videoURL.path)")
            self.error = .captureError("Video file not found")
            return
        }
        
        appBootLog.infoWithContext("📱 Saving video to Photos Library...")
        appBootLog.debugWithContext("   File: \(videoURL.lastPathComponent)")
        
        // Save to photos
        do {
            var savedAssetIdentifier: String?
            
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                savedAssetIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
            }
            
            appBootLog.infoWithContext("✅ Video saved to Photos Library")
            if let identifier = savedAssetIdentifier {
                appBootLog.debugWithContext("   Asset ID: \(identifier)")
            }
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoSavedToPhotos"),
                object: nil,
                userInfo: [
                    "url": videoURL,
                    "assetIdentifier": savedAssetIdentifier as Any
                ]
            )
            
        } catch {
            appBootLog.errorWithContext("❌ Failed to save video to Photos: \(error.localizedDescription)")
            self.error = .captureError("Failed to save video: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Photo Identification
    
    /// Identify a photo using Gemini Vision API
    private func identifyPhotoWithGemini(_ image: UIImage) async {
        isIdentifyingPhoto = true
        photoIdentification = "Analyzing..."
        
        appBootLog.infoWithContext("🔍 Starting Gemini photo identification...")
        
        let geminiService = GeminiVisionService.shared
        await geminiService.identifyImage(image)
        
        // Update with the result
        if let error = geminiService.error {
            photoIdentification = "Error: \(error)"
            appBootLog.errorWithContext("❌ Gemini identification failed")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            appBootLog.errorWithContext("   Error: \(error)")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            // Also set camera error for UI display
            self.error = .captureError("Photo identification failed: \(error)")
            
        } else if !geminiService.latestIdentification.isEmpty {
            photoIdentification = geminiService.latestIdentification
            appBootLog.infoWithContext("✅ Gemini identification complete!")
            appBootLog.infoWithContext("   Result: \(geminiService.latestIdentification)")
        } else {
            photoIdentification = ""
            appBootLog.warningWithContext("⚠️ Gemini returned no identification")
        }
        
        isIdentifyingPhoto = false
    }
    
    /// Clear photo identification
    func clearPhotoIdentification() {
        photoIdentification = ""
        lastCapturedImage = nil
    }
}

// MARK: - Camera Errors

enum CameraError: Error, Identifiable {
    case permissionDenied
    case cannotAddInput
    case captureError(String)
    
    var id: String { localizedDescription }
    
    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Camera access denied. Please enable in Settings."
        case .cannotAddInput:
            return "Cannot access camera input."
        case .captureError(let message):
            return "Capture error: \(message)"
        }
    }
}
