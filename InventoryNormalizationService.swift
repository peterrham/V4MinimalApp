//
//  InventoryNormalizationService.swift
//  V4MinimalApp
//
//  Batch normalization of inventory data using Gemini AI
//

import Foundation
import UIKit

@MainActor
class InventoryNormalizationService: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress: Int = 0
    @Published var total: Int = 0
    @Published var currentItem: String = ""
    @Published var errors: Int = 0
    @Published var garbageRemoved: Int = 0
    @Published var itemsUpdated: Int = 0
    @Published var lastRunSummary: String?

    private var cancelled = false

    weak var inventoryStore: InventoryStore?

    // Reuse same API config as GeminiVisionService
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    private var apiKey: String {
        GeminiVisionService.shared.apiKeyValue
    }

    // MARK: - Garbage Patterns

    private let garbagePatterns = [
        "cannot", "unable", "provided image", "bounding box",
        "no visible", "no visual", "Therefore", "no discernible",
        "impossible to identify", "not contain any", "entirely black",
        "completely black", "solid color", "no objects"
    ]

    // MARK: - Phase 1: Remove Garbage Items

    func removeGarbageItems() {
        guard let store = inventoryStore else { return }

        let before = store.items.count
        store.items.removeAll { item in
            let name = item.name
            if name.count > 80 { return true }
            let lower = name.lowercased()
            return garbagePatterns.contains { lower.contains($0.lowercased()) }
        }
        store.saveItems()

        garbageRemoved = before - store.items.count
        print("🧹 Removed \(garbageRemoved) garbage items (\(before) → \(store.items.count))")
    }

    /// Count how many items would be removed
    func countGarbageItems() -> Int {
        guard let store = inventoryStore else { return 0 }
        return store.items.filter { item in
            let name = item.name
            if name.count > 80 { return true }
            let lower = name.lowercased()
            return garbagePatterns.contains { lower.contains($0.lowercased()) }
        }.count
    }

    // MARK: - Phase 2: AI Normalization

    func normalizeAll() async {
        guard let store = inventoryStore else { return }
        guard !apiKey.isEmpty else {
            lastRunSummary = "Error: No API key configured"
            return
        }

        isRunning = true
        cancelled = false
        progress = 0
        errors = 0
        itemsUpdated = 0
        total = store.items.count
        lastRunSummary = nil

        for i in 0..<store.items.count {
            guard !cancelled else { break }

            let item = store.items[i]
            currentItem = item.name
            progress = i + 1

            do {
                let result = try await normalizeItem(item)
                if let result = result {
                    mergeResult(result, into: &store.items[i])
                    itemsUpdated += 1
                }
            } catch {
                errors += 1
                print("⚠️ Normalization error for '\(item.name)': \(error.localizedDescription)")
            }

            // Save every 10 items to avoid data loss
            if (i + 1) % 10 == 0 {
                store.saveItems()
            }

            // Rate limit: 1.5s between requests
            if !cancelled && i < store.items.count - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        store.saveItems()
        isRunning = false
        currentItem = ""
        lastRunSummary = "Done: \(itemsUpdated) updated, \(errors) errors out of \(total) items"
        print("✅ Normalization complete: \(itemsUpdated) updated, \(errors) errors")
    }

    func cancel() {
        cancelled = true
    }

    // MARK: - Single Item Normalization

    private func normalizeItem(_ item: InventoryItem) async throws -> NormalizationResult? {
        // Load photo if available
        var base64Image: String? = nil
        if let photoName = item.photos.first {
            let photoURL = InventoryStore.photoURL(for: photoName)
            if let image = UIImage(contentsOfFile: photoURL.path) {
                // Resize to 640px for smaller payload
                let resized = resizeImage(image, maxWidth: 640)
                if let jpegData = resized.jpegData(compressionQuality: 0.7) {
                    base64Image = jpegData.base64EncodedString()
                }
            }
        }

        let prompt = """
        You are normalizing a home inventory database.
        Current item name: "\(item.name)"
        \(base64Image != nil ? "Look at the photo and return" : "Based on the item name, return") corrected/enriched data.
        Return JSON only: {"name":"...","brand":"...","color":"...","size":"...","category":"...","estimatedValue":...,"room":"..."}
        category: one of Electronics, Furniture, Appliance, Decor, Kitchen, Clothing, Books, Tools, Sports, Toys, Valuables, Other.
        room: guess from context (Living Room, Bedroom, Kitchen, Bathroom, Office, Garage, Dining Room, Hallway, Closet, Other).
        estimatedValue: number in USD or null.
        Clean up the name to be concise (2-4 words, the specific object). JSON only, no markdown.
        """

        let request = try createRequest(base64Image: base64Image, prompt: prompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Normalization", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let candidate = geminiResponse.candidates.first,
              let content = candidate.content.parts.first else {
            return nil
        }

        let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return NormalizationResult.parse(from: responseText)
    }

    // MARK: - Merge Logic

    private func mergeResult(_ result: NormalizationResult, into item: inout InventoryItem) {
        // Name: always update if result looks reasonable
        if !result.name.isEmpty && result.name.count <= 60 && !result.name.contains("cannot") {
            item.name = result.name
        }

        // Brand: only fill if empty
        if (item.brand == nil || item.brand?.isEmpty == true), let brand = result.brand {
            item.brand = brand
        }

        // Color: only fill if empty
        if (item.itemColor == nil || item.itemColor?.isEmpty == true), let color = result.color {
            item.itemColor = color
        }

        // Size: only fill if empty
        if (item.size == nil || item.size?.isEmpty == true), let size = result.size {
            item.size = size
        }

        // Category: update if currently "Other"
        if let category = result.category {
            let newCat = ItemCategory.from(rawString: category)
            if item.category == .other && newCat != .other {
                item.category = newCat
            }
        }

        // Room: only fill if empty
        if item.room.isEmpty, let room = result.room {
            item.room = room
        }

        // EstimatedValue: only fill if nil
        if item.estimatedValue == nil && item.purchasePrice == nil, let value = result.estimatedValue {
            item.estimatedValue = value
        }

        item.updatedAt = Date()
    }

    // MARK: - API Request

    private func createRequest(base64Image: String?, prompt: String) throws -> URLRequest {
        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            throw NSError(domain: "Normalization", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var parts: [[String: Any]] = [["text": prompt]]

        if let base64Image = base64Image {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 200
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }

    // MARK: - Image Resize

    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let scale = min(1.0, maxWidth / image.size.width)
        if scale >= 1.0 { return image }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Normalization Result

struct NormalizationResult {
    var name: String
    var brand: String?
    var color: String?
    var size: String?
    var category: String?
    var estimatedValue: Double?
    var room: String?

    static func parse(from text: String) -> NormalizationResult? {
        // Strip markdown fences
        var cleaned = text
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}") else {
            return nil
        }

        let jsonStr = String(cleaned[startIdx...endIdx])
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = dict["name"] as? String ?? ""
        if name.isEmpty || name.contains("cannot") || name.contains("unable") {
            return nil
        }

        return NormalizationResult(
            name: name,
            brand: nullableString(dict["brand"]),
            color: nullableString(dict["color"]),
            size: nullableString(dict["size"]),
            category: nullableString(dict["category"]),
            estimatedValue: nullableDouble(dict["estimatedValue"]),
            room: nullableString(dict["room"])
        )
    }

    private static func nullableString(_ value: Any?) -> String? {
        guard let str = value as? String, str != "null", !str.isEmpty else { return nil }
        return str
    }

    private static func nullableDouble(_ value: Any?) -> Double? {
        if let num = value as? Double { return num }
        if let num = value as? Int { return Double(num) }
        if let str = value as? String, let num = Double(str) { return num }
        return nil
    }
}
