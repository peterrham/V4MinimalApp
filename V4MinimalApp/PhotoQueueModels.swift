//
//  PhotoQueueModels.swift
//  V4MinimalApp
//
//  Data models for the Photo Queue capture mode
//

import Foundation
import UIKit

// MARK: - Processing Mode

enum PhotoQueueProcessingMode: String, CaseIterable, Identifiable {
    case concurrent = "Concurrent"
    case batch = "Batch"
    case incremental = "Incremental"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .concurrent:
            return "Process 2-3 photos in parallel. Fastest, but may have duplicates."
        case .batch:
            return "Send all photos to Gemini at once. Best deduplication, waits until done."
        case .incremental:
            return "Process one-by-one with context. Fast feedback + smart deduplication."
        }
    }

    var icon: String {
        switch self {
        case .concurrent: return "arrow.triangle.branch"
        case .batch: return "square.stack.3d.up"
        case .incremental: return "list.number"
        }
    }
}

// MARK: - Photo Queue Status

enum PhotoQueueStatus: String, Codable {
    case queued
    case processing
    case completed
    case failed
}

// MARK: - Queued Photo

struct QueuedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let capturedAt: Date
    var status: PhotoQueueStatus

    init(id: UUID = UUID(), image: UIImage, capturedAt: Date = Date(), status: PhotoQueueStatus = .queued) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
        self.status = status
    }
}

// MARK: - Photo Queue Item

struct PhotoQueueItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var brand: String?
    var color: String?
    var size: String?
    var category: String?
    var estimatedValue: Double?
    var description: String?
    var boundingBox: CodableBoundingBox?
    var isSaved: Bool

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        color: String? = nil,
        size: String? = nil,
        category: String? = nil,
        estimatedValue: Double? = nil,
        description: String? = nil,
        boundingBox: CodableBoundingBox? = nil,
        isSaved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.color = color
        self.size = size
        self.category = category
        self.estimatedValue = estimatedValue
        self.description = description
        self.boundingBox = boundingBox
        self.isSaved = isSaved
    }

    /// Create from a PhotoIdentificationResult
    static func from(_ result: PhotoIdentificationResult) -> PhotoQueueItem {
        var box: CodableBoundingBox?
        if let bb = result.boundingBox {
            box = CodableBoundingBox(
                yMin: Double(bb.yMin),
                xMin: Double(bb.xMin),
                yMax: Double(bb.yMax),
                xMax: Double(bb.xMax)
            )
        }
        return PhotoQueueItem(
            id: result.id,
            name: result.name,
            brand: result.brand,
            color: result.color,
            size: result.size,
            category: result.category,
            estimatedValue: result.estimatedValue,
            description: result.description,
            boundingBox: box,
            isSaved: false
        )
    }
}

// MARK: - Photo Queue Result

struct PhotoQueueResult: Identifiable, Codable {
    let id: UUID
    let photoId: UUID
    var items: [PhotoQueueItem]
    let capturedAt: Date
    let processedAt: Date
    let processingTimeMs: Int
    var photoFilename: String?
    var error: String?

    init(
        id: UUID = UUID(),
        photoId: UUID,
        items: [PhotoQueueItem],
        capturedAt: Date,
        processedAt: Date = Date(),
        processingTimeMs: Int,
        photoFilename: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.photoId = photoId
        self.items = items
        self.capturedAt = capturedAt
        self.processedAt = processedAt
        self.processingTimeMs = processingTimeMs
        self.photoFilename = photoFilename
        self.error = error
    }

    var itemCount: Int { items.count }
    var savedCount: Int { items.filter { $0.isSaved }.count }
    var isFullySaved: Bool { items.allSatisfy { $0.isSaved } }
}

// MARK: - Photo Queue Session

struct PhotoQueueSession: Codable, Identifiable {
    let id: UUID
    var name: String
    let startedAt: Date
    var endedAt: Date?
    var results: [PhotoQueueResult]

    init(
        id: UUID = UUID(),
        name: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        results: [PhotoQueueResult] = []
    ) {
        self.id = id
        self.name = name.isEmpty ? Self.autoName(date: startedAt) : name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.results = results
    }

    // MARK: - Computed Properties

    var totalPhotos: Int { results.count }

    var totalItems: Int { results.reduce(0) { $0 + $1.items.count } }

    var totalSavedItems: Int { results.reduce(0) { $0 + $1.savedCount } }

    var averageProcessingTimeMs: Int {
        guard !results.isEmpty else { return 0 }
        let total = results.reduce(0) { $0 + $1.processingTimeMs }
        return total / results.count
    }

    var averageItemsPerPhoto: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(totalItems) / Double(totalPhotos)
    }

    var displayDuration: String {
        let end = endedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(startedAt))
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            return "\(m)m \(s)s"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h)h \(m)m"
        }
    }

    static func autoName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}
