//
//  FileUploadService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Upload Progress Model
struct UploadProgress {
    let id: String
    let filename: String
    let progress: Double
    let status: UploadStatus
    let error: Error?
    
    enum UploadStatus {
        case preparing
        case uploading
        case completed
        case failed
    }
}

// MARK: - Upload Result Model
struct UploadResult {
    let success: Bool
    let filename: String?
    let url: String?
    let error: Error?
    let attachment: Attachment?
}

// MARK: - File Upload Service
class FileUploadService: ObservableObject {
    static let shared = FileUploadService()
    
    @Published var uploadProgress: [String: UploadProgress] = [:]
    private let session: URLSession
    private let keychainService = KeychainService.shared
    
    private init() {
        // Create URLSession with extended timeout configuration for file uploads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minutes for individual requests (files can be large)
        config.timeoutIntervalForResource = 300 // 5 minutes for entire resource
        config.waitsForConnectivity = true      // Wait for network connectivity
        config.allowsCellularAccess = true      // Allow cellular connections
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Upload File
    func uploadFile(_ fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        print("📎 FileUploadService.uploadFile called")
        print("📎   - Filename: \(filename)")
        print("📎   - MimeType: \(mimeType)")
        print("📎   - Data size: \(fileData.count) bytes")
        
        let uploadId = UUID().uuidString
        
        // Validate file size
        guard fileData.count <= ServerConfig.maxFileSize else {
            print("📎 ERROR: File too large (\(fileData.count) bytes > \(ServerConfig.maxFileSize))")
            let error = UploadError.fileTooLarge(ServerConfig.maxFileSize)
            updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
            throw error
        }
        
        // Validate file type
        guard isValidFileType(filename: filename, mimeType: mimeType) else {
            let error = UploadError.unsupportedFileType
            updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
            throw error
        }
        
        guard let token = keychainService.getToken() else {
            print("📎 ERROR: No authentication token found!")
            let error = UploadError.authenticationRequired
            updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
            throw error
        }
        
        print("📎 Authentication token found, proceeding with upload...")
        
        // Update progress to preparing
        updateProgress(uploadId: uploadId, filename: filename, progress: 0.1, status: .preparing, error: nil)
        
        do {
            // Create multipart form data
            let boundary = UUID().uuidString
            var request = URLRequest(url: URL(string: ServerConfig.uploadFile)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            // Build multipart body
            var body = Data()
            
            // Add file data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            // Update progress to uploading
            updateProgress(uploadId: uploadId, filename: filename, progress: 0.2, status: .uploading, error: nil)
            
            // Perform upload with progress tracking
            print("📎 Uploading to: \(ServerConfig.uploadFile)")
            print("📎 Request body size: \(body.count) bytes")
            
            let (responseData, response) = try await session.data(for: request)
            
            print("📎 Upload response received")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("📎 ERROR: Invalid response type")
                let error = UploadError.invalidResponse
                updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
                throw error
            }
            
            print("📎 HTTP Status Code: \(httpResponse.statusCode)")
            print("📎 Response data size: \(responseData.count) bytes")
            
            guard httpResponse.statusCode == 200 else {
                print("📎 ERROR: Server returned status \(httpResponse.statusCode)")
                if let responseString = String(data: responseData, encoding: .utf8) {
                    print("📎 Error response: \(responseString)")
                }
                let error = UploadError.serverError(httpResponse.statusCode)
                updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
                throw error
            }
            
            // Parse response
            print("📎 Parsing upload response...")
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("📎 Response JSON: \(responseString)")
            }
            
            let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)
            print("📎 Upload response parsed successfully: \(uploadResponse.filename)")
            print("📎 Server returned file_url: '\(uploadResponse.file_url)'")
            
            // Create attachment - ensure we have a full URL with fallbacks
            let fileURL: String
            if uploadResponse.file_url.hasPrefix("http") {
                // Already a full URL
                fileURL = uploadResponse.file_url
                print("📎 Using full URL as-is: \(fileURL)")
            } else if !uploadResponse.file_url.isEmpty {
                // Relative URL, make it absolute
                fileURL = uploadResponse.file_url.hasPrefix("/") ? 
                    "\(ServerConfig.httpBaseURL)\(uploadResponse.file_url)" :
                    "\(ServerConfig.httpBaseURL)/\(uploadResponse.file_url)"
                print("📎 Constructed URL from relative: \(fileURL)")
            } else {
                // Fallback URL if file_url is empty
                fileURL = "\(ServerConfig.httpBaseURL)/api/files/\(uploadResponse.filename)"
                print("📎 Using fallback URL: \(fileURL)")
            }
            
            let attachment = Attachment(
                type: getAttachmentType(from: uploadResponse.mime_type),
                filename: uploadResponse.filename.isEmpty ? "unknown_file" : uploadResponse.filename,
                url: fileURL,
                size: uploadResponse.file_size > 0 ? uploadResponse.file_size : nil,
                mimeType: uploadResponse.mime_type.isEmpty ? "application/octet-stream" : uploadResponse.mime_type
            )
            
            print("📎 Created attachment:")
            print("📎   - Type: \(attachment.type.rawValue)")
            print("📎   - Filename: \(attachment.filename)")
            print("📎   - URL: \(attachment.url ?? "nil")")
            print("📎   - Size: \(attachment.size ?? 0)")
            print("📎   - MIME: \(attachment.mimeType ?? "nil")")
            
            // Update progress to completed
            updateProgress(uploadId: uploadId, filename: filename, progress: 1.0, status: .completed, error: nil)
            
            // Auto-remove completed upload after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.removeProgress(uploadId: uploadId)
            }
            
