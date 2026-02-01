//
//  EvaluationView.swift
//  V4MinimalApp
//
//  Scan session evaluation harness UI
//

import SwiftUI
import AVFoundation
import PhotosUI

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
    @State private var selectedPipelines: Set<DetectionPipeline> = [.yoloOnly]
    @State private var selectedRun: PipelineRunResult?

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

            ForEach(store.sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    HStack {
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
            // Video info
            HStack {
                Label("Video", systemImage: "film")
                Spacer()
                Text(session.videoFileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

            // Pipeline selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipelines")
                    .font(.subheadline)
                ForEach(DetectionPipeline.allCases) { pipeline in
                    Button {
                        if selectedPipelines.contains(pipeline) {
                            selectedPipelines.remove(pipeline)
                        } else {
                            selectedPipelines.insert(pipeline)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedPipelines.contains(pipeline)
                                  ? "checkmark.square.fill" : "square")
                                .foregroundColor(selectedPipelines.contains(pipeline) ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(pipeline.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(pipeline.isOnDevice ? "On-device" : "API")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
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

            ForEach(session.pipelineRuns) { run in
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

    private func runSelectedPipelines(_ session: ScanSession) async {
        let videoURL = store.videoURL(for: session)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            runner.statusMessage = "Video file not found"
            return
        }

        for pipeline in selectedPipelines.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let result = await runner.runPipeline(
                pipeline,
                videoURL: videoURL,
                sessionId: session.id,
                intervalSeconds: frameInterval,
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
                    LabeledContent("Items Detected", value: "\(run.detectedItems.count)")
                    LabeledContent("Frames Processed", value: "\(run.framesProcessed)")
                    LabeledContent("Duration", value: String(format: "%.1fs", run.durationSeconds))
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

    var body: some View {
        NavigationStack {
            List {
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

                    if !session.groundTruth.items.isEmpty {
                        TextField("Category (optional)", text: $newItemCategory)
                            .font(.caption)
                    }
                } header: {
                    Text("Add Item")
                }

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
        }
    }

    private func refreshSession() {
        if let updated = store.sessions.first(where: { $0.id == session.id }) {
            session = updated
        }
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
