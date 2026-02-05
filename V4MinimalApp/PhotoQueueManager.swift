//
//  PhotoQueueManager.swift
//  V4MinimalApp
//
//  Manager for the Photo Queue capture mode - handles queuing, concurrent processing, and metrics
//

import Foundation
import UIKit

@MainActor
class PhotoQueueManager: ObservableObject {

    // MARK: - Queue State

    @Published var queue: [QueuedPhoto] = []
    @Published var results: [PhotoQueueResult] = []
    @Published var isProcessing = false
    @Published var currentlyProcessing: Set<UUID> = []

    // MARK: - Metrics

    @Published var totalPhotosQueued = 0
    @Published var totalPhotosProcessed = 0
    @Published var totalItemsDetected = 0
    @Published var averageProcessingTimeMs: Int = 0
    @Published var averageItemsPerPhoto: Double = 0

    // MARK: - Configuration

    @Published var processingMode: PhotoQueueProcessingMode = .incremental
    var maxConcurrentWorkers = 2

    // MARK: - Incremental Mode State

    /// Items found so far (for incremental deduplication context)
    @Published var foundItemNames: [String] = []

    // MARK: - Session History

    @Published var sessions: [PhotoQueueSession] = []
    private var currentSession: PhotoQueueSession?

    // MARK: - Private State

    private var processingTask: Task<Void, Never>?
    private var processingTimes: [Int] = []
    private let maxTimeSamples = 20

    // MARK: - File Storage