            return UploadResult(
                success: true,
                filename: uploadResponse.filename,
                url: uploadResponse.file_url,
                error: nil,
                attachment: attachment
            )
            
        } catch {
            updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
            throw error
        }
    }
    
    // MARK: - Upload Image with Compression
    func uploadImage(_ image: UIImage, filename: String, quality: CGFloat = 0.8) async throws -> UploadResult {
        let uploadId = UUID().uuidString
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: quality) else {
            let error = UploadError.imageProcessingFailed
            updateProgress(uploadId: uploadId, filename: filename, progress: 0, status: .failed, error: error)
            throw error
        }
        
        return try await uploadFile(imageData, filename: filename, mimeType: "image/jpeg")
    }
    
    // MARK: - Upload Video with Compression
    func uploadVideo(from url: URL, filename: String) async throws -> UploadResult {
        let uploadId = UUID().uuidString
        
        // Compress video if needed
        let compressedURL = try await compressVideo(inputURL: url)
        let videoData = try Data(contentsOf: compressedURL)
        
        // Clean up temporary file
        try? FileManager.default.removeItem(at: compressedURL)
        
        return try await uploadFile(videoData, filename: filename, mimeType: "video/mp4")
    }
    
    // MARK: - Progress Tracking
    private func updateProgress(uploadId: String, filename: String, progress: Double, status: UploadProgress.UploadStatus, error: Error?) {
        DispatchQueue.main.async {
            self.uploadProgress[uploadId] = UploadProgress(
                id: uploadId,
                filename: filename,
                progress: progress,
                status: status,
                error: error
            )
        }
    }
    
    func removeProgress(uploadId: String) {
        DispatchQueue.main.async {
            self.uploadProgress.removeValue(forKey: uploadId)
        }
    }
    
    // MARK: - File Validation
    private func isValidFileType(filename: String, mimeType: String) -> Bool {
        let fileExtension = filename.lowercased().components(separatedBy: ".").last ?? ""
        
        let allSupportedTypes = ServerConfig.supportedImageTypes +
                               ServerConfig.supportedVideoTypes +
                               ServerConfig.supportedAudioTypes +
                               ServerConfig.supportedDocumentTypes
        
        return allSupportedTypes.contains(fileExtension)
    }
    
    private func getAttachmentType(from mimeType: String) -> Attachment.AttachmentType {
        if mimeType.hasPrefix("image/") {
            return .image
        } else if mimeType.hasPrefix("video/") {
            return .video
        } else if mimeType.hasPrefix("audio/") {
            return .audio
        } else {
            return .document
        }
    }
    
    // MARK: - Video Compression
    private func compressVideo(inputURL: URL) async throws -> URL {
        let asset = AVAsset(url: inputURL)
        
        // Check if already compressed enough
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw UploadError.videoProcessingFailed
        }
        
        let size = track.naturalSize
        let estimatedFileSize = try await estimateVideoFileSize(asset: asset)
        
        // If file is already small enough, return original
        if estimatedFileSize < ServerConfig.maxFileSize / 2 {
            return inputURL
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        // Calculate compression ratio and choose appropriate preset
        let targetSize = min(size.width, size.height)
        let preset: String
        if targetSize > 720 {
            preset = AVAssetExportPresetMediumQuality
        } else {
            preset = AVAssetExportPresetLowQuality
        }
        
        // Create export session with the chosen preset
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw UploadError.videoProcessingFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return outputURL
        } else {
            throw UploadError.videoProcessingFailed
        }
    }
    
    private func estimateVideoFileSize(asset: AVAsset) async throws -> Int64 {
        guard let track = asset.tracks(withMediaType: .video).first else {
            return 0
        }
        
        let duration = try await asset.load(.duration)
        let bitRate = try await track.load(.estimatedDataRate)
        
        return Int64(CMTimeGetSeconds(duration) * Double(bitRate) / 8)
    }
}

// MARK: - Upload Response Model
private struct UploadResponse: Codable {
    let file_url: String
    let filename: String
    let file_size: Int
    let mime_type: String
    let message: String
}

// MARK: - Upload Errors
enum UploadError: Error, LocalizedError {
    case fileTooLarge(Int)
    case unsupportedFileType
    case authenticationRequired
    case invalidResponse
    case serverError(Int)
    case imageProcessingFailed
    case videoProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maxSize):
            return "File size exceeds the maximum allowed size of \(maxSize / (1024 * 1024))MB"
        case .unsupportedFileType:
            return "This file type is not supported"
        case .authenticationRequired:
            return "Authentication required to upload files"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .videoProcessingFailed:
            return "Failed to process video"
        }
    }
}

// MARK: - File Size Formatter
extension FileUploadService {
    static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
