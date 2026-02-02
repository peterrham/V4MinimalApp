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

    // Fallback decoder: unknown category values decode as .other instead of crashing
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ItemCategory(rawValue: rawValue) ?? ItemCategory.from(rawString: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
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

extension ItemCategory {
    /// Map a raw string (from Gemini) to an ItemCategory case
    static func from(rawString: String) -> ItemCategory {
        let lower = rawString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Direct rawValue match
        if let match = ItemCategory.allCases.first(where: { $0.rawValue.lowercased() == lower }) {
            return match
        }
        // Alias / substring matching
        let aliases: [String: ItemCategory] = [
            "electronic": .electronics, "tv": .electronics, "computer": .electronics,
            "phone": .electronics, "laptop": .electronics, "monitor": .electronics,
            "tablet": .electronics, "speaker": .electronics, "camera": .electronics,
            "furnitur": .furniture, "chair": .furniture, "table": .furniture,
            "sofa": .furniture, "couch": .furniture, "desk": .furniture, "bed": .furniture,
            "appliance": .appliances, "washer": .appliances, "dryer": .appliances,
            "microwave": .appliances, "refrigerator": .appliances, "oven": .appliances,
            "cloth": .clothing, "shirt": .clothing, "pants": .clothing, "jacket": .clothing,
            "kitchen": .kitchenware, "utensil": .kitchenware, "pot": .kitchenware, "pan": .kitchenware,
            "decor": .decor, "lamp": .decor, "vase": .decor, "candle": .decor,
            "tool": .tools, "hammer": .tools, "drill": .tools, "wrench": .tools,
            "book": .books, "magazine": .books,
            "sport": .sports, "fitness": .sports, "exercise": .sports,
            "toy": .toys, "game": .toys,
            "jewel": .jewelry, "ring": .jewelry, "necklace": .jewelry, "watch": .jewelry,
            "art": .art, "painting": .art, "sculpture": .art, "collectible": .art,
        ]
        for (key, category) in aliases {
            if lower.contains(key) { return category }
        }
        return .other
    }
}

// MARK: - Inventory Item

struct InventoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: ItemCategory
    var room: String
    var container: String?
    var quantity: Int
    var upc: String?
    var isEmptyBox: Bool
    var estimatedValue: Double?
    var purchasePrice: Double?
    var purchaseDate: Date?
    var brand: String?
    var itemColor: String?
    var size: String?
    var notes: String
    var photos: [String]
    var voiceTranscripts: [String]
    let createdAt: Date
    var updatedAt: Date
    var homeId: UUID?

    // MARK: - CodingKeys (backward-compatible with old JSON lacking new fields)

    enum CodingKeys: String, CodingKey {
        case id, name, category, room, container
        case quantity, upc, isEmptyBox
        case estimatedValue, purchasePrice, purchaseDate
        case brand, itemColor, size, notes, photos, voiceTranscripts
        case createdAt, updatedAt, homeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(ItemCategory.self, forKey: .category)
        room = try c.decode(String.self, forKey: .room)
        container = try c.decodeIfPresent(String.self, forKey: .container)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        upc = try c.decodeIfPresent(String.self, forKey: .upc)
        isEmptyBox = try c.decodeIfPresent(Bool.self, forKey: .isEmptyBox) ?? false
        estimatedValue = try c.decodeIfPresent(Double.self, forKey: .estimatedValue)
        purchasePrice = try c.decodeIfPresent(Double.self, forKey: .purchasePrice)
        purchaseDate = try c.decodeIfPresent(Date.self, forKey: .purchaseDate)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        itemColor = try c.decodeIfPresent(String.self, forKey: .itemColor)
        size = try c.decodeIfPresent(String.self, forKey: .size)
        notes = try c.decode(String.self, forKey: .notes)
        photos = try c.decode([String].self, forKey: .photos)
        voiceTranscripts = try c.decode([String].self, forKey: .voiceTranscripts)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        homeId = try c.decodeIfPresent(UUID.self, forKey: .homeId)
    }

    // MARK: - Computed Display Properties

    static let dollarFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    var displayValue: String {
        if let price = purchasePrice {
            let rounded = price.rounded(.up)
            return "$\(Self.dollarFormatter.string(from: NSNumber(value: rounded)) ?? "0")"
        } else if let estimate = estimatedValue {
            let rounded = estimate.rounded(.up)
            return "$\(Self.dollarFormatter.string(from: NSNumber(value: rounded)) ?? "0")"
        } else {
            return ""
        }
    }

    var mainPhoto: String? {
        photos.first
    }

    /// Brand + name for detail views
    var displayTitle: String {
        if let brand = brand, !brand.isEmpty {
            return "\(brand) \(name)"
        }
        return name
    }

    /// Color · Category subtitle
    var displaySubtitle: String {
        var parts: [String] = []
        if let color = itemColor, !color.isEmpty {
            parts.append(color)
        }
        parts.append(category.rawValue)
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Title with quantity prefix when > 1
    var displayTitleWithQuantity: String {
        let title = displayTitle
        if quantity > 1 {
            return "\(quantity)x \(title)"
        }
        return title
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory,
        room: String,
        container: String? = nil,
        quantity: Int = 1,
        upc: String? = nil,
        isEmptyBox: Bool = false,
        estimatedValue: Double? = nil,
        purchasePrice: Double? = nil,
        purchaseDate: Date? = nil,
        brand: String? = nil,
        itemColor: String? = nil,
        size: String? = nil,
        notes: String = "",
        photos: [String] = [],
        voiceTranscripts: [String] = [],
        homeId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.room = room
        self.container = container
        self.quantity = quantity
        self.upc = upc
        self.isEmptyBox = isEmptyBox
        self.estimatedValue = estimatedValue
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.brand = brand
        self.itemColor = itemColor
        self.size = size
        self.notes = notes
        self.photos = photos
        self.voiceTranscripts = voiceTranscripts
        self.createdAt = Date()
        self.updatedAt = Date()
        self.homeId = homeId
    }
}

// MARK: - Disambiguation Helper

extension InventoryItem {
    /// Returns display title with brand only when the name is ambiguous among the provided items
    static func disambiguatedTitle(for item: InventoryItem, in items: [InventoryItem]) -> String {
        let sameName = items.filter {
            $0.id != item.id &&
            $0.name.caseInsensitiveCompare(item.name) == .orderedSame
        }
        let prefix = item.quantity > 1 ? "\(item.quantity)x " : ""
        if !sameName.isEmpty, let brand = item.brand, !brand.isEmpty {
            return "\(prefix)\(brand) \(item.name)"
        }
        return "\(prefix)\(item.name)"
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

// MARK: - Home Room (per-home room with enabled state)

struct HomeRoom: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var isEnabled: Bool
    var homeId: UUID

    init(id: UUID = UUID(), name: String, icon: String, isEnabled: Bool = false, homeId: UUID) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isEnabled = isEnabled
        self.homeId = homeId
    }

    static func defaultRooms(for homeId: UUID) -> [HomeRoom] {
        [
            HomeRoom(name: "Living Room", icon: "sofa.fill", isEnabled: true, homeId: homeId),
            HomeRoom(name: "Bathroom", icon: "shower.fill", homeId: homeId),
            HomeRoom(name: "Kitchen", icon: "fork.knife", homeId: homeId),
            HomeRoom(name: "Bedroom", icon: "bed.double.fill", homeId: homeId),
            HomeRoom(name: "Basement", icon: "stairs", homeId: homeId),
            HomeRoom(name: "Garage", icon: "car.fill", homeId: homeId),
        ]
    }
}

// MARK: - Home Model (Property/Location)

struct Home: Identifiable, Codable, Hashable {
    /// Well-known ID for the default home. Existing items without homeId belong here.
    static let defaultHomeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var icon: String
    var color: Color

    init(id: UUID = UUID(), name: String, icon: String = "house.fill", color: Color = .blue) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }

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
        // Convert Color to hex for persistence
        let uiColor = UIColor(color)
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        try container.encode(hex, forKey: .colorHex)
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
