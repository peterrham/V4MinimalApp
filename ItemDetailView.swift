//
//  ItemDetailView.swift
//  V4MinimalApp
//
//  Home Inventory - Item Detail View
//

import SwiftUI

struct ItemDetailView: View {
    let item: InventoryItem
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Photo Gallery
                if !item.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.m) {
                            ForEach(item.photos, id: \.self) { photo in
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
                        Text(item.name)
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
                                         String(format: "$%.2f", item.purchasePrice!) :
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
                                        
                                        Text(String(format: "$%.2f", estimate))
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
                    if item.brand != nil || !item.notes.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                                Label("Details", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.primary)
                                
                                if let brand = item.brand {
                                    DetailRow(label: "Brand", value: brand)
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
