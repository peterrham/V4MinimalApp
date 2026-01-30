//
//  DetectionSettings.swift
//  V4MinimalApp
//
//  Persisted camera & detection settings backed by UserDefaults
//

import Foundation

@MainActor
class DetectionSettings: ObservableObject {
    static let shared = DetectionSettings()

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

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        self.sessionPreset = ud.string(forKey: "ds_sessionPreset") ?? "hd1280x720"
        self.analysisInterval = ud.object(forKey: "ds_analysisInterval") as? Double ?? 1.5
        self.jpegQuality = ud.object(forKey: "ds_jpegQuality") as? Double ?? 0.6
        self.frameResizeWidth = ud.object(forKey: "ds_frameResizeWidth") as? Int ?? 640
        self.enableAutoFocus = ud.object(forKey: "ds_enableAutoFocus") as? Bool ?? true
        self.enableAutoExposure = ud.object(forKey: "ds_enableAutoExposure") as? Bool ?? true
        self.enableBackgroundEnrichment = ud.object(forKey: "ds_enableBackgroundEnrichment") as? Bool ?? true
    }
}
