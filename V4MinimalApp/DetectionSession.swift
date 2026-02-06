//
//  DetectionSession.swift
//  V4MinimalApp
//
//  Models for detection sessions — captures detected objects for later review/merge
//

import Foundation

/// A single item captured during a detection session.
/// Persisted subset of DetectedObject (which has non-Codable sourceFrame: UIImage?).
struct SessionItem: Codable, Identifiable {
    let id: UUID
    var name: String
    var brand: String?
    var color: String?
    var size: String?
    var categoryHint: String?
    var photoFilename: String?
    var boundingBox: CodableBoundingBox?
    var hasBoundingBox: Bool
    var yoloClassName: String?
    var isEnriched: Bool
    var detectedAt: Date
}

/// A detection session — a group of items found during one scanning pass.
struct DetectionSession: Codable, Identifiable {
    let id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var items: [SessionItem]
    var isMerged: Bool

    var itemCount: Int { items.count }

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
