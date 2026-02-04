//
//  ItemDetailView.swift
//  V4MinimalApp
//
//  Home Inventory - Item Detail View
//

import SwiftUI
import UIKit

struct ItemDetailView: View {
    let item: InventoryItem
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @State private var selectedPhoto: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Photo Gallery (tap to zoom)
                if !item.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.m) {
                            ForEach(item.photos, id: \.self) { photo in
                                if let uiImage = UIImage(contentsOfFile: InventoryStore.photoURL(for: photo).path) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 280, height: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                                        .onTapGesture { selectedPhoto = photo }
                                } else {
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                        .fill(item.category.color.opacity(0.1))
                                        .frame(width: 280, height: 280)
                                        .overlay {
                                            Image(systemName: item.category.icon)
                                                .font(.system(size: 80))
                                                .foregroundStyle(item.category.color.opacity(0.3))
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .fill(item.category.color.opacity(0.1))
                            .frame(height: 280)

                        Image(systemName: item.category.icon)
                            .font(.system(size: 100))
                            .foregroundStyle(item.category.color.opacity(0.3))
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                }
                
                // Item Information
                VStack(spacing: AppTheme.Spacing.l) {
                    // Name and Category
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text(item.displayTitleWithQuantity)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: AppTheme.Spacing.s) {
                            Label(item.category.rawValue, systemImage: item.category.icon)
                                .font(.callout)
                                .padding(.horizontal, AppTheme.Spacing.m)
                                .padding(.vertical, AppTheme.Spacing.s)
                                .background(item.category.color.opacity(0.15))
                                .foregroundColor(item.category.color)
                                .cornerRadius(8)

                            Label(item.room, systemImage: "door.left.hand.closed")
                                .font(.callout)
                                .padding(.horizontal, AppTheme.Spacing.m)
                                .padding(.vertical, AppTheme.Spacing.s)
                                .background(AppTheme.Colors.surface)
                                .cornerRadius(8)

                            if item.isEmptyBox {
                                Label("Empty Box", systemImage: "shippingbox")
                                    .font(.callout)
                                    .padding(.horizontal, AppTheme.Spacing.m)
                                    .padding(.vertical, AppTheme.Spacing.s)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.l)
                    
                    // Value Section
                    Card {
                        VStack(spacing: AppTheme.Spacing.m) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Purchase Price")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text(item.purchasePrice != nil ?
                                         "$\(InventoryItem.dollarFormatter.string(from: NSNumber(value: item.purchasePrice!)) ?? "0")" :
                                         "Not set")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(AppTheme.Colors.success)
                                }
                                
                                Spacer()
                                
                                if let estimate = item.estimatedValue {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Estimated")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text("$\(InventoryItem.dollarFormatter.string(from: NSNumber(value: estimate)) ?? "0")")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            if let purchaseDate = item.purchaseDate {
                                Divider()
                                
                                HStack {
                                    Label("Purchased", systemImage: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Text(purchaseDate, style: .date)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                    
                    // Details Section
                    if item.brand != nil || !item.notes.isEmpty || item.upc != nil || item.quantity > 1 {
                        Card {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                                Label("Details", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.primary)

                                if let brand = item.brand {
                                    DetailRow(label: "Brand", value: brand)
                                }

                                if item.quantity > 1 {
                                    DetailRow(label: "Quantity", value: "\(item.quantity)")
                                }

                                if let upc = item.upc {
                                    DetailRow(label: "UPC / Barcode", value: upc)
                                }

                                if !item.notes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Notes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(item.notes)
                                            .font(.callout)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                    }
                    
                    // Voice Transcripts
                    if !item.voiceTranscripts.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                                Label("Voice Notes", systemImage: "waveform")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.primary)
                                
                                ForEach(item.voiceTranscripts, id: \.self) { transcript in
                                    HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
                                        Image(systemName: "quote.opening")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        
                                        Text(transcript)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(AppTheme.Spacing.m)
                                    .background(AppTheme.Colors.background)
                                    .cornerRadius(8)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                    }
                    
                    // Action Buttons
                    VStack(spacing: AppTheme.Spacing.m) {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit Item", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.m)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Button {
                            // Share action
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.m)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete Item", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.m)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .background(AppTheme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Delete action
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
        }
        .sheet(isPresented: $isEditing) {
            ItemEditView(item: item)
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            ZoomablePhotoView(photoFilename: photo, item: item)
        }
    }
}

// MARK: - Identifiable wrapper for String
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Zoomable Photo View (3 modes)

enum PhotoViewMode: String, CaseIterable {
    case item = "Item"
    case frameAllBoxes = "All Boxes"
    case frameWithBox = "Box"
    case frame = "Frame"
}

struct ZoomablePhotoView: View {
    let photoFilename: String
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewMode: PhotoViewMode = .item

    /// Whether this item has a source frame to show
    private var hasFrame: Bool {
        item.sourceFramePhoto != nil && item.boundingBox != nil
    }

    private var frameImage: UIImage? {
        guard let frameFile = item.sourceFramePhoto else { return nil }
        return UIImage(contentsOfFile: InventoryStore.photoURL(for: frameFile).path)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                switch viewMode {
                case .item:
                    itemView
                case .frameAllBoxes:
                    frameView(showAllBoxes: true)
                case .frameWithBox:
                    frameView(showAllBoxes: false)
                case .frame:
                    frameView(showAllBoxes: nil)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = lastScale * value.magnification
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 0.5 {
                            withAnimation {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 3.0
                        lastScale = 3.0
                    }
                }
            }

            // Controls overlay
            VStack {
                HStack {
                    // Mode picker (only when frame is available)
                    if hasFrame {
                        Picker("View", selection: $viewMode) {
                            ForEach(PhotoViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        .padding(.leading)
                        .onChange(of: viewMode) { _, _ in
                            // Reset zoom when switching modes
                            withAnimation {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()

                // Item name label at bottom
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Item view (cropped photo)

    @ViewBuilder
    private var itemView: some View {
        if let uiImage = UIImage(contentsOfFile: InventoryStore.photoURL(for: photoFilename).path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    // MARK: - Frame view
    // showAllBoxes: true = all items' boxes, false = just this item's box, nil = no boxes

    @ViewBuilder
    private func frameView(showAllBoxes: Bool?) -> some View {
        if let uiImage = frameImage {
            GeometryReader { geo in
                let imageSize = uiImage.size
                let fitScale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                let displayW = imageSize.width * fitScale
                let displayH = imageSize.height * fitScale

                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    if let showAll = showAllBoxes {
                        // This item's box (yellow, always shown when boxes enabled)
                        if let box = item.boundingBox {
                            boxOverlay(box: box, name: item.name, color: .yellow, lineWidth: 3, displayW: displayW, displayH: displayH)
                        }

                        // Sibling boxes (green, only in "All Boxes" mode)
                        if showAll, let siblings = item.frameSiblings {
                            ForEach(Array(siblings.enumerated()), id: \.offset) { _, sibling in
                                boxOverlay(box: sibling.boundingBox, name: sibling.name, color: .green, lineWidth: 2, displayW: displayW, displayH: displayH)
                            }
                        }
                    }
                }
                .frame(width: displayW, height: displayH)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        } else {
            itemView
        }
    }

    @ViewBuilder
    private func boxOverlay(box: CodableBoundingBox, name: String, color: Color, lineWidth: CGFloat, displayW: CGFloat, displayH: CGFloat) -> some View {
        let x = CGFloat(box.xMin) * displayW
        let y = CGFloat(box.yMin) * displayH
        let w = CGFloat(box.xMax - box.xMin) * displayW
        let h = CGFloat(box.yMax - box.yMin) * displayH

        Rectangle()
            .stroke(color, lineWidth: lineWidth)
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)

        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.85))
            .cornerRadius(3)
            .fixedSize()
            .position(x: x + w / 2, y: max(10, y - 12))
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.callout)
        }
    }
}

// MARK: - Item Edit View (Placeholder)

struct ItemEditView: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    Text(item.name)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(item: InventoryItem.sampleItems[0])
    }
}
