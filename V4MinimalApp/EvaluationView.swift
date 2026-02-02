//
//  EvaluationView.swift
//  V4MinimalApp
//
//  Scan session evaluation harness UI
//

import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos

// MARK: - Main Evaluation View

struct EvaluationView: View {
    @StateObject private var store = ScanSessionStore()
    @StateObject private var runner = PipelineRunner()
    @State private var selectedSession: ScanSession?
    @State private var showRecordSheet = false
    @State private var showImportPicker = false
    @State private var showGroundTruthEditor = false
    @State private var showComparisonView = false
    @State private var frameInterval: Double = 2.0
    @State private var startSecond: String = ""
    @State private var endSecond: String = ""
    @State private var selectedPipelines: Set<DetectionPipeline> = [.yoloOnly]
    @State private var selectedRun: PipelineRunResult?
    @State private var videoDurationSeconds: Double?
    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var player: AVPlayer?
    @State private var showingSaveConfirmation = false
    @State private var saveMessage = ""
    @State private var isExporting = false
    @State private var exportMessage = ""
    @State private var showExportAlert = false

    var body: some View {
        List {
            // Section 1: Sessions
            sessionsSection

            // Section 2: Selected Session Detail
            if let session = selectedSession {
                sessionDetailSection(session)
            }

            // Section 3: Results
            if let session = selectedSession, !session.pipelineRuns.isEmpty {
                resultsSection(session)
            }
        }
        .navigationTitle("Evaluation Harness")
        .sheet(isPresented: $showRecordSheet) {
            RecordVideoSheet(store: store) { session in
                selectedSession = session
            }
        }
        .sheet(isPresented: $showImportPicker) {
            VideoImportPicker(store: store) { session in
                selectedSession = session
            }
        }
        .sheet(isPresented: $showGroundTruthEditor) {
            if let session = selectedSession {
                GroundTruthEditorSheet(
                    store: store,
                    session: binding(for: session)
                )
            }
        }
        .sheet(isPresented: $showComparisonView) {
            if let session = selectedSession {
                ComparisonView(session: session)
            }
        }
        .sheet(item: $selectedRun) { run in
            PipelineRunDetailView(run: run)
        }
        .alert("Save to Photos", isPresented: $showingSaveConfirmation) {
            Button("OK") {}
        } message: {
            Text(saveMessage)
        }
        .alert("Export to Drive", isPresented: $showExportAlert) {
            Button("OK") {}
        } message: {
            Text(exportMessage)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onChange(of: selectedSession?.id) { _, _ in
            player?.pause()
            if let session = selectedSession {
                let url = store.videoURL(for: session)
                if FileManager.default.fileExists(atPath: url.path) {
                    player = AVPlayer(url: url)
                } else {
                    player = nil
                }
            } else {
                player = nil
            }
        }
    }

    // MARK: - Sessions Section

    private var sessionsSection: some View {
        Section {
            Button {
                showRecordSheet = true
            } label: {
                Label("Record New Video", systemImage: "video.badge.plus")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import from Photo Library", systemImage: "photo.on.rectangle")
            }

            Button {
                Task { await exportResultsToDrive() }
            } label: {
                HStack {
                    Label("Export All Results to Drive", systemImage: "icloud.and.arrow.up")
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isExporting || store.sessions.flatMap(\.pipelineRuns).isEmpty)

            ForEach(store.sessions) { session in
                Button {
                    selectedSession = session
                    videoDurationSeconds = nil
                    endSecond = ""
                    loadVideoDuration(session)
                } label: {
                    HStack(spacing: 10) {
                        // Thumbnail
                        if let thumb = thumbnailCache[session.id] {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: "film")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(session.recordedAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(session.groundTruth.items.count) GT")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("\(session.pipelineRuns.count) runs")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        if selectedSession?.id == session.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .onAppear {
                    loadThumbnail(for: session)
                }
            }
            .onDelete { offsets in
                let wasSelected = offsets.contains(where: { store.sessions[$0].id == selectedSession?.id })
                store.deleteSession(at: offsets)
                if wasSelected { selectedSession = nil }
            }
        } header: {
            Text("Sessions")
        }
    }

    // MARK: - Session Detail Section

    private func sessionDetailSection(_ session: ScanSession) -> some View {
        Section {
            // Video player
            VStack(spacing: 8) {
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Video not found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                HStack {
                    Text(session.videoFileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let dur = videoDurationSeconds {
                        Text(String(format: "%.1fs", dur))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        saveVideoToPhotos(session)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }

                    Button {
                        shareVideo(session)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                }
            }
            .onAppear {
                loadVideoDuration(session)
                if player == nil {
                    let url = store.videoURL(for: session)
                    if FileManager.default.fileExists(atPath: url.path) {
                        player = AVPlayer(url: url)
                    }
                }
            }

            // Ground truth
            Button {
                showGroundTruthEditor = true
            } label: {
                HStack {
                    Label("Ground Truth", systemImage: "checkmark.seal")
                    Spacer()
                    Text("\(session.groundTruth.items.count) items")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)

            // Frame interval picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Frame Interval")
                    .font(.subheadline)
                Picker("Interval", selection: $frameInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
            }

            // Start/end time range
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start (s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0", text: $startSecond)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("End (s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(videoDurationSeconds.map { String(format: "%.1f", $0) } ?? "end", text: $endSecond)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Spacer()
                if let dur = videoDurationSeconds {
                    Text(String(format: "Video: %.1fs", dur))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Leave blank for full video")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Pipeline selection — each pipeline is its own row so
            // List gives each an independent tap target.
            ForEach(DetectionPipeline.allCases) { pipeline in
                HStack {
                    Image(systemName: selectedPipelines.contains(pipeline)
                          ? "checkmark.square.fill" : "square")
                        .foregroundColor(selectedPipelines.contains(pipeline) ? .blue : .secondary)
                    VStack(alignment: .leading) {
                        Text(pipeline.rawValue)
                            .font(.subheadline)
                        Text(pipeline.isOnDevice ? "On-device" : "API")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedPipelines.contains(pipeline) {
                        selectedPipelines.remove(pipeline)
                    } else {
                        selectedPipelines.insert(pipeline)
                    }
                }
            }

            // Run button
            if runner.isRunning {
                VStack(spacing: 6) {
                    ProgressView(value: runner.progress)
                    Text(runner.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Cancel", role: .destructive) {
                        runner.cancel()
                    }
                    .font(.caption)
                }
            } else {
                Button {
                    Task {
                        await runSelectedPipelines(session)
                    }
                } label: {
                    Label("Run Selected Pipelines", systemImage: "play.fill")
                }
                .disabled(selectedPipelines.isEmpty)
            }
        } header: {
            Text("Session: \(session.name)")
        }
    }

    // MARK: - Results Section

    private func resultsSection(_ session: ScanSession) -> some View {
        Section {
            if session.pipelineRuns.count > 1 {
                Button {
                    showComparisonView = true
                } label: {
                    Label("Compare Pipelines", systemImage: "chart.bar.xaxis")
                }
            }

            ForEach(session.pipelineRuns.sorted(by: { $0.runDate > $1.runDate })) { run in
                Button {
                    selectedRun = run
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(run.pipeline.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        // Date/time and video range
                        HStack(spacing: 6) {
                            Text(run.runDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if run.videoStartTime > 0 || run.videoEndTime != nil {
                                Text("[\(String(format: "%.0f", run.videoStartTime))s–\(run.videoEndTime.map { String(format: "%.0f", $0) } ?? "end")s]")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            statBadge("\(run.detectedItems.count)", label: "items", color: .blue)
                            if let scores = run.scores {
                                statBadge(scores.recallPercent, label: "recall", color: .green)
                                statBadge(scores.precisionPercent, label: "prec", color: .orange)
                            }
                            statBadge(String(format: "%.1fs", run.durationSeconds), label: "time", color: .purple)
                        }
                        .font(.caption)

                        if run.apiCallCount > 0 {
                            Text("\(run.apiCallCount) API calls, \(run.framesProcessed) frames")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Results (tap for details)")
        }
    }

    // MARK: - Helpers

    private func statBadge(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .foregroundColor(.secondary)
        }
    }

    private func binding(for session: ScanSession) -> Binding<ScanSession> {
        Binding(
            get: {
                store.sessions.first { $0.id == session.id } ?? session
            },
            set: { newValue in
                store.updateSession(newValue)
                selectedSession = newValue
            }
        )
    }

    private func loadThumbnail(for session: ScanSession) {
        guard thumbnailCache[session.id] == nil else { return }
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return }
        Task.detached {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            if let cgImage = try? await generator.image(at: .zero).image {
                let img = UIImage(cgImage: cgImage)
                await MainActor.run { thumbnailCache[session.id] = img }
            }
        }
    }

    private func saveVideoToPhotos(_ session: ScanSession) {
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            saveMessage = "Video file not found"
            showingSaveConfirmation = true
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSaveToPhotos(url: videoURL)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performSaveToPhotos(url: videoURL)
                    } else {
                        saveMessage = "Photo library access denied"
                        showingSaveConfirmation = true
                    }
                }
            }
        default:
            saveMessage = "Photo library access denied. Enable in Settings."
            showingSaveConfirmation = true
        }
    }

    private func performSaveToPhotos(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    saveMessage = "Video saved to Photos"
                } else {
                    saveMessage = "Failed to save: \(error?.localizedDescription ?? "unknown error")"
                }
                showingSaveConfirmation = true
            }
        }
    }

    private func shareVideo(_ session: ScanSession) {
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return }
        let activityVC = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        // Find the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        activityVC.popoverPresentationController?.sourceView = topVC.view
        topVC.present(activityVC, animated: true)
    }

    // MARK: - Export to Google Drive

    private func exportResultsToDrive() async {
        guard let token = AuthManager.shared.getAccessToken(), !token.isEmpty else {
            exportMessage = "Not signed in to Google. Sign in from Settings first."
            showExportAlert = true
            return
        }

        isExporting = true
        defer { isExporting = false }

        let allRuns = store.sessions.flatMap { session in
            session.pipelineRuns.map { (session, $0) }
        }
        guard !allRuns.isEmpty else {
            exportMessage = "No pipeline runs to export."
            showExportAlert = true
            return
        }

        // Find or create export folder
        let folderId: String
        do {
            folderId = try await findOrCreateDriveFolder(name: "EvalHarness", token: token)
        } catch {
            exportMessage = "Failed to create Drive folder: \(error.localizedDescription)"
            showExportAlert = true
            return
        }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFmt.string(from: Date())

        // --- Summary CSV ---
        var summaryCSV = "Session,Pipeline,Date,Items Detected,Ground Truth,Matched,Recall,Precision,Name Quality,Duration (s),Frames,API Calls,Video Start,Video End\n"
        for (session, run) in allRuns {
            let row = [
                csvEscape(session.name),
                csvEscape(run.pipeline.rawValue),
                run.runDate.ISO8601Format(),
                "\(run.detectedItems.count)",
                "\(session.groundTruth.items.count)",
                "\(run.scores?.matchedCount ?? 0)",
                run.scores.map { String(format: "%.1f%%", $0.recall * 100) } ?? "",
                run.scores.map { String(format: "%.1f%%", $0.precision * 100) } ?? "",
                run.scores.map { String(format: "%.1f", $0.avgNameQuality) } ?? "",
                String(format: "%.1f", run.durationSeconds),
                "\(run.framesProcessed)",
                "\(run.apiCallCount)",
                String(format: "%.1f", run.videoStartTime),
                run.videoEndTime.map { String(format: "%.1f", $0) } ?? "end"
            ].joined(separator: ",")
            summaryCSV += row + "\n"
        }

        // --- Detailed Items CSV ---
        var itemsCSV = "Session,Pipeline,Run Date,Frame,Item Name,Brand,Color,Size,Category,Confidence,Has BBox,OCR Text\n"
        for (session, run) in allRuns {
            for item in run.detectedItems {
                let row = [
                    csvEscape(session.name),
                    csvEscape(run.pipeline.rawValue),
                    run.runDate.ISO8601Format(),
                    "\(item.frameIndex)",
                    csvEscape(item.name),
                    csvEscape(item.brand ?? ""),
                    csvEscape(item.color ?? ""),
                    csvEscape(item.size ?? ""),
                    csvEscape(item.category ?? ""),
                    item.confidence.map { String(format: "%.2f", $0) } ?? "",
                    item.boundingBox != nil ? "Yes" : "No",
                    csvEscape(item.ocrText?.joined(separator: "; ") ?? "")
                ].joined(separator: ",")
                itemsCSV += row + "\n"
            }
        }

        // --- Match Details CSV ---
        var matchCSV = "Session,Pipeline,Run Date,Ground Truth Item,Detected As,Match Type\n"
        for (session, run) in allRuns {
            if let scores = run.scores {
                for detail in scores.matchDetails {
                    let row = [
                        csvEscape(session.name),
                        csvEscape(run.pipeline.rawValue),
                        run.runDate.ISO8601Format(),
                        csvEscape(detail.groundTruthName),
                        csvEscape(detail.detectedName ?? ""),
                        detail.matchType.rawValue.uppercased()
                    ].joined(separator: ",")
                    matchCSV += row + "\n"
                }
            }
        }

        // Upload all three
        var uploaded = 0
        var errors: [String] = []

        for (name, csv) in [
            ("summary_\(timestamp).csv", summaryCSV),
            ("items_\(timestamp).csv", itemsCSV),
            ("matches_\(timestamp).csv", matchCSV)
        ] {
            do {
                try await uploadCSVToDrive(csv: csv, filename: name, folderId: folderId, token: token)
                uploaded += 1
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }

        if errors.isEmpty {
            exportMessage = "Exported \(uploaded) files to Google Drive/EvalHarness"
        } else {
            exportMessage = "Uploaded \(uploaded)/3. Errors: \(errors.joined(separator: "; "))"
        }
        showExportAlert = true
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func findOrCreateDriveFolder(name: String, token: String) async throws -> String {
        // Search for existing folder
        let query = "mimeType='application/vnd.google-apps.folder' and name='\(name)' and trashed=false"
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(escaped)&fields=files(id,name)")!

        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        searchReq.timeoutInterval = 15

        let (searchData, searchResp) = try await URLSession.shared.data(for: searchReq)
        guard let httpResp = searchResp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let firstId = files.first?["id"] as? String {
            return firstId
        }

        // Create folder
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.timeoutInterval = 15

        let metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        guard let createHttp = createResp as? HTTPURLResponse, createHttp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let createJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let folderId = createJson["id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return folderId
    }

    private func uploadCSVToDrive(csv: String, filename: String, folderId: String, token: String) async throws {
        guard let fileData = csv.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }

        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let metadata: [String: Any] = [
            "name": filename,
            "mimeType": "text/csv",
            "parents": [folderId]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
    }

    private func loadVideoDuration(_ session: ScanSession) {
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return }
        Task {
            let asset = AVURLAsset(url: videoURL)
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds > 0 {
                    videoDurationSeconds = seconds
                    if endSecond.isEmpty {
                        endSecond = String(format: "%.1f", seconds)
                    }
                }
            }
        }
    }

    private func runSelectedPipelines(_ session: ScanSession) async {
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            runner.statusMessage = "Video file not found"
            return
        }

        let start = Double(startSecond) ?? 0
        let end = Double(endSecond)

        for pipeline in selectedPipelines.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let result = await runner.runPipeline(
                pipeline,
                videoURL: videoURL,
                sessionId: session.id,
                intervalSeconds: frameInterval,
                startTime: start,
                endTime: end,
                groundTruth: session.groundTruth
            ) else { continue }

            store.addPipelineRun(to: session.id, result: result)
            // Refresh selected session
            if let updated = store.sessions.first(where: { $0.id == session.id }) {
                selectedSession = updated
            }
        }
    }
}

// MARK: - Pipeline Run Detail View

struct PipelineRunDetailView: View {
    let run: PipelineRunResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section {
                    LabeledContent("Pipeline", value: run.pipeline.rawValue)
                    LabeledContent("Run Date", value: run.runDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))
                    LabeledContent("Items Detected", value: "\(run.detectedItems.count)")
                    LabeledContent("Frames Processed", value: "\(run.framesProcessed)")
                    LabeledContent("Duration", value: String(format: "%.1fs", run.durationSeconds))
                    LabeledContent("Video Range", value: "\(String(format: "%.1f", run.videoStartTime))s – \(run.videoEndTime.map { String(format: "%.1f", $0) } ?? "end")s")
                    if run.apiCallCount > 0 {
                        LabeledContent("API Calls", value: "\(run.apiCallCount)")
                    }
                    if let scores = run.scores {
                        LabeledContent("Recall", value: scores.recallPercent)
                        LabeledContent("Precision", value: scores.precisionPercent)
                        LabeledContent("Name Quality", value: String(format: "%.1f/5", scores.avgNameQuality))
                    }
                } header: {
                    Text("Summary")
                }

                // All detected items
                Section {
                    ForEach(run.detectedItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.subheadline.bold())

                            HStack(spacing: 8) {
                                if let conf = item.confidence {
                                    Text(String(format: "%.0f%%", conf * 100))
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                if let brand = item.brand, !brand.isEmpty {
                                    Text(brand)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let color = item.color, !color.isEmpty {
                                    Text(color)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let cat = item.category, !cat.isEmpty {
                                    Text(cat)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Frame \(item.frameIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if item.boundingBox != nil {
                                    Image(systemName: "rectangle.dashed")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                if let ocr = item.ocrText, !ocr.isEmpty {
                                    Text("OCR: \(ocr.prefix(2).joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Detected Items (\(run.detectedItems.count))")
                }
            }
            .navigationTitle("\(run.pipeline.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Record Video Sheet

struct RecordVideoSheet: View {
    @ObservedObject var store: ScanSessionStore
    var onSessionCreated: (ScanSession) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sessionName = ""
    @State private var isRecording = false
    @StateObject private var cameraManager = CameraManager()
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Camera preview — use the app's existing CameraPreview which
                // overrides layerClass so the preview auto-resizes correctly
                CameraPreview(session: cameraManager.session)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                // Session name
                TextField("Session name (e.g. Kitchen Shelf)", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Recording controls
                if isRecording {
                    VStack(spacing: 8) {
                        HStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text(String(format: "Recording: %.1fs", recordingDuration))
                                .font(.headline)
                                .monospacedDigit()
                        }

                        Button {
                            stopRecording()
                        } label: {
                            Label("Stop Recording", systemImage: "stop.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Button {
                        startRecording()
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(sessionName.isEmpty ? .gray : .red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(sessionName.isEmpty)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Record Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                cameraManager.startSession()
            }
            .onDisappear {
                timer?.invalidate()
                if isRecording {
                    cameraManager.stopRecording()
                }
                cameraManager.stopSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VideoRecordingComplete"))) { notification in
                handleRecordingComplete(notification)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        recordingDuration = 0
        cameraManager.startRecording()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        cameraManager.stopRecording()
    }

    private func handleRecordingComplete(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        isRecording = false

        let name = sessionName.isEmpty ? "Session \(Date().formatted(.dateTime.month().day().hour().minute()))" : sessionName

        if let fileName = store.saveVideo(from: url, sessionName: name) {
            let session = ScanSession(
                name: name,
                videoFileName: fileName
            )
            store.addSession(session)
            onSessionCreated(session)
            dismiss()
        }
    }
}

// MARK: - Video Import Picker (Photo Library)

struct VideoImportPicker: UIViewControllerRepresentable {
    @ObservedObject var store: ScanSessionStore
    var onSessionCreated: (ScanSession) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoImportPicker

        init(_ parent: VideoImportPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.dismiss()
                return
            }

            let provider = result.itemProvider
            guard provider.hasItemConformingToTypeIdentifier("public.movie") else {
                parent.dismiss()
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
                guard let self, let url else {
                    DispatchQueue.main.async { self?.parent.dismiss() }
                    return
                }

                // Copy to a temp location (the provided URL is ephemeral)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: tempURL)

                DispatchQueue.main.async {
                    let dateFmt = DateFormatter()
                    dateFmt.dateFormat = "MMM d, h:mm a"
                    let name = "Import \(dateFmt.string(from: Date()))"

                    if let fileName = self.parent.store.saveVideo(from: tempURL, sessionName: name) {
                        let session = ScanSession(
                            name: name,
                            videoFileName: fileName
                        )
                        self.parent.store.addSession(session)
                        self.parent.onSessionCreated(session)
                    }
                    // Clean up temp
                    try? FileManager.default.removeItem(at: tempURL)
                    self.parent.dismiss()
                }
            }
        }
    }
}

// MARK: - Ground Truth Editor Sheet

struct GroundTruthEditorSheet: View {
    @ObservedObject var store: ScanSessionStore
    @Binding var session: ScanSession
    @Environment(\.dismiss) private var dismiss
    @State private var newItemName = ""
    @State private var newItemCategory = ""
    @State private var showSheetsImport = false

    var body: some View {
        NavigationStack {
            List {
                // Google Sheets import
                Section {
                    Button {
                        showSheetsImport = true
                    } label: {
                        Label("Import from Google Sheets", systemImage: "tablecells.badge.ellipsis")
                    }
                } header: {
                    Text("Import")
                }

                // Manual add
                Section {
                    HStack {
                        TextField("Item name", text: $newItemName)
                        Button {
                            guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let cat = newItemCategory.isEmpty ? nil : newItemCategory
                            store.addGroundTruthItem(
                                to: session.id,
                                name: newItemName.trimmingCharacters(in: .whitespaces),
                                category: cat
                            )
                            newItemName = ""
                            newItemCategory = ""
                            refreshSession()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    TextField("Category (optional)", text: $newItemCategory)
                        .font(.caption)
                } header: {
                    Text("Add Manually")
                }

                // Current items
                Section {
                    if session.groundTruth.items.isEmpty {
                        Text("No ground truth items yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(session.groundTruth.items) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                if let cat = item.category {
                                    Text(cat)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                let item = session.groundTruth.items[offset]
                                store.removeGroundTruthItem(from: session.id, itemId: item.id)
                            }
                            refreshSession()
                        }
                    }
                } header: {
                    Text("Items (\(session.groundTruth.items.count))")
                }
            }
            .navigationTitle("Ground Truth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSheetsImport) {
                GoogleSheetsImportView(store: store, session: $session)
            }
        }
    }

    private func refreshSession() {
        if let updated = store.sessions.first(where: { $0.id == session.id }) {
            session = updated
        }
    }
}

// MARK: - Google Sheets Import

struct GoogleSheetsImportView: View {
    @ObservedObject var store: ScanSessionStore
    @Binding var session: ScanSession
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = "ground truth"
    @State private var spreadsheets: [(id: String, name: String)] = []
    @State private var isSearching = false
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var previewItems: [(name: String, category: String?)] = []
    @State private var selectedSheetId: String?
    @State private var selectedSheetName: String?

    var body: some View {
        NavigationStack {
            List {
                // Search
                Section {
                    HStack {
                        TextField("Search sheets...", text: $searchQuery)
                            .textInputAutocapitalization(.never)
                        Button {
                            Task { await searchSheets() }
                        } label: {
                            if isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    }
                } header: {
                    Text("Search Google Drive")
                } footer: {
                    Text("Searches your Google Drive for spreadsheets. Column A = item name, Column B = category (optional).")
                }

                // Results
                if !spreadsheets.isEmpty {
                    Section {
                        ForEach(spreadsheets, id: \.id) { sheet in
                            Button {
                                selectedSheetId = sheet.id
                                selectedSheetName = sheet.name
                                Task { await loadSheet(id: sheet.id) }
                            } label: {
                                HStack {
                                    Image(systemName: "tablecells")
                                        .foregroundColor(.green)
                                    Text(sheet.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedSheetId == sheet.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Spreadsheets")
                    }
                }

                // Preview
                if !previewItems.isEmpty {
                    Section {
                        ForEach(Array(previewItems.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                if let cat = item.category {
                                    Text(cat)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Preview (\(previewItems.count) items from \(selectedSheetName ?? ""))")
                    }

                    Section {
                        Button {
                            importItems()
                        } label: {
                            Label("Import \(previewItems.count) Items", systemImage: "square.and.arrow.down")
                                .fontWeight(.semibold)
                        }
                    }
                }

                // Status
                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading sheet data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import from Sheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func getAccessToken() -> String? {
        AuthManager.shared.getAccessToken()
    }

    private func searchSheets() async {
        guard let token = getAccessToken(), !token.isEmpty else {
            statusMessage = "Not signed in to Google. Sign in from Settings first."
            return
        }

        isSearching = true
        statusMessage = ""
        spreadsheets = []
        previewItems = []
        selectedSheetId = nil

        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "https://www.googleapis.com/drive/v3/files?q=mimeType%3D'application%2Fvnd.google-apps.spreadsheet'+and+name+contains+'\(escaped)'&orderBy=modifiedTime+desc&pageSize=10&fields=files(id%2Cname)"

        guard let url = URL(string: urlStr) else {
            statusMessage = "Invalid search query"
            isSearching = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                statusMessage = "Invalid response"
                isSearching = false
                return
            }

            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                statusMessage = "Google auth expired. Re-sign in from Settings."
                isSearching = false
                return
            }

            guard httpResp.statusCode == 200 else {
                statusMessage = "Drive API error: HTTP \(httpResp.statusCode)"
                isSearching = false
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let files = json["files"] as? [[String: Any]] {
                spreadsheets = files.compactMap { file in
                    guard let id = file["id"] as? String,
                          let name = file["name"] as? String else { return nil }
                    return (id: id, name: name)
                }
                if spreadsheets.isEmpty {
                    statusMessage = "No spreadsheets found matching '\(query)'"
                }
            }
        } catch {
            statusMessage = "Search failed: \(error.localizedDescription)"
        }

        isSearching = false
    }

    private func loadSheet(id: String) async {
        guard let token = getAccessToken() else {
            statusMessage = "Not signed in"
            return
        }

        isLoading = true
        previewItems = []

        // Read A:B from the first sheet
        let urlStr = "https://sheets.googleapis.com/v4/spreadsheets/\(id)/values/Sheet1!A:B?key=&majorDimension=ROWS"
        guard let url = URL(string: urlStr) else {
            statusMessage = "Invalid sheet URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                // Try without "Sheet1" in case the sheet has a different name
                let fallbackResult = await loadSheetFallback(id: id, token: token)
                if fallbackResult {
                    isLoading = false
                    return
                }
                statusMessage = "Failed to read sheet (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                isLoading = false
                return
            }

            parseSheetData(data)
        } catch {
            statusMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func loadSheetFallback(id: String, token: String) async -> Bool {
        // Try reading without specifying sheet name (uses first sheet)
        let urlStr = "https://sheets.googleapis.com/v4/spreadsheets/\(id)/values/A:B?majorDimension=ROWS"
        guard let url = URL(string: urlStr) else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            return false
        }

        parseSheetData(data)
        return !previewItems.isEmpty
    }

    private func parseSheetData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[Any]] else {
            statusMessage = "No data found in sheet"
            return
        }

        var items: [(name: String, category: String?)] = []
        for (i, row) in values.enumerated() {
            guard let name = row.first as? String else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Skip header row if it looks like one
            if i == 0 {
                let lower = trimmed.lowercased()
                if lower == "name" || lower == "item" || lower == "item name" || lower == "items" {
                    continue
                }
            }

            let category: String?
            if row.count > 1, let cat = row[1] as? String, !cat.trimmingCharacters(in: .whitespaces).isEmpty {
                category = cat.trimmingCharacters(in: .whitespaces)
            } else {
                category = nil
            }

            items.append((name: trimmed, category: category))
        }

        previewItems = items
        if items.isEmpty {
            statusMessage = "Sheet has no valid items (expected names in column A)"
        } else {
            statusMessage = ""
        }
    }

    private func importItems() {
        for item in previewItems {
            store.addGroundTruthItem(
                to: session.id,
                name: item.name,
                category: item.category
            )
        }
        // Refresh session binding
        if let updated = store.sessions.first(where: { $0.id == session.id }) {
            session = updated
        }
        dismiss()
    }
}

// MARK: - Comparison View

struct ComparisonView: View {
    let session: ScanSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Summary table
                Section {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Pipeline")
                            .font(.caption.bold())
                            .frame(width: 90, alignment: .leading)
                        Text("Items")
                            .font(.caption.bold())
                            .frame(width: 40, alignment: .trailing)
                        Text("Match")
                            .font(.caption.bold())
                            .frame(width: 42, alignment: .trailing)
                        Text("Recall")
                            .font(.caption.bold())
                            .frame(width: 48, alignment: .trailing)
                        Text("Prec")
                            .font(.caption.bold())
                            .frame(width: 42, alignment: .trailing)
                        Text("Qual")
                            .font(.caption.bold())
                            .frame(width: 36, alignment: .trailing)
                        Text("Time")
                            .font(.caption.bold())
                            .frame(width: 42, alignment: .trailing)
                    }
                    .padding(.vertical, 2)

                    ForEach(session.pipelineRuns) { run in
                        HStack(spacing: 0) {
                            Text(shortName(run.pipeline))
                                .font(.caption)
                                .frame(width: 90, alignment: .leading)
                            Text("\(run.detectedItems.count)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                            Text("\(run.scores?.matchedCount ?? 0)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                            Text(run.scores?.recallPercent ?? "-")
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                                .foregroundColor(recallColor(run.scores?.recall ?? 0))
                            Text(run.scores?.precisionPercent ?? "-")
                                .font(.caption.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                            Text(String(format: "%.1f", run.scores?.avgNameQuality ?? 0))
                                .font(.caption.monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                            Text(String(format: "%.0fs", run.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Pipeline Comparison")
                }

                // Per-item drill-down
                if !session.groundTruth.items.isEmpty {
                    Section {
                        ForEach(session.groundTruth.items) { gtItem in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gtItem.name)
                                    .font(.subheadline.bold())

                                ForEach(session.pipelineRuns) { run in
                                    if let detail = run.scores?.matchDetails.first(where: {
                                        $0.groundTruthName == gtItem.name
                                    }) {
                                        HStack {
                                            Text(shortName(run.pipeline))
                                                .font(.caption2)
                                                .frame(width: 70, alignment: .leading)
                                                .foregroundColor(.secondary)
                                            matchBadge(detail.matchType)
                                            if let detected = detail.detectedName {
                                                Text(detected)
                                                    .font(.caption2)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Per-Item Results")
                    }
                }
            }
            .navigationTitle("Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func shortName(_ pipeline: DetectionPipeline) -> String {
        switch pipeline {
        case .yoloOnly: return "YOLO"
        case .yoloPlusOCR: return "YOLO+OCR"
        case .geminiStreaming: return "Gem.Stream"
        case .geminiMultiItem: return "Gem.Multi"
        case .geminiVideo: return "Gem.Video"
        }
    }

    private func recallColor(_ recall: Double) -> Color {
        if recall >= 0.7 { return .green }
        if recall >= 0.4 { return .orange }
        return .red
    }

    @ViewBuilder
    private func matchBadge(_ type: MatchType) -> some View {
        switch type {
        case .exact:
            Text("EXACT")
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.green.opacity(0.2))
                .foregroundColor(.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .substring:
            Text("SUB")
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.blue.opacity(0.2))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .fuzzy:
            Text("FUZZY")
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.orange.opacity(0.2))
                .foregroundColor(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .none:
            Text("MISS")
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.red.opacity(0.2))
                .foregroundColor(.red)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
