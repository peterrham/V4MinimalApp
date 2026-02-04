//
//  DetectionSessionStore.swift
//  V4MinimalApp
//
//  Persistent store for detection sessions
//

import Foundation
import SwiftUI

@MainActor
class DetectionSessionStore: ObservableObject {

    @Published var sessions: [DetectionSession] = []
    @Published var activeSessionId: UUID?

    private let fileName = "detection_sessions.json"
    private var itemsSinceLastSave = 0

    // MARK: - File URLs

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    private var sessionPhotosDir: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("session_photos")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Init

    init() {
        loadSessions()
    }

    // MARK: - Session Lifecycle

    /// Create a new session and set it as active. Returns the session ID.
    @discardableResult
    func createSession() -> UUID {
        let session = DetectionSession(
            id: UUID(),
            name: DetectionSession.autoName(),
            startedAt: Date(),
            items: [],
            isMerged: false
        )
        sessions.append(session)
        activeSessionId = session.id
        itemsSinceLastSave = 0
        saveSessions()
        NetworkLogger.shared.info("Session created: \(session.name) (\(session.id))", category: "Session")
        return session.id
    }

    /// Add a detected object to the active session.
    /// Creates a JPEG thumbnail immediately (sourceFrame is only available in memory).
    func addItem(from detection: DetectedObject) {
        guard let sessionId = activeSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        // Save photo from detection's source frame
        var photoFilename: String?
        if let imageData = detection.createThumbnailData() {
            let filename = "\(detection.id.uuidString).jpg"
            let url = sessionPhotosDir.appendingPathComponent(filename)
            do {
                try imageData.write(to: url)
                photoFilename = filename
            } catch {
                NetworkLogger.shared.error("Session photo save failed: \(error)", category: "Session")
            }
        }

        let sessionItem = SessionItem(
            id: detection.id,
            name: detection.name,
            brand: detection.brand,
            color: detection.color,
            size: detection.size,
            categoryHint: detection.categoryHint,
            photoFilename: photoFilename,
            boundingBox: nil,
            hasBoundingBox: detection.boundingBoxes != nil,
            yoloClassName: detection.yoloClassName,
            isEnriched: detection.isEnriched,
            detectedAt: detection.timestamp
        )

        sessions[index].items.append(sessionItem)
        itemsSinceLastSave += 1

        // Persist every 5 items for efficiency
        if itemsSinceLastSave >= 5 {
            saveSessions()
            itemsSinceLastSave = 0
        }
    }

