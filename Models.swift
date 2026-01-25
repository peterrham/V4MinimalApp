//
//  InventoryItem.swift
//  V4MinimalApp
//
//  Home Inventory Data Model
//

import Foundation
import SwiftUI

// MARK: - Item Category

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case electronics = "Electronics"
    case furniture = "Furniture"
    case appliances = "Appliances"
    case clothing = "Clothing"
    case kitchenware = "Kitchenware"
    case decor = "Decor"
    case tools = "Tools"
    case books = "Books"
    case sports = "Sports & Fitness"
    case toys = "Toys & Games"
    case jewelry = "Jewelry"
    case art = "Art & Collectibles"
    case other = "Other"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .electronics: return "tv.fill"
        case .furniture: return "chair.fill"
        case .appliances: return "washer.fill"
        case .clothing: return "tshirt.fill"
        case .kitchenware: return "fork.knife"
        case .decor: return "lamp.table.fill"
        case .tools: return "hammer.fill"
        case .books: return "book.fill"
        case .sports: return "figure.run"
        case .toys: return "gamecontroller.fill"
        case .jewelry: return "sparkles"
        case .art: return "paintpalette.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .electronics: return .blue
        case .furniture: return .brown
        case .appliances: return .gray
        case .clothing: return .purple
        case .kitchenware: return .orange
        case .decor: return .pink
        case .tools: return .red
        case .books: return .green
        case .sports: return .mint
        case .toys: return .yellow
        case .jewelry: return .cyan
        case .art: return .indigo
        case .other: return .secondary
        }
    }
}

// MARK: - Inventory Item

struct InventoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: ItemCategory
    var room: String
    var estimatedValue: Double?
    var purchasePrice: Double?
    var purchaseDate: Date?
    var brand: String?
    var notes: String
    var photos: [String] // URLs or local paths
    var voiceTranscripts: [String]
    let createdAt: Date
    var updatedAt: Date
    
    // Computed property for display
    var displayValue: String {
        if let price = purchasePrice {
            return String(format: "$%.2f", price)
        } else if let estimate = estimatedValue {
            return String(format: "~$%.2f", estimate)
        } else {
            return "No value"
        }
    }
    
    var mainPhoto: String? {
        photos.first
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory,
        room: String,
        estimatedValue: Double? = nil,
        purchasePrice: Double? = nil,
        purchaseDate: Date? = nil,
        brand: String? = nil,
        notes: String = "",
        photos: [String] = [],
        voiceTranscripts: [String] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.room = room
        self.estimatedValue = estimatedValue
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.brand = brand
        self.notes = notes
        self.photos = photos
        self.voiceTranscripts = voiceTranscripts
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Room Model

struct Room: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var color: Color
    
    init(id: UUID = UUID(), name: String, icon: String = "door.left.hand.open", color: Color = .blue) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
    
    // Codable conformance for Color
    enum CodingKeys: String, CodingKey {
        case id, name, icon, colorHex
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        let hex = try container.decode(String.self, forKey: .colorHex)
        color = Color(hex: hex)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode("#6366F1", forKey: .colorHex) // Simplified for now
    }
}

// MARK: - Sample Data

extension InventoryItem {
    static let sampleItems: [InventoryItem] = [
        InventoryItem(
            name: "Samsung 55\" QLED TV",
            category: .electronics,
            room: "Living Room",
            estimatedValue: 1200,
            purchasePrice: 1299.99,
            purchaseDate: Date().addingTimeInterval(-180 * 24 * 60 * 60),
            brand: "Samsung",
            notes: "Purchased at Best Buy, extended warranty until 2026",
            photos: ["tv-photo"],
            voiceTranscripts: ["This is our main TV, we use it every day"]
        ),
        InventoryItem(
            name: "Leather Sofa",
            category: .furniture,
            room: "Living Room",
            estimatedValue: 2500,
            purchasePrice: 2800,
            purchaseDate: Date().addingTimeInterval(-365 * 24 * 60 * 60),
            brand: "Ashley",
            notes: "Brown leather, 3-seater",
            photos: ["sofa-photo"]
        ),
        InventoryItem(
            name: "KitchenAid Mixer",
            category: .appliances,
            room: "Kitchen",
            purchasePrice: 379.99,
            brand: "KitchenAid",
            notes: "Red color, with attachments"
        ),
        InventoryItem(
            name: "MacBook Pro 16\"",
            category: .electronics,
            room: "Home Office",
            purchasePrice: 2499,
            purchaseDate: Date().addingTimeInterval(-90 * 24 * 60 * 60),
            brand: "Apple",
            notes: "M3 Max, 36GB RAM, AppleCare+ until 2027"
        ),
        InventoryItem(
            name: "Queen Bed Frame",
            category: .furniture,
            room: "Bedroom",
            estimatedValue: 800,
            notes: "Wooden frame with headboard"
        )
    ]
}

extension Room {
    static let sampleRooms: [Room] = [
        Room(name: "Living Room", icon: "sofa.fill", color: AppTheme.Colors.primary),
        Room(name: "Kitchen", icon: "fork.knife", color: .orange),
        Room(name: "Bedroom", icon: "bed.double.fill", color: .purple),
        Room(name: "Home Office", icon: "desktopcomputer", color: .blue),
        Room(name: "Bathroom", icon: "shower.fill", color: .cyan),
        Room(name: "Garage", icon: "car.fill", color: .gray)
    ]
}