    private var photosDir: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("photo_queue_photos")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var sessionsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("photo_queue_sessions.json")
    }

    // MARK: - Init

    init() {
        loadSessions()
    }

    // MARK: - Public Methods

    /// Queue a photo for processing. Returns the photo's UUID.
    @discardableResult
    func queuePhoto(_ image: UIImage) -> UUID {
        let photo = QueuedPhoto(image: image)
        queue.append(photo)
        totalPhotosQueued += 1

        // Start session if not already active
        if currentSession == nil {
            currentSession = PhotoQueueSession()
            NetworkLogger.shared.info("Photo Queue session started: \(currentSession!.name)", category: "PhotoQueue")
        }

        NetworkLogger.shared.info("Photo queued: \(photo.id) (queue size: \(queue.count), mode: \(processingMode.rawValue))", category: "PhotoQueue")

        // Auto-start processing based on mode
        // - Batch: wait for user to manually trigger processing
        // - Concurrent/Incremental: start immediately
        if processingMode != .batch && !isProcessing {
            startProcessing()
        }

        return photo.id
    }

    /// Start processing the queue.
    func startProcessing() {
        guard !isProcessing else { return }
        guard !queue.isEmpty else { return }

        isProcessing = true
        NetworkLogger.shared.info("Photo Queue processing started (mode: \(processingMode.rawValue), workers: \(maxConcurrentWorkers))", category: "PhotoQueue")

        processingTask = Task {
            switch processingMode {
            case .concurrent:
                await processQueueConcurrent()
            case .batch:
                await processQueueBatch()
            case .incremental:
                await processQueueIncremental()
            }
        }
    }

    /// Stop processing (cancels in-flight work).
    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        currentlyProcessing.removeAll()
        NetworkLogger.shared.info("Photo Queue processing stopped", category: "PhotoQueue")
    }

    /// Clear the queue (removes unprocessed photos).
    func clearQueue() {
        let removed = queue.filter { $0.status == .queued }.count
        queue.removeAll { $0.status == .queued }
        NetworkLogger.shared.info("Photo Queue cleared: \(removed) photos removed", category: "PhotoQueue")
    }

    /// Clear all results.
    func clearResults() {
        results.removeAll()
        totalItemsDetected = 0
        NetworkLogger.shared.info("Photo Queue results cleared", category: "PhotoQueue")
    }

    /// End the current session and save it.
    func endSession() {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        session.results = results
        sessions.insert(session, at: 0)  // Most recent first
        saveSessions()
        NetworkLogger.shared.info("Photo Queue session ended: \(session.totalPhotos) photos, \(session.totalItems) items", category: "PhotoQueue")
        currentSession = nil
    }

    /// Reset all state for a fresh start.
    func resetAll() {
        stopProcessing()
        queue.removeAll()
        results.removeAll()
        totalPhotosQueued = 0
        totalPhotosProcessed = 0
        totalItemsDetected = 0
        averageProcessingTimeMs = 0
        averageItemsPerPhoto = 0
        processingTimes.removeAll()
        currentSession = nil
    }

    // MARK: - Concurrent Processing (Original)

    private func processQueueConcurrent() async {
        await withTaskGroup(of: PhotoQueueResult?.self) { group in
            var activeCount = 0
            var queueIndex = 0

            while !Task.isCancelled {
                // Start workers up to max, if there are queued photos
                while activeCount < maxConcurrentWorkers && queueIndex < queue.count {
                    let photo = queue[queueIndex]
                    if photo.status == .queued {
                        // Mark as processing
                        queue[queueIndex].status = .processing
                        currentlyProcessing.insert(photo.id)

                        let photoToProcess = photo
                        group.addTask { [weak self] in
                            await self?.processPhoto(photoToProcess)
                        }
                        activeCount += 1
                    }
                    queueIndex += 1
                }

                // If nothing active and nothing left, we're done
                if activeCount == 0 && queueIndex >= queue.count {
                    break
                }

                // Wait for one to complete
                if let result = await group.next() {
                    activeCount -= 1
                    if let result = result {
                        // Update queue status
                        if let idx = queue.firstIndex(where: { $0.id == result.photoId }) {
                            queue[idx].status = result.error == nil ? .completed : .failed
                        }
                        currentlyProcessing.remove(result.photoId)
                        results.append(result)
                        updateMetrics(result)
                    }
                }
            }
        }

        isProcessing = false
        currentlyProcessing.removeAll()
        NetworkLogger.shared.info("Photo Queue (concurrent) complete: \(totalPhotosProcessed) photos, \(totalItemsDetected) items", category: "PhotoQueue")
    }

    // MARK: - Batch Processing

    /// Process all queued photos in a single Gemini API call
    private func processQueueBatch() async {
        let photosToProcess = queue.filter { $0.status == .queued }
        guard !photosToProcess.isEmpty else {
            isProcessing = false
            return
        }

        // Mark all as processing
        for i in queue.indices where queue[i].status == .queued {
            queue[i].status = .processing
            currentlyProcessing.insert(queue[i].id)
        }

        let start = CFAbsoluteTimeGetCurrent()
        NetworkLogger.shared.info("Batch processing \(photosToProcess.count) photos...", category: "PhotoQueue")

        // Collect all images
        let images = photosToProcess.map { $0.image }

        // Call Gemini with all images at once
        let allItems = await GeminiVisionService.shared.identifyAllItemsFromMultipleImages(images)
        let apiError = await GeminiVisionService.shared.error

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        // Save all photos to disk
        var photoFilenames: [UUID: String] = [:]
        for photo in photosToProcess {
            if let data = photo.image.jpegData(compressionQuality: 0.7) {
                let filename = "\(photo.id.uuidString).jpg"
                let url = photosDir.appendingPathComponent(filename)
                do {
                    try data.write(to: url)
                    photoFilenames[photo.id] = filename
                } catch {
                    NetworkLogger.shared.error("Failed to save batch photo: \(error)", category: "PhotoQueue")
                }
            }
        }

        // Create a single combined result (items from all photos together)
        // Use the first photo's ID as the "batch" photo ID
        let batchPhotoId = photosToProcess.first?.id ?? UUID()
        let items = allItems.map { PhotoQueueItem.from($0) }

        let result = PhotoQueueResult(
            photoId: batchPhotoId,
            items: items,
            capturedAt: photosToProcess.first?.capturedAt ?? Date(),
            processedAt: Date(),
            processingTimeMs: elapsedMs,
            photoFilename: photoFilenames[batchPhotoId],
            error: apiError
        )

        // Update queue status
        for i in queue.indices {
            if currentlyProcessing.contains(queue[i].id) {
                queue[i].status = apiError == nil ? .completed : .failed
            }
        }
        currentlyProcessing.removeAll()
        results.append(result)
        updateMetrics(result)

        isProcessing = false
        NetworkLogger.shared.info("Photo Queue (batch) complete: \(photosToProcess.count) photos → \(items.count) unique items in \(elapsedMs)ms", category: "PhotoQueue")
    }

    // MARK: - Incremental Processing

    /// Process photos one-by-one, passing context of previously found items
    private func processQueueIncremental() async {
        foundItemNames = []  // Reset context for this run

        while !Task.isCancelled {
            // Find next queued photo
            guard let index = queue.firstIndex(where: { $0.status == .queued }) else {
                break
            }

            let photo = queue[index]
            queue[index].status = .processing
            currentlyProcessing.insert(photo.id)

            let start = CFAbsoluteTimeGetCurrent()
            NetworkLogger.shared.info("Incremental processing photo \(photo.id) (context: \(foundItemNames.count) items)...", category: "PhotoQueue")

            // Call Gemini with context of previously found items
            let newItems: [PhotoIdentificationResult]
            if foundItemNames.isEmpty {
                // First photo - no context needed
                newItems = await GeminiVisionService.shared.identifyAllItems(photo.image)
            } else {
                // Subsequent photos - ask for NEW items only
                newItems = await GeminiVisionService.shared.identifyNewItems(photo.image, alreadyFound: foundItemNames)
            }
            let apiError = await GeminiVisionService.shared.error

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            // Update found items context
            let newItemNames = newItems.map { $0.name }
            foundItemNames.append(contentsOf: newItemNames)

            // Save photo to disk
            var photoFilename: String?
            if let data = photo.image.jpegData(compressionQuality: 0.7) {
                let filename = "\(photo.id.uuidString).jpg"
                let url = photosDir.appendingPathComponent(filename)
                do {
                    try data.write(to: url)
                    photoFilename = filename
                } catch {
                    NetworkLogger.shared.error("Failed to save incremental photo: \(error)", category: "PhotoQueue")
                }
            }

            let items = newItems.map { PhotoQueueItem.from($0) }
            let result = PhotoQueueResult(
                photoId: photo.id,
                items: items,
                capturedAt: photo.capturedAt,
                processedAt: Date(),
                processingTimeMs: elapsedMs,
                photoFilename: photoFilename,
                error: apiError
            )

            // Update status
            if let idx = queue.firstIndex(where: { $0.id == photo.id }) {
                queue[idx].status = apiError == nil ? .completed : .failed
            }
            currentlyProcessing.remove(photo.id)
            results.append(result)
            updateMetrics(result)

            NetworkLogger.shared.info("Photo \(photo.id) processed: \(items.count) NEW items in \(elapsedMs)ms (total found: \(foundItemNames.count))", category: "PhotoQueue")
        }

        isProcessing = false
        currentlyProcessing.removeAll()
        NetworkLogger.shared.info("Photo Queue (incremental) complete: \(totalPhotosProcessed) photos, \(foundItemNames.count) unique items", category: "PhotoQueue")
    }

    private func processPhoto(_ photo: QueuedPhoto) async -> PhotoQueueResult? {
        let start = CFAbsoluteTimeGetCurrent()

        NetworkLogger.shared.info("Processing photo \(photo.id)...", category: "PhotoQueue")

        // Call Gemini API
        let identificationResults = await GeminiVisionService.shared.identifyAllItems(photo.image)
        let apiError = await GeminiVisionService.shared.error

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        // Convert to PhotoQueueItems
        let items = identificationResults.map { PhotoQueueItem.from($0) }

        // Save photo to disk
        var photoFilename: String?
        if let data = photo.image.jpegData(compressionQuality: 0.7) {
            let filename = "\(photo.id.uuidString).jpg"
            let url = photosDir.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                photoFilename = filename
            } catch {
                NetworkLogger.shared.error("Failed to save queue photo: \(error)", category: "PhotoQueue")
            }
        }

        let result = PhotoQueueResult(
            photoId: photo.id,
            items: items,
            capturedAt: photo.capturedAt,
            processedAt: Date(),
            processingTimeMs: elapsedMs,
            photoFilename: photoFilename,
            error: apiError
        )

        NetworkLogger.shared.info("Photo \(photo.id) processed: \(items.count) items in \(elapsedMs)ms", category: "PhotoQueue")

        return result
    }

    private func updateMetrics(_ result: PhotoQueueResult) {
        totalPhotosProcessed += 1
        totalItemsDetected += result.items.count

        // Update rolling average processing time
        processingTimes.append(result.processingTimeMs)
        if processingTimes.count > maxTimeSamples {
            processingTimes.removeFirst()
        }
        let totalTime = processingTimes.reduce(0, +)
        averageProcessingTimeMs = processingTimes.isEmpty ? 0 : totalTime / processingTimes.count

        // Update items per photo
        averageItemsPerPhoto = totalPhotosProcessed > 0 ? Double(totalItemsDetected) / Double(totalPhotosProcessed) : 0
    }

    // MARK: - Persistence

    private func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: sessionsFileURL, options: .atomic)
        } catch {
            NetworkLogger.shared.error("Failed to save photo queue sessions: \(error)", category: "PhotoQueue")
        }
    }

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else {
            sessions = []
            return
        }
        do {
            let data = try Data(contentsOf: sessionsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([PhotoQueueSession].self, from: data)
        } catch {
            NetworkLogger.shared.error("Failed to load photo queue sessions: \(error)", category: "PhotoQueue")
            sessions = []
        }
    }

    /// Get the URL for a saved photo.
    func photoURL(for filename: String) -> URL {
        photosDir.appendingPathComponent(filename)
    }

    /// Delete a session and its photos.
    func deleteSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = sessions[index]

        // Delete photo files
        let filenames = Set(session.results.compactMap { $0.photoFilename })
        for filename in filenames {
            let url = photosDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }

        sessions.remove(at: index)
        saveSessions()
    }
}