    /// Add photo analysis results to a session. Saves the full source frame once and stores
    /// bounding box coordinates per item for on-demand cropping at display time.
    func addPhotoResults(_ results: [PhotoIdentificationResult], sourceImage: UIImage) {
        guard let sessionId = activeSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        // Save the full source frame once — all items from this photo share it
        let frameId = UUID().uuidString
        let frameFilename = "frame_\(frameId).jpg"
        let frameURL = sessionPhotosDir.appendingPathComponent(frameFilename)
        let maxDim: CGFloat = 1200
        let imgScale = min(1.0, maxDim / max(sourceImage.size.width, sourceImage.size.height))
        let newSize = CGSize(width: sourceImage.size.width * imgScale, height: sourceImage.size.height * imgScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.image { _ in sourceImage.draw(in: CGRect(origin: .zero, size: newSize)) }
        if let frameData = scaled.jpegData(compressionQuality: 0.7) {
            do {
                try frameData.write(to: frameURL)
                NetworkLogger.shared.info("Saved source frame \(frameFilename) (\(frameData.count / 1024)KB, \(Int(newSize.width))x\(Int(newSize.height)))", category: "Session")
            } catch {
                NetworkLogger.shared.error("Session frame save failed: \(error)", category: "Session")
            }
        }

        for result in results {
            // Convert bounding box tuple to Codable struct (coords are already 0-1 normalized)
            var codableBox: CodableBoundingBox?
            if let box = result.boundingBox {
                codableBox = CodableBoundingBox(yMin: Double(box.yMin), xMin: Double(box.xMin), yMax: Double(box.yMax), xMax: Double(box.xMax))
                NetworkLogger.shared.debug("📦 '\(result.name)' box=(y:\(String(format:"%.3f",box.yMin))-\(String(format:"%.3f",box.yMax)), x:\(String(format:"%.3f",box.xMin))-\(String(format:"%.3f",box.xMax)))", category: "Session")
            } else {
                NetworkLogger.shared.debug("📦 '\(result.name)' NO box", category: "Session")
            }

            let sessionItem = SessionItem(
                id: result.id,
                name: result.name,
                brand: result.brand,
                color: result.color,
                size: result.size,
                categoryHint: result.category,
                photoFilename: frameFilename,
                boundingBox: codableBox,
                hasBoundingBox: result.boundingBox != nil,
                yoloClassName: nil,
                isEnriched: true,
                detectedAt: Date()
            )
            sessions[index].items.append(sessionItem)
        }
        saveSessions()
        NetworkLogger.shared.info("Added \(results.count) photo results to session (frame: \(frameFilename))", category: "Session")
    }

    /// Crop a bounding box region from an image. Returns cropped UIImage, or the original if no box.
    /// Box coordinates are 0-1 normalized. Adds 10% padding around the crop.
    static func cropImage(_ image: UIImage, to box: CodableBoundingBox?) -> UIImage {
        guard let box = box, let cgImage = image.cgImage else { return image }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        let yMin = CGFloat(box.yMin) * imgH
        let xMin = CGFloat(box.xMin) * imgW
        let yMax = CGFloat(box.yMax) * imgH
        let xMax = CGFloat(box.xMax) * imgW

        let padX = (xMax - xMin) * 0.1
        let padY = (yMax - yMin) * 0.1
        let cropRect = CGRect(
            x: max(0, xMin - padX),
            y: max(0, yMin - padY),
            width: min(imgW, xMax + padX) - max(0, xMin - padX),
            height: min(imgH, yMax + padY) - max(0, yMin - padY)
        )

        if cropRect.width > 1 && cropRect.height > 1,
           let cropped = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: cropped)
        }
        return image
    }

    /// End the active session.
    func endSession() {
        guard let sessionId = activeSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        sessions[index].endedAt = Date()
        activeSessionId = nil
        itemsSinceLastSave = 0
        saveSessions()

        let count = sessions[index].items.count
        NetworkLogger.shared.info("Session ended: \(sessions[index].name) with \(count) items", category: "Session")
    }

    /// Merge all items from a session into the inventory store.
    func mergeSession(_ sessionId: UUID, into inventoryStore: InventoryStore) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = sessions[index]

        for item in session.items {
            // Check for existing item by name
            if let existingIndex = inventoryStore.findExistingItemByName(item.name) {
                // Merge fields into existing
                inventoryStore.mergeSessionItem(item, at: existingIndex)
            } else {
                // Build sibling list — other items from the same source frame
                var siblings: [FrameSibling]?
                if let photoFilename = item.photoFilename {
                    let sibs = session.items
                        .filter { $0.photoFilename == photoFilename && $0.id != item.id && $0.boundingBox != nil }
                        .map { FrameSibling(name: $0.name, boundingBox: $0.boundingBox!) }
                    if !sibs.isEmpty { siblings = sibs }
                }

                // Create new inventory item
                var inventoryItem = InventoryItem(
                    name: item.name,
                    category: ItemCategory.from(rawString: item.categoryHint ?? ""),
                    room: "",
                    brand: item.brand,
                    itemColor: item.color,
                    size: item.size,
                    boundingBox: item.boundingBox,
                    frameSiblings: siblings,
                    homeId: inventoryStore.currentHomeId
                )

                // Save cropped thumbnail + full source frame to inventory photos
                if let photoFilename = item.photoFilename {
                    let sourceURL = sessionPhotosDir.appendingPathComponent(photoFilename)
                    if let fullImage = UIImage(contentsOfFile: sourceURL.path) {
                        // Save cropped item photo as the main thumbnail
                        let cropped = DetectionSessionStore.cropImage(fullImage, to: item.boundingBox)
                        if let data = cropped.jpegData(compressionQuality: 0.6) {
                            let newFilename = inventoryStore.saveImagePublic(data, for: inventoryItem.id)
                            inventoryItem.photos.append(newFilename)
                        }
                        // Save full source frame for context viewing
                        if item.boundingBox != nil, let frameData = fullImage.jpegData(compressionQuality: 0.7) {
                            let frameFilename = inventoryStore.saveImagePublic(frameData, for: inventoryItem.id)
                            inventoryItem.sourceFramePhoto = frameFilename
                        }
                    }
                }

                inventoryStore.items.append(inventoryItem)
            }
        }

        sessions[index].isMerged = true
        inventoryStore.saveItems()
        saveSessions()
        NetworkLogger.shared.info("Merged session '\(session.name)' — \(session.items.count) items", category: "Session")
    }

    /// Delete a session and its photos.
    func deleteSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = sessions[index]

        // Collect unique photo filenames and remove them
        let filenames = Set(session.items.compactMap { $0.photoFilename })
        for filename in filenames {
            let url = sessionPhotosDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }

        sessions.remove(at: index)
        saveSessions()
    }

    /// URL for a session photo.
    func photoURL(for filename: String) -> URL {
        sessionPhotosDir.appendingPathComponent(filename)
    }

    /// Number of items in the active session.
    var activeSessionItemCount: Int {
        guard let sessionId = activeSessionId,
              let session = sessions.first(where: { $0.id == sessionId }) else { return 0 }
        return session.items.count
    }

    // MARK: - Persistence

    private func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NetworkLogger.shared.error("Failed to save sessions: \(error)", category: "Session")
        }
    }

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([DetectionSession].self, from: data)
        } catch {
            NetworkLogger.shared.error("Failed to load sessions: \(error)", category: "Session")
            sessions = []
        }
    }
}
