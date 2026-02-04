//
//  DetectionSettings.swift
//  V4MinimalApp
//
//  Persisted camera & detection settings backed by UserDefaults
//

import Foundation

enum LiveDetectionPipeline: String, CaseIterable, Identifiable {
    case geminiOnly = "geminiOnly"
    case yoloThenGemini = "yoloThenGemini"
    case yoloBootstrapThenGemini = "yoloBootstrapThenGemini"
    case appleVisionBootstrap = "appleVisionBootstrap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .geminiOnly: return "Gemini Only (Cloud)"
        case .yoloThenGemini: return "YOLO + Gemini (Hybrid)"
        case .yoloBootstrapThenGemini: return "YOLO Bootstrap + Gemini"
        case .appleVisionBootstrap: return "Apple Vision + Gemini"
        }
    }

    var shortName: String {
        switch self {
        case .geminiOnly: return "Gemini"
        case .yoloThenGemini: return "Hybrid"
        case .yoloBootstrapThenGemini: return "YOLO Boot"
        case .appleVisionBootstrap: return "Vision"
        }
    }

    var description: String {
        switch self {
        case .geminiOnly: return "Full frame to Gemini every 2s"
        case .yoloThenGemini: return "YOLO instant boxes, Gemini enriches each crop"
        case .yoloBootstrapThenGemini: return "YOLO fills gaps until first Gemini response, then Gemini takes over"
        case .appleVisionBootstrap: return "Apple Vision classifies on-device (~1000 categories), then Gemini takes over"
        }
    }

    var isOnDevice: Bool {
        switch self {
        case .geminiOnly: return false
        case .yoloThenGemini, .yoloBootstrapThenGemini, .appleVisionBootstrap: return true
        }
    }
}

@MainActor
class DetectionSettings: ObservableObject {
    static let shared = DetectionSettings()

    // MARK: - Pipeline Selection

    @Published var detectionPipeline: LiveDetectionPipeline {
        didSet { UserDefaults.standard.set(detectionPipeline.rawValue, forKey: "ds_detectionPipeline") }
    }

    // MARK: - Camera Settings

    @Published var sessionPreset: String {
        didSet { UserDefaults.standard.set(sessionPreset, forKey: "ds_sessionPreset") }
    }

    @Published var enableAutoFocus: Bool {
        didSet { UserDefaults.standard.set(enableAutoFocus, forKey: "ds_enableAutoFocus") }
    }

    @Published var enableAutoExposure: Bool {
        didSet { UserDefaults.standard.set(enableAutoExposure, forKey: "ds_enableAutoExposure") }
    }

    // MARK: - Detection Settings

    @Published var analysisInterval: Double {
        didSet { UserDefaults.standard.set(analysisInterval, forKey: "ds_analysisInterval") }
    }

    @Published var jpegQuality: Double {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: "ds_jpegQuality") }
    }

    @Published var frameResizeWidth: Int {
        didSet { UserDefaults.standard.set(frameResizeWidth, forKey: "ds_frameResizeWidth") }
    }

    // MARK: - Enrichment Settings

    @Published var enableBackgroundEnrichment: Bool {
        didSet { UserDefaults.standard.set(enableBackgroundEnrichment, forKey: "ds_enableBackgroundEnrichment") }
    }

    // MARK: - HD Detection & Dedup

    @Published var useHDDetection: Bool {
        didSet { UserDefaults.standard.set(useHDDetection, forKey: "ds_useHDDetection") }
    }

    @Published var strictVisionDedup: Bool {
        didSet { UserDefaults.standard.set(strictVisionDedup, forKey: "ds_strictVisionDedup") }
    }

    @Published var useVideoStabilization: Bool {
        didSet { UserDefaults.standard.set(useVideoStabilization, forKey: "ds_useVideoStabilization") }
    }

    @Published var useGuidedMotionCoaching: Bool {
        didSet { UserDefaults.standard.set(useGuidedMotionCoaching, forKey: "ds_useGuidedMotionCoaching") }
    }

    // MARK: - UI Settings

    /// Tab bar icon size: 0 = default (26pt), 1 = large (34pt), 2 = extra-large (42pt)
    @Published var tabIconSize: Int {
        didSet { UserDefaults.standard.set(tabIconSize, forKey: "ds_tabIconSize") }
    }

    /// Computed icon point size for the tab bar
    var tabIconPointSize: CGFloat {
        switch tabIconSize {
        case 1: return 34
        case 2: return 42
        default: return 26
        }
    }

    /// Computed label font size for the tab bar
    var tabLabelFontSize: CGFloat {
        switch tabIconSize {
        case 1: return 14
        case 2: return 16
        default: return 13
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        let pipelineRaw = ud.string(forKey: "ds_detectionPipeline") ?? "appleVisionBootstrap"
        self.detectionPipeline = LiveDetectionPipeline(rawValue: pipelineRaw) ?? .appleVisionBootstrap
        self.sessionPreset = ud.string(forKey: "ds_sessionPreset") ?? "hd1280x720"
        self.analysisInterval = ud.object(forKey: "ds_analysisInterval") as? Double ?? 1.5
        self.jpegQuality = ud.object(forKey: "ds_jpegQuality") as? Double ?? 0.6
        self.frameResizeWidth = ud.object(forKey: "ds_frameResizeWidth") as? Int ?? 640
        self.enableAutoFocus = ud.object(forKey: "ds_enableAutoFocus") as? Bool ?? true
        self.enableAutoExposure = ud.object(forKey: "ds_enableAutoExposure") as? Bool ?? true
        self.enableBackgroundEnrichment = ud.object(forKey: "ds_enableBackgroundEnrichment") as? Bool ?? true
        self.useHDDetection = ud.object(forKey: "ds_useHDDetection") as? Bool ?? false
        self.strictVisionDedup = ud.object(forKey: "ds_strictVisionDedup") as? Bool ?? true
        self.useVideoStabilization = ud.object(forKey: "ds_useVideoStabilization") as? Bool ?? false
        self.useGuidedMotionCoaching = ud.object(forKey: "ds_useGuidedMotionCoaching") as? Bool ?? false
        self.tabIconSize = ud.object(forKey: "ds_tabIconSize") as? Int ?? 2
    }
}
