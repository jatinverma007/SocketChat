//
//  MediaCaptureService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import UIKit
import AVFoundation
import Photos
import UniformTypeIdentifiers

// MARK: - Media Capture Service
class MediaCaptureService: NSObject, ObservableObject {
    static let shared = MediaCaptureService()
    
    @Published var selectedMedia: SelectedMedia?
    @Published var isRecordingAudio = false
    @Published var audioRecordingDuration: TimeInterval = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var audioTimer: Timer?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Media Selection Types
    enum MediaType {
        case camera
        case photoLibrary
        case documentPicker
        case audioRecording
    }
    
    struct SelectedMedia: Equatable {
        let type: Attachment.AttachmentType
        let data: Data
        let filename: String
        let mimeType: String
        let thumbnail: UIImage?
        let duration: TimeInterval?
        let size: CGSize?
        
        init(type: Attachment.AttachmentType, data: Data, filename: String, mimeType: String, thumbnail: UIImage? = nil, duration: TimeInterval? = nil, size: CGSize? = nil) {
            self.type = type
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
            self.thumbnail = thumbnail
            self.duration = duration
            self.size = size
        }
        
        // Equatable conformance
        static func == (lhs: SelectedMedia, rhs: SelectedMedia) -> Bool {
            return lhs.type == rhs.type &&
                   lhs.filename == rhs.filename &&
                   lhs.mimeType == rhs.mimeType &&
                   lhs.duration == rhs.duration &&
                   lhs.size == rhs.size &&
                   lhs.data == rhs.data
            // Note: UIImage comparison is complex, so we compare other properties
            // In practice, this should be sufficient for onChange detection
        }
    }
    
    // MARK: - Image Capture from Camera
    func captureImageFromCamera() -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = true
        picker.mediaTypes = ["public.image"]
        return picker
    }
    
    // MARK: - Image Selection from Photo Library
    func selectImageFromLibrary() -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        picker.mediaTypes = ["public.image"]
        return picker
    }
    
    // MARK: - Video Capture from Camera
    func captureVideoFromCamera() -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = true
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 60 // 1 minute max
        picker.videoQuality = .typeMedium
        return picker
    }
    
    // MARK: - Video Selection from Photo Library
    func selectVideoFromLibrary() -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        picker.mediaTypes = ["public.movie"]
        return picker
    }
    
    // MARK: - Document Picker
    func selectDocument() -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.pdf,
            UTType.text,
            UTType.rtf,
            UTType.plainText,
            UTType("org.openxmlformats.wordprocessingml.document")!, // .docx
            UTType("com.microsoft.word.doc")! // .doc
        ])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        return picker
    }
    
    // MARK: - Audio Recording
    func startAudioRecording() throws {
        guard !isRecordingAudio else { return }
        
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        isRecordingAudio = true
        audioRecordingDuration = 0
        
        // Start timer for duration tracking
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.audioRecordingDuration += 0.1
        }
    }
    
    func stopAudioRecording() {
        guard isRecordingAudio else { return }
        
        audioRecorder?.stop()
        audioTimer?.invalidate()
        audioTimer = nil
        isRecordingAudio = false
        
        try? audioSession.setActive(false)
    }
    
    func cancelAudioRecording() {
        guard isRecordingAudio else { return }
        
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        audioTimer?.invalidate()
        audioTimer = nil
        isRecordingAudio = false
        audioRecordingDuration = 0
        
        try? audioSession.setActive(false)
    }
    
    // MARK: - Setup Audio Session
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(false)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - File Type Validation
    func isValidFileType(_ filename: String, mimeType: String) -> Bool {
        let fileExtension = filename.lowercased().components(separatedBy: ".").last ?? ""
        
        let allSupportedTypes = ServerConfig.supportedImageTypes +
                               ServerConfig.supportedVideoTypes +
                               ServerConfig.supportedAudioTypes +
                               ServerConfig.supportedDocumentTypes
        
        return allSupportedTypes.contains(fileExtension)
    }
    
    // MARK: - Generate Filename
    func generateFilename(for type: Attachment.AttachmentType, originalFilename: String? = nil) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid = UUID().uuidString.prefix(8)
        
        if let original = originalFilename {
            let components = original.components(separatedBy: ".")
            if components.count > 1 {
                let fileExtension = components.last!
                return "\(type.rawValue)_\(timestamp)_\(uuid).\(fileExtension)"
            }
        }
        
        switch type {
        case .image:
            return "image_\(timestamp)_\(uuid).jpg"
        case .video:
            return "video_\(timestamp)_\(uuid).mp4"
        case .audio:
            return "audio_\(timestamp)_\(uuid).m4a"
        case .document, .file:
            return "document_\(timestamp)_\(uuid).pdf"
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension MediaCaptureService: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
            handleImageSelection(image)
        } else if let videoURL = info[.mediaURL] as? URL {
            handleVideoSelection(videoURL)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    private func handleImageSelection(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        
        let filename = generateFilename(for: .image)
        let selectedMedia = SelectedMedia(
            type: .image,
            data: imageData,
            filename: filename,
            mimeType: "image/jpeg",
            thumbnail: image,
            size: image.size
        )
        
        DispatchQueue.main.async {
            self.selectedMedia = selectedMedia
        }
    }
    
    private func handleVideoSelection(_ videoURL: URL) {
        Task {
            do {
                let videoData = try Data(contentsOf: videoURL)
                let filename = generateFilename(for: .video)
                
                // Generate thumbnail
                let thumbnail = generateVideoThumbnail(from: videoURL)
                
                // Get video duration
                let asset = AVAsset(url: videoURL)
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                
                let selectedMedia = SelectedMedia(
                    type: .video,
                    data: videoData,
                    filename: filename,
                    mimeType: "video/mp4",
                    thumbnail: thumbnail,
                    duration: durationSeconds
                )
                
                DispatchQueue.main.async {
                    self.selectedMedia = selectedMedia
                }
            } catch {
                print("Error handling video selection: \(error)")
            }
        }
    }
    
    private func generateVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 300, height: 300)
        
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

// MARK: - UIDocumentPickerDelegate
extension MediaCaptureService: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        do {
            let documentData = try Data(contentsOf: url)
            let filename = generateFilename(for: .document, originalFilename: url.lastPathComponent)
            
            let mimeType = getMimeType(for: url)
            
            let selectedMedia = SelectedMedia(
                type: .document,
                data: documentData,
                filename: filename,
                mimeType: mimeType
            )
            
            DispatchQueue.main.async {
                self.selectedMedia = selectedMedia
            }
        } catch {
            print("Error handling document selection: \(error)")
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Handle cancellation
    }
    
    func getMimeType(for url: URL) -> String {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension MediaCaptureService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            do {
                let audioData = try Data(contentsOf: recorder.url)
                let filename = generateFilename(for: .audio)
                
                let selectedMedia = SelectedMedia(
                    type: .audio,
                    data: audioData,
                    filename: filename,
                    mimeType: "audio/mp4",
                    duration: audioRecordingDuration
                )
                
                DispatchQueue.main.async {
                    self.selectedMedia = selectedMedia
                }
            } catch {
                print("Error handling audio recording: \(error)")
            }
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: recorder.url)
    }
}
