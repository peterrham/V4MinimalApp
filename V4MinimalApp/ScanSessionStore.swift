//
//  ScanSessionStore.swift
//  V4MinimalApp
//
//  JSON-backed persistence for scan sessions (follows InventoryStore pattern)
//

import Foundation

@MainActor
class ScanSessionStore: ObservableObject {

    // MARK: - Published State

    @Published var sessions: [ScanSession] = []

    // MARK: - File Paths

    private let fileName = "scan_sessions.json"
    private let videoDirectoryName = "scan_videos"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private var videoDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(videoDirectoryName)
    }

    // MARK: - Initialization

    init() {
        ensureVideoDirectory()
        loadSessions()
    }

    private func ensureVideoDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: videoDirectoryURL.path) {
            try? fm.createDirectory(at: videoDirectoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - CRUD

    func addSession(_ session: ScanSession) {
        sessions.append(session)
        saveSessions()
    }

    func deleteSession(_ session: ScanSession) {
        // Remove video file
        let videoURL = videoDirectoryURL.appendingPathComponent(session.videoFileName)
        try? FileManager.default.removeItem(at: videoURL)

        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            let videoURL = videoDirectoryURL.appendingPathComponent(session.videoFileName)
            try? FileManager.default.removeItem(at: videoURL)
        }
        sessions.remove(atOffsets: offsets)
        saveSessions()
    }

    func updateSession(_ session: ScanSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
            saveSessions()
        }
    }

    // MARK: - Ground Truth

    func setGroundTruth(for sessionId: UUID, items: [GroundTruthItem]) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].groundTruth = GroundTruth(items: items)
            saveSessions()
        }
    }

    func addGroundTruthItem(to sessionId: UUID, name: String, category: String? = nil) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            let item = GroundTruthItem(name: name, category: category)
            sessions[idx].groundTruth.items.append(item)
            saveSessions()
        }
    }

    func removeGroundTruthItem(from sessionId: UUID, itemId: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].groundTruth.items.removeAll { $0.id == itemId }
            saveSessions()
        }
    }

    // MARK: - Pipeline Results

    func addPipelineRun(to sessionId: UUID, result: PipelineRunResult) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].pipelineRuns.append(result)
            saveSessions()
        }
    }

    func removePipelineRun(from sessionId: UUID, runId: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].pipelineRuns.removeAll { $0.id == runId }
            saveSessions()
        }
    }

    // MARK: - Video Management

    func videoURL(for session: ScanSession) -> URL {
        videoDirectoryURL.appendingPathComponent(session.videoFileName)
    }

    /// Copy a video from a temp URL to the scan_videos directory, returns the filename
    func saveVideo(from tempURL: URL, sessionName: String) -> String? {
        let sessionId = UUID().uuidString
        let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
        let fileName = "\(sessionId).\(ext)"
        let destURL = videoDirectoryURL.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: tempURL, to: destURL)
            return fileName
        } catch {
            print("Failed to copy video: \(error)")
            return nil
        }
    }

    // MARK: - Persistence

    func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scan sessions: \(error)")
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
            sessions = try decoder.decode([ScanSession].self, from: data)
        } catch {
            print("Failed to load scan sessions: \(error)")
            sessions = []
        }
    }
}
