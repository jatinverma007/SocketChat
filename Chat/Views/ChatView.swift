//
//  ChatView.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI
import PhotosUI

struct ChatView: View {
    let room: ChatRoom
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var messageText = ""
    @State private var typingTimer: Timer?
    @State private var isTyping = false
    @State private var showingMediaPicker = false
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var showingAudioRecorder = false
    @State private var showingFullScreenImage = false
    @State private var showingVideoPlayer = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @StateObject private var mediaCaptureService = MediaCaptureService.shared
    @StateObject private var fileUploadService = FileUploadService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Bar - Only show when there's a persistent error
            if let connectionError = chatViewModel.connectionError, !chatViewModel.isConnected {
                HStack {
                    Text("Connection Error")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
            }
            
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if chatViewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading messages...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                        
                        ForEach(chatViewModel.messages) { message in
                            EnhancedMessageBubbleView(
                                message: message,
                                isFromCurrentUser: chatViewModel.isMessageFromCurrentUser(message),
                                onReactionSelected: { messageId, reactionType in
                                    print("🔖 ChatView: Reaction selected callback - messageId: \(messageId), reactionType: \(reactionType.rawValue)")
                                    Task {
                                        await chatViewModel.addReaction(to: messageId, reactionType: reactionType)
                                    }
                                },
                                onReactionRemoved: { messageId in
                                    print("🔖 ChatView: Reaction removed callback - messageId: \(messageId)")
                                    Task {
                                        await chatViewModel.removeReaction(from: messageId)
                                    }
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: chatViewModel.messages.count) { _ in
                    if let lastMessage = chatViewModel.messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
                        }
                    }
                }
            }
            
