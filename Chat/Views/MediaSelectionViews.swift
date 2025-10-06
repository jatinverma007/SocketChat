//
//  MediaSelectionViews.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI
import PhotosUI

// MARK: - Upload Progress View
struct UploadProgressView: View {
    let progress: UploadProgress
    let onDismiss: () -> Void
    @State private var autoDismissTimer: Timer?
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                switch progress.status {
                case .preparing:
                    ProgressView()
                        .scaleEffect(0.8)
                case .uploading:
                    ProgressView()
                        .scaleEffect(0.8)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .frame(width: 20, height: 20)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Progress bar or status
                switch progress.status {
                case .preparing:
                    Text("Preparing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                case .uploading:
                    ProgressView(value: progress.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                    
                case .completed:
                    Text("Upload complete")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                case .failed:
                    Text(progress.error?.localizedDescription ?? "Upload failed")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            // Dismiss button
            if progress.status == .completed || progress.status == .failed {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onAppear {
            // Auto-dismiss after 3 seconds when upload completes successfully
            if progress.status == .completed {
                autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    onDismiss()
                }
            }
        }
        .onDisappear {
            // Cancel timer if view disappears
            autoDismissTimer?.invalidate()
            autoDismissTimer = nil
        }
    }
}

// MARK: - Image Picker View
struct ImagePickerView: UIViewControllerRepresentable {
    let mediaCaptureService: MediaCaptureService
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode
    
    init(mediaCaptureService: MediaCaptureService, sourceType: UIImagePickerController.SourceType = .photoLibrary) {
        self.mediaCaptureService = mediaCaptureService
        self.sourceType = sourceType
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.sourceType = sourceType
        
        // Set video quality for camera recording
        if sourceType == .camera {
            picker.videoQuality = .typeMedium
            picker.videoMaximumDuration = 60 // 1 minute max
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
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
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { 
                print("📎 Failed to convert image to JPEG data")
                return 
            }
            
            print("📎 Image selected: \(image.size), data size: \(imageData.count) bytes")
            
            let filename = parent.mediaCaptureService.generateFilename(for: .image)
            let selectedMedia = MediaCaptureService.SelectedMedia(
                type: .image,
                data: imageData,
                filename: filename,
                mimeType: "image/jpeg",
                thumbnail: image,
                size: image.size
            )
            
            print("📎 Created SelectedMedia with data size: \(selectedMedia.data.count) bytes")
            parent.mediaCaptureService.selectedMedia = selectedMedia
        }
        
        private func handleVideoSelection(_ videoURL: URL) {
            Task {
                do {
                    let videoData = try Data(contentsOf: videoURL)
                    let filename = parent.mediaCaptureService.generateFilename(for: .video)
                    
                    // Generate thumbnail
                    let thumbnail = generateVideoThumbnail(from: videoURL)
                    
                    // Get video duration
                    let asset = AVAsset(url: videoURL)
                    let duration = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(duration)
                    
                    // Determine MIME type based on file extension
                    let fileExtension = videoURL.pathExtension.lowercased()
                    let mimeType: String
                    switch fileExtension {
                    case "mov":
                        mimeType = "video/quicktime"
                    case "mp4":
                        mimeType = "video/mp4"
                    case "avi":
                        mimeType = "video/x-msvideo"
                    default:
                        mimeType = "video/mp4"
                    }
                    
                    let selectedMedia = MediaCaptureService.SelectedMedia(
                        type: .video,
                        data: videoData,
                        filename: filename,
                        mimeType: mimeType,
                        thumbnail: thumbnail,
                        duration: durationSeconds
                    )
                    
                    print("📎 Video selected: \(videoURL.lastPathComponent), size: \(videoData.count) bytes, duration: \(durationSeconds)s")
                    parent.mediaCaptureService.selectedMedia = selectedMedia
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
}

// MARK: - Document Picker View
struct DocumentPickerView: UIViewControllerRepresentable {
    let onDocumentSelected: (URL) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.pdf,
            UTType.text,
            UTType.rtf,
            UTType.plainText,
            UTType("org.openxmlformats.wordprocessingml.document")!, // .docx
            UTType("com.microsoft.word.doc")! // .doc
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing the security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let documentData = try Data(contentsOf: url)
                print("✅ Document selected successfully: \(url.lastPathComponent)")
                
                // Call the closure with the selected document URL
                parent.onDocumentSelected(url)
            } catch {
                print("❌ Error handling document selection: \(error)")
                print("❌ File path: \(url.path)")
                print("❌ File exists: \(FileManager.default.fileExists(atPath: url.path))")
                print("❌ Is readable: \(FileManager.default.isReadableFile(atPath: url.path))")
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Handle cancellation
        }
        
        private func getMimeType(for url: URL) -> String {
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
}

// MARK: - Audio Recorder View
struct AudioRecorderView: View {
    let mediaCaptureService: MediaCaptureService
    @Environment(\.presentationMode) var presentationMode
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Recording visualization
                VStack(spacing: 20) {
                    if isRecording {
                        // Animated waveform or circle
                        Circle()
                            .stroke(Color.red, lineWidth: 4)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                            .overlay(
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundColor(.red)
                            )
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "mic")
                                    .font(.title)
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    // Duration display
                    Text(formatDuration(recordingDuration))
                        .font(.title)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 40) {
                    // Cancel button
                    Button(action: cancelRecording) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                    }
                    .disabled(isRecording)
                    
                    // Record/Stop button
                    Button(action: toggleRecording) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 70))
                            .foregroundColor(isRecording ? .red : .red)
                    }
                    
                    // Send button
                    Button(action: sendRecording) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(recordingDuration > 0 && !isRecording ? .green : .gray)
                    }
                    .disabled(isRecording || recordingDuration == 0)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Record Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        do {
            try mediaCaptureService.startAudioRecording()
            isRecording = true
            recordingDuration = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        mediaCaptureService.stopAudioRecording()
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
    
    private func cancelRecording() {
        if isRecording {
            mediaCaptureService.cancelAudioRecording()
            isRecording = false
            recordingDuration = 0
            timer?.invalidate()
            timer = nil
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func sendRecording() {
        // The MediaCaptureService will handle setting the selectedMedia
        // when recording finishes
        presentationMode.wrappedValue.dismiss()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}
