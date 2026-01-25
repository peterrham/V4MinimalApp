//
//  GeminiPromptExamples.swift
//  V4MinimalApp
//
//  Example prompts for different Gemini Vision use cases
//

import Foundation

/// Collection of prompt templates for different identification scenarios
enum GeminiPromptTemplates {
    
    // MARK: - General Purpose
    
    /// Default prompt - general object identification
    static let general = """
    What is in this image? Provide a brief, clear identification of the main object or scene. \
    Keep the response concise (1-2 sentences).
    """
    
    // MARK: - Inventory Specific
    
    /// Detailed inventory item description
    static let inventoryDetailed = """
    Identify this item for a home inventory. Include:
    - Item name
    - Estimated category (furniture, electronics, clothing, etc.)
    - Approximate value range if recognizable
    Keep it concise but informative.
    """
    
    /// Quick inventory tagging
    static let inventoryQuick = """
    What type of item is this? Provide a short category name (e.g., "Chair", "Laptop", "Book").
    """
    
    // MARK: - Shopping & Price
    
    /// Product identification with pricing hints
    static let shopping = """
    Identify this product. If it's a recognizable brand or model, mention it. \
    Suggest what category of store would sell this item.
    """
    
    // MARK: - Organization
    
    /// Room/space categorization
    static let roomCategory = """
    What room or space is this? Describe the main purpose of this area \
    (e.g., "Living room with modern furniture", "Kitchen workspace").
    """
    
    /// Storage organization
    static let storage = """
    What type of items are in this image? Suggest the best way to categorize or organize them.
    """
    
    // MARK: - Safety & Maintenance
    
    /// Safety inspection
    static let safety = """
    Identify this item and mention any visible safety concerns or maintenance needs.
    """
    
    /// Condition assessment
    static let condition = """
    Describe the condition of this item. Note any visible damage, wear, or issues.
    """
    
    // MARK: - Technical
    
    /// Brand and model identification
    static let technical = """
    Identify the brand, model, and type of this item. If there are any visible labels, \
    serial numbers, or technical specifications, mention them.
    """
    
    /// Compatibility checking
    static let compatibility = """
    What is this device or item? What other items or accessories would it be compatible with?
    """
    
    // MARK: - Creative
    
    /// Design and style analysis
    static let design = """
    Describe the design style and aesthetic of this item. What design era or style does it represent?
    """
    
    /// Color scheme
    static let colorScheme = """
    What are the main colors in this image? Describe the color scheme and mood.
    """
    
    // MARK: - Accessibility
    
    /// Detailed description for accessibility
    static let accessibility = """
    Provide a detailed description of this image for someone who cannot see it. \
    Include objects, people, colors, and spatial arrangement.
    """
    
    // MARK: - Custom Template Builder
    
    /// Build a custom prompt with specific requirements
    static func custom(
        task: String,
        details: [String] = [],
        maxSentences: Int = 2
    ) -> String {
        var prompt = task
        
        if !details.isEmpty {
            prompt += " Include:\n"
            for detail in details {
                prompt += "- \(detail)\n"
            }
        }
        
        if maxSentences > 0 {
            prompt += "Keep the response concise (\(maxSentences) sentence\(maxSentences == 1 ? "" : "s"))."
        }
        
        return prompt
    }
}

// MARK: - Usage Examples

/*
 
 HOW TO USE THESE PROMPTS
 ========================
 
 In GeminiVisionService.swift, replace the default prompt in createRequest():
 
 // Default (current implementation)
 ["text": "What is in this image? Provide a brief, clear identification..."]
 
 // Change to any template:
 ["text": GeminiPromptTemplates.inventoryDetailed]
 ["text": GeminiPromptTemplates.shopping]
 ["text": GeminiPromptTemplates.technical]
 
 // Or create a custom prompt:
 ["text": GeminiPromptTemplates.custom(
     task: "Identify this furniture item",
     details: ["Style/era", "Material", "Condition"],
     maxSentences: 3
 )]
 
 DYNAMIC PROMPTS
 ===============
 
 You can also add a prompt selector to your UI:
 
 1. Add to CameraManager:
    @Published var selectedPromptType: PromptType = .general
 
 2. Pass prompt to GeminiVisionService:
    func identifyImage(_ image: UIImage, prompt: String) async
 
 3. Select in UI:
    Picker("Analysis Type", selection: $cameraManager.selectedPromptType) {
        Text("General").tag(PromptType.general)
        Text("Inventory").tag(PromptType.inventory)
        Text("Technical").tag(PromptType.technical)
    }
 
 EXAMPLE RESPONSES
 ================
 
 General Prompt:
 → "A modern black office chair with adjustable armrests and wheels."
 
 Inventory Detailed:
 → "Office Chair - Furniture category. Ergonomic mesh chair with lumbar support. 
     Estimated value: $150-300 range."
 
 Technical:
 → "Herman Miller Aeron Chair, Model B (Medium Size). Ergonomic office seating 
     with PostureFit support and adjustable arms."
 
 Shopping:
 → "Office task chair, likely available at office furniture stores or retailers 
     like Staples, IKEA, or specialized ergonomic furniture shops."
 
 */