            // Typing Indicator
            if !chatViewModel.typingUsers.isEmpty {
                HStack {
                    Text(typingIndicatorText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: chatViewModel.typingUsers)
                .onAppear {
                    print("👀 UI: Typing indicator showing: \(chatViewModel.typingUsers)")
                }
            }
            
            // Upload Progress Indicators
            if !fileUploadService.uploadProgress.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(fileUploadService.uploadProgress.values), id: \.id) { progress in
                        UploadProgressView(progress: progress) {
                            fileUploadService.removeProgress(uploadId: progress.id)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Input Bar
            HStack(spacing: 12) {
                // Media Attachment Button
                Button(action: {
                    showingMediaPicker = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                    .onChange(of: messageText) { newValue in
                        handleTextChange(newValue)
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(18)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separator)),
                alignment: .top
            )
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            chatViewModel.joinRoom(room)
        }
        .onDisappear {
            // Don't disconnect WebSocket when navigating back - keep connection alive
            // Only clear the current room to stop processing messages for this room
            chatViewModel.leaveRoom()
        }
        .actionSheet(isPresented: $showingMediaPicker) {
            ActionSheet(
                title: Text("Select Media"),
                message: Text("Choose what you want to share"),
                buttons: [
                    .default(Text("📷 Camera")) {
                        imagePickerSourceType = .camera
                        showingImagePicker = true
                    },
                    .default(Text("📷 Photo Library")) {
                        imagePickerSourceType = .photoLibrary
                        showingImagePicker = true
                    },
                    .default(Text("🎥 Video")) {
                        imagePickerSourceType = .photoLibrary
                        showingImagePicker = true
                    },
                    .default(Text("🎤 Record Audio")) {
                        showingAudioRecorder = true
                    },
                    .default(Text("📄 Document")) {
                        showingDocumentPicker = true
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(mediaCaptureService: mediaCaptureService, sourceType: imagePickerSourceType)
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPickerView { url in
                do {
                    // Start accessing the security-scoped resource
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    let documentData = try Data(contentsOf: url)
                    let filename = mediaCaptureService.generateFilename(for: .document, originalFilename: url.lastPathComponent)
                    let mimeType = mediaCaptureService.getMimeType(for: url)
                    
                    let selectedMedia = MediaCaptureService.SelectedMedia(
                        type: .document,
                        data: documentData,
                        filename: filename,
                        mimeType: mimeType
                    )
                    
                    mediaCaptureService.selectedMedia = selectedMedia
                    print("✅ Document processed successfully: \(filename)")
                } catch {
                    print("❌ Error processing document: \(error)")
                }
            }
        }
        .sheet(isPresented: $showingAudioRecorder) {
            AudioRecorderView(mediaCaptureService: mediaCaptureService)
        }
        .sheet(isPresented: $showingFullScreenImage) {
            if let selectedMedia = mediaCaptureService.selectedMedia,
               selectedMedia.type == .image,
               let thumbnail = selectedMedia.thumbnail {
                LocalImageView(
                    image: thumbnail,
                    isPresented: $showingFullScreenImage,
                    onSend: {
                        print("📎 Send button tapped, media data size: \(selectedMedia.data.count) bytes")
                        handleMediaSelection(selectedMedia)
                        showingFullScreenImage = false
                    }
                )
            }
        }
        .onChange(of: mediaCaptureService.selectedMedia) { selectedMedia in
            print("📎 Media selection changed: \(selectedMedia?.type.rawValue ?? "nil")")
            if let media = selectedMedia {
                print("📎 Selected media: \(media.filename), data size: \(media.data.count) bytes")
                
                // For debugging: upload all media immediately
                // TODO: Re-enable preview for images once upload is working
                handleMediaSelection(media)
                
                // Original code (commented out for debugging):
                // if media.type == .image && media.thumbnail != nil {
                //     showingFullScreenImage = true
                // } else {
                //     handleMediaSelection(media)
                // }
            }
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        chatViewModel.sendMessage(text)
        messageText = ""
    }
    
    private func handleMediaSelection(_ media: MediaCaptureService.SelectedMedia) {
        print("📎 handleMediaSelection called for: \(media.type.rawValue)")
        print("📎 Media filename: \(media.filename)")
        print("📎 Media data size: \(media.data.count) bytes")
        
        Task {
            do {
                // Validate data before upload
                guard !media.data.isEmpty else {
                    print("📎 ERROR: Media data is empty!")
                    await MainActor.run {
                        chatViewModel.errorMessage = "Selected file data is empty"
                    }
                    return
                }
                
                print("📎 Starting upload: \(media.filename), size: \(media.data.count) bytes, type: \(media.type)")
                
                let result = try await fileUploadService.uploadFile(
                    media.data,
                    filename: media.filename,
                    mimeType: media.mimeType
                )
                
                if result.success, let attachment = result.attachment {
                    await MainActor.run {
                        print("📎 Upload successful, creating message with attachment:")
                        print("📎   - Attachment type: \(attachment.type.rawValue)")
                        print("📎   - Attachment filename: \(attachment.filename)")
                        print("📎   - Attachment URL: \(attachment.url ?? "nil")")
                        
                        // Determine message type based on attachment and text presence
                        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let messageType = MessageType.fromAttachment(attachment, hasText: hasText)
                        
                        print("📎 Message type determined: \(messageType.rawValue)")
                        
                        // Create message with attachment
                        let message = ChatMessage(
                            roomId: room.id,
                            sender: chatViewModel.getCurrentUsername(),
                            message: messageText.trimmingCharacters(in: .whitespacesAndNewlines),
                            attachment: attachment,
                            messageType: messageType
                        )
                        
                        print("📎 Created ChatMessage, sending via WebSocket...")
                        
                        // Send message via WebSocket
                        chatViewModel.sendMessageWithAttachment(message)
                        
                        // Clear text if it was just for this media
                        messageText = ""
                        
                        // Clear selected media
                        mediaCaptureService.selectedMedia = nil
                    }
                } else {
                    await MainActor.run {
                        chatViewModel.errorMessage = result.error?.localizedDescription ?? "Upload failed"
                    }
                }
            } catch {
                print("📎 Upload error: \(error)")
                await MainActor.run {
                    chatViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Typing Indicator Helpers
    private var typingIndicatorText: String {
        let users = Array(chatViewModel.typingUsers)
        if users.count == 1 {
            return "\(users[0]) is typing..."
        } else if users.count == 2 {
            return "\(users[0]) and \(users[1]) are typing..."
        } else if users.count > 2 {
            return "\(users[0]), \(users[1]) and \(users.count - 2) others are typing..."
        }
        return ""
    }
    
    private func handleTextChange(_ text: String) {
        print("⌨️ UI: Text changed, length: \(text.count), isTyping: \(isTyping)")
        
        // Cancel previous timer
        typingTimer?.invalidate()
        
        if !text.isEmpty {
            // Send typing start if not already typing
            if !isTyping {
                isTyping = true
                print("⌨️ UI: Sending typing START")
                chatViewModel.sendTypingIndicator(isTyping: true)
            }
            
            // Set timer to send typing stop after 2 seconds of inactivity
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                print("⌨️ UI: Timer expired, sending typing STOP")
                isTyping = false
                chatViewModel.sendTypingIndicator(isTyping: false)
            }
        } else {
            // Empty text, send typing stop
            if isTyping {
                print("⌨️ UI: Text empty, sending typing STOP")
                isTyping = false
                chatViewModel.sendTypingIndicator(isTyping: false)
            }
        }
    }
    
}


struct MessageBubbleView: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    
    private var bubbleColor: Color {
        isFromCurrentUser ? .blue : Color(.systemGray5)
    }
    
    private var textColor: Color {
        isFromCurrentUser ? .white : .primary
    }
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isFromCurrentUser {
                    Text(message.sender)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Text(message.message)
                    .font(.body)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .cornerRadius(16)
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isFromCurrentUser {
                Spacer(minLength: 50)
            }
        }
        .onAppear {
            print("💬 MessageBubble: Sender: '\(message.sender)', IsFromCurrentUser: \(isFromCurrentUser)")
        }
    }
    
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ChatView(room: ChatRoom(id: "1", name: "General"))
        .environmentObject(ChatViewModel())
}
