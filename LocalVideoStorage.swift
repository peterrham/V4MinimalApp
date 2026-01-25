//
//  LocalVideoStorage.swift
//  V4MinimalApp
//
//  Simple local video storage for testing without Google Drive
//

import Foundation
import Photos
import UIKit

/// Simple service for saving videos locally while you set up Google Drive
class LocalVideoStorage {
    
    enum StorageError: Error, LocalizedError {
        case permissionDenied
        case saveFailed(String)
        case iCloudNotAvailable
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photo library access denied"
            case .saveFailed(let message):
                return "Failed to save video: \(message)"
            case .iCloudNotAvailable:
                return "iCloud Drive is not available"
            }
        }
    }
    
    // MARK: - Photos Library
    
    /// Save video to Photos Library
    /// This is the easiest way to save videos and users can access them immediately
    static func saveToPhotos(_ videoURL: URL) async throws {
        // Check authorization
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .notDetermined:
            // Request permission
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized else {
                throw StorageError.permissionDenied
            }
            
        case .restricted, .denied:
            throw StorageError.permissionDenied
            
        case .authorized, .limited:
            break
            
        @unknown default:
            throw StorageError.permissionDenied
        }
        
        // Save to photos
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }
            
            appBootLog.infoWithContext("✅ Video saved to Photos Library")
            
            // Optionally delete the temporary file
            try? FileManager.default.removeItem(at: videoURL)
            
        } catch {
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - iCloud Drive
    
    /// Save video to iCloud Drive
    /// Videos will sync across user's devices
    static func saveToiCloud(_ videoURL: URL, folderName: String = "InventoryVideos") async throws {
        // Get iCloud container URL
        guard let iCloudURL = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) else {
            throw StorageError.iCloudNotAvailable
        }
        
        // Create folder if needed
        let folderURL = iCloudURL.appendingPathComponent(folderName)
        
        do {
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Create unique filename
            let timestamp = Date().timeIntervalSince1970
            let fileName = "inventory_\(Int(timestamp)).mov"
            let destinationURL = folderURL.appendingPathComponent(fileName)
            
            // Copy file to iCloud
            try FileManager.default.copyItem(at: videoURL, to: destinationURL)
            
            appBootLog.infoWithContext("✅ Video saved to iCloud Drive: \(destinationURL.path)")
            
            // Delete temporary file
            try? FileManager.default.removeItem(at: videoURL)
            
        } catch {
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - App Documents Directory
    
    /// Save video to app's documents directory
    /// Videos persist but are only accessible within the app
    static func saveToDocuments(_ videoURL: URL) throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosURL = documentsURL.appendingPathComponent("Videos")
        
        // Create Videos directory if needed
        try FileManager.default.createDirectory(
            at: videosURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Create unique filename
        let timestamp = Date().timeIntervalSince1970
        let fileName = "inventory_\(Int(timestamp)).mov"
        let destinationURL = videosURL.appendingPathComponent(fileName)
        
        // Move or copy file
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.moveItem(at: videoURL, to: destinationURL)
        
        appBootLog.infoWithContext("✅ Video saved to documents: \(destinationURL.path)")
        
        return destinationURL
    }
    
    // MARK: - List Saved Videos
    
    /// Get list of videos saved in documents directory
    static func listSavedVideos() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosURL = documentsURL.appendingPathComponent("Videos")
        
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: videosURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return urls.filter { $0.pathExtension == "mov" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
    }
    
    // MARK: - Delete Video
    
    static func deleteVideo(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        appBootLog.infoWithContext("🗑️ Deleted video: \(url.lastPathComponent)")
    }
}

// MARK: - Quick Use Extension

extension LocalVideoStorage {
    
    /// Quick save with automatic fallback
    /// Tries Photos first, then Documents as fallback
    static func quickSave(_ videoURL: URL) async {
        do {
            // Try Photos first
            try await saveToPhotos(videoURL)
        } catch {
            appBootLog.errorWithContext("Failed to save to Photos: \(error.localizedDescription)")
            
            // Fallback to Documents
            do {
                _ = try saveToDocuments(videoURL)
            } catch {
                appBootLog.errorWithContext("Failed to save to Documents: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Usage Examples

/*
 
 // Example 1: Save to Photos (recommended for users)
 Task {
     do {
         try await LocalVideoStorage.saveToPhotos(videoURL)
         print("Saved to Photos!")
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Example 2: Save to iCloud Drive
 Task {
     do {
         try await LocalVideoStorage.saveToiCloud(videoURL)
         print("Saved to iCloud!")
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Example 3: Save to app documents
 do {
     let savedURL = try LocalVideoStorage.saveToDocuments(videoURL)
     print("Saved to: \(savedURL)")
 } catch {
     print("Error: \(error)")
 }
 
 // Example 4: Quick save with automatic fallback
 Task {
     await LocalVideoStorage.quickSave(videoURL)
 }
 
 // Example 5: List all saved videos
 let videos = LocalVideoStorage.listSavedVideos()
 for video in videos {
     print("Video: \(video.lastPathComponent)")
 }
 
 */
