//
//  MessageBubbleComponents.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI
import AVKit
import AVFoundation
import UIKit

// MARK: - Enhanced Message Bubble View
struct EnhancedMessageBubbleView: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    @State private var showingFullScreenImage = false
    @State private var showingVideoPlayer = false
    @State private var isPlayingAudio = false
    @State private var audioPlayer: AVAudioPlayer?
    
    // Reaction-related state
    @State private var showingReactionPicker = false
    @State private var reactions: [ReactionSummary] = []
    @State private var userReaction: ReactionType?
    @State private var isChangingReaction = false
    @State private var showingRemoveReactionSheet = false
    @State private var reactionToRemove: ReactionType?
    
    // Callbacks for reaction handling
    let onReactionSelected: ((String, ReactionType) -> Void)?
    let onReactionRemoved: ((String) -> Void)?
    
    init(message: ChatMessage, isFromCurrentUser: Bool, onReactionSelected: ((String, ReactionType) -> Void)? = nil, onReactionRemoved: ((String) -> Void)? = nil) {
        self.message = message
        self.isFromCurrentUser = isFromCurrentUser
        self.onReactionSelected = onReactionSelected
        self.onReactionRemoved = onReactionRemoved
        
        // Initialize reactions from message data
        self._reactions = State(initialValue: message.reactions)
        self._userReaction = State(initialValue: message.userReaction)
    }
    
    private var bubbleColor: Color {
        isFromCurrentUser ? .blue : Color(.systemGray5)
    }
    
    private var textColor: Color {
        isFromCurrentUser ? .white : .primary
    }
    
    var body: some View {
        ZStack {
            // Background overlay to dismiss reaction picker when tapping outside
            if showingReactionPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("🔖 MessageBubble: Background tapped, dismissing reaction picker")
                        showingReactionPicker = false
                    }
            }
            
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
                
                // Main content based on message type
                MessageContentView(
                    message: message,
                    bubbleColor: bubbleColor,
                    textColor: textColor,
                    isFromCurrentUser: isFromCurrentUser,
                    showingFullScreenImage: $showingFullScreenImage,
                    showingVideoPlayer: $showingVideoPlayer,
                    isPlayingAudio: $isPlayingAudio,
                    audioPlayer: $audioPlayer
                )
                // Reserve minimal space below the bubble for the overlapping reactions pill
                .padding(.bottom, reactions.isEmpty ? 0 : 6)
                .overlay(
                    // Reaction overlay positioned based on message side
                    ReactionOverlayView(
                        reactions: reactions,
                        userReaction: userReaction,
                        isFromCurrentUser: isFromCurrentUser,
                        showingReactionPicker: showingReactionPicker,
                        onReactionLongPress: { reactionType in
                            // Long press on reaction - show remove option
                            handleReactionLongPress(reactionType)
                        },
                        onReactionTap: { reactionType in
                            // Tap on reaction - add/change reaction
                            handleReactionTap(reactionType)
                        }
                    ),
                    alignment: isFromCurrentUser ? .bottomTrailing : .bottomLeading
                )
                .onLongPressGesture {
                    print("🔖 MessageBubble: Long press detected on message: \(message.id)")
                    isChangingReaction = (userReaction != nil)
                    showingReactionPicker = true
                    print("🔖 MessageBubble: Showing reaction picker: \(showingReactionPicker), isChangingReaction: \(isChangingReaction)")
                }
                
                // Inline Reaction Picker
                if showingReactionPicker {
//                    print("🔖 MessageBubble: Showing reaction picker for message: \(message.id)")
                    ReactionPickerView(
                        userReaction: userReaction,
                        isFromCurrentUser: isFromCurrentUser,
                        isChangingReaction: isChangingReaction,
                        onSelect: { reactionType in
                            print("🔖 MessageBubble: Reaction selected: \(reactionType.rawValue) for message: \(message.id)")
                            if isChangingReaction && userReaction != nil {
                                // User is changing reaction - remove old one first, then add new one
                                print("🔖 MessageBubble: Changing reaction from \(userReaction?.rawValue ?? "nil") to \(reactionType.rawValue)")
                                onReactionRemoved?(message.id)
                                // Add new reaction immediately
                                onReactionSelected?(message.id, reactionType)
                            } else {
                                // User is adding new reaction
                                print("🔖 MessageBubble: Adding new reaction: \(reactionType.rawValue)")
                                onReactionSelected?(message.id, reactionType)
                            }
                        },
                        onRemove: {
                            onReactionRemoved?(message.id)
                        },
                        showing: $showingReactionPicker
                    )
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: showingReactionPicker)
                }
                
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
                if !isFromCurrentUser {
                    Spacer(minLength: 50)
                }
            }
        }
        .onAppear {
            print("💬 MessageBubble: Sender: '\(message.sender)', IsFromCurrentUser: \(isFromCurrentUser), Type: \(message.messageType)")
            print("🔖 MessageBubble: Initial reactions count: \(message.reactions.count)")
            print("🔖 MessageBubble: Initial userReaction: \(message.userReaction?.rawValue ?? "nil")")
            // Sync reactions with message data
            reactions = message.reactions
            userReaction = message.userReaction
            print("🔖 MessageBubble: Local reactions count: \(reactions.count)")
        }
        .onChange(of: message.reactions) { newReactions in
            // Update reactions when message data changes
            reactions = newReactions
        }
        .onChange(of: message.userReaction) { newUserReaction in
            // Update user reaction when message data changes
            userReaction = newUserReaction
        }
        .onChange(of: showingReactionPicker) { isShowing in
            if !isShowing {
                isChangingReaction = false
            }
        }
        .sheet(isPresented: $showingRemoveReactionSheet) {
            RemoveReactionSheet(
                reactionType: reactionToRemove,
                onRemove: {
                    onReactionRemoved?(message.id)
                    showingRemoveReactionSheet = false
                },
                onCancel: {
                    showingRemoveReactionSheet = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let attachment = message.attachment,
               let videoURL = attachment.url {
                let fullURL = videoURL.hasPrefix("/api/files/") ? 
                    "\(ServerConfig.httpBaseURL)\(videoURL)" : 
                    ServerConfig.getFileURL(for: videoURL)
                
                if let url = URL(string: fullURL) {
                    FullScreenVideoPlayer(videoURL: url, isPresented: $showingVideoPlayer)
                }
            }
        }
        // Removed background tap gesture to prevent interference with reaction picker
    }
    
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Reaction Management
    func updateReactions(_ newReactions: [ReactionSummary], userReaction: ReactionType? = nil) {
        self.reactions = newReactions
        self.userReaction = userReaction
    }
    
    func addReaction(_ reaction: ReactionSummary) {
        if let index = reactions.firstIndex(where: { $0.reactionType == reaction.reactionType }) {
            reactions[index] = reaction
        } else {
            reactions.append(reaction)
        }
    }
    
    func removeReaction(_ reactionType: ReactionType) {
        reactions.removeAll { $0.reactionType == reactionType }
        if userReaction == reactionType {
            userReaction = nil
        }
    }
    
    // MARK: - Reaction Interaction Handlers
    func handleReactionLongPress(_ reactionType: ReactionType) {
        // If user has this reaction, show remove option
        if userReaction == reactionType {
            // Show alert to remove reaction
            showRemoveReactionAlert(reactionType)
        }
    }
    
    func handleReactionTap(_ reactionType: ReactionType) {
        // If user already has this reaction, show remove sheet
        if userReaction == reactionType {
            reactionToRemove = reactionType
            showingRemoveReactionSheet = true
        } else {
            // Add or change reaction
            onReactionSelected?(message.id, reactionType)
        }
    }
    
    private func showRemoveReactionAlert(_ reactionType: ReactionType) {
        // For now, we'll use a simple approach - directly remove the reaction
        // In a full implementation, you might want to show an alert
        onReactionRemoved?(message.id)
    }
}

// MARK: - Subviews
private struct ReactionOverlayView: View {
    let reactions: [ReactionSummary]
    let userReaction: ReactionType?
    let isFromCurrentUser: Bool
    let showingReactionPicker: Bool
    let onReactionLongPress: (ReactionType) -> Void
    let onReactionTap: (ReactionType) -> Void
    
    var body: some View {
        Group {
            if !reactions.isEmpty && !showingReactionPicker {
                HStack(spacing: 2) {
                    ForEach(reactions, id: \.reactionType) { reaction in
                        ReactionBubbleView(
                            reaction: reaction,
                            isUserReaction: userReaction == reaction.reactionType,
                            onLongPress: { onReactionLongPress(reaction.reactionType) },
                            onTap: { onReactionTap(reaction.reactionType) }
                        )
                    }
                }
                .fixedSize(horizontal: true, vertical: false) // Allow horizontal expansion
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                // Overlap slightly with the bottom of the message bubble
                .offset(y: 2)
                .padding(isFromCurrentUser ? .trailing : .leading, 2)
                .zIndex(10) // Higher z-index to appear over message
            }
        }
    }
}

private struct ReactionBubbleView: View {
    let reaction: ReactionSummary
    let isUserReaction: Bool
    let onLongPress: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            Text(reaction.reactionType.rawValue)
                .font(.system(size: 12))
            
            if reaction.count > 1 {
                Text("\(reaction.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .onTapGesture {
            onTap()
        }
                .onLongPressGesture {
            onLongPress()
        }
    }
}

private struct ReactionPickerView: View {
    let userReaction: ReactionType?
    let isFromCurrentUser: Bool
    let isChangingReaction: Bool
    let onSelect: (ReactionType) -> Void
    let onRemove: () -> Void
    @Binding var showing: Bool
    
    var body: some View {
                    HStack {
                        if !isFromCurrentUser {
                            Spacer()
                        }
                        
                        HStack(spacing: 6) {
                            ForEach(ReactionType.allCases, id: \.self) { reactionType in
                                Button(action: {
                        print("🔖 ReactionPicker: Button tapped for reaction: \(reactionType.rawValue)")
                        print("🔖 ReactionPicker: isChangingReaction: \(isChangingReaction), userReaction: \(userReaction?.rawValue ?? "nil")")
                        
                        if isChangingReaction {
                            // When changing reaction, always select the new one
                            print("🔖 ReactionPicker: Changing reaction to: \(reactionType.rawValue)")
                            onSelect(reactionType)
                        } else if userReaction == reactionType {
                            // Normal case: remove if same reaction
                            print("🔖 ReactionPicker: Removing reaction: \(reactionType.rawValue)")
                            onRemove()
                                    } else {
                            // Normal case: add new reaction
                            print("🔖 ReactionPicker: Adding reaction: \(reactionType.rawValue)")
                            onSelect(reactionType)
                                    }
                        showing = false
                                }) {
                                    Text(reactionType.rawValue)
                                        .font(.system(size: 20))
                                        .padding(6)
                                        .background(
                                            Circle()
                                                .fill(Color.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                        .shadow(radius: 2)
                                }
                                .scaleEffect(userReaction == reactionType ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: userReaction == reactionType)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
            .offset(y: -8)
            .zIndex(2)
                        
                        if isFromCurrentUser {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 8)
    }
}

private struct MessageContentView: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    let isFromCurrentUser: Bool
    @Binding var showingFullScreenImage: Bool
    @Binding var showingVideoPlayer: Bool
    @Binding var isPlayingAudio: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    
    var body: some View {
        Group {
            switch message.messageType {
            case .text:
                TextOnlyBubble(message: message, bubbleColor: bubbleColor, textColor: textColor)
                
            case .image:
                ImageOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, showingFullScreen: $showingFullScreenImage)
                
            case .video:
                VideoOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, showingVideoPlayer: $showingVideoPlayer)
                
            case .audio:
                AudioOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, isPlaying: $isPlayingAudio, audioPlayer: $audioPlayer)
                
            case .document:
                DocumentOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser)
                
            case .textWithImage:
                TextWithImageBubble(message: message, bubbleColor: bubbleColor, textColor: textColor, isFromCurrentUser: isFromCurrentUser, showingFullScreen: $showingFullScreenImage)
                
            case .textWithVideo:
                TextWithVideoBubble(message: message, bubbleColor: bubbleColor, textColor: textColor, isFromCurrentUser: isFromCurrentUser, showingVideoPlayer: $showingVideoPlayer)
                
            case .textWithAudio:
                TextWithAudioBubble(message: message, bubbleColor: bubbleColor, textColor: textColor, isFromCurrentUser: isFromCurrentUser, isPlaying: $isPlayingAudio, audioPlayer: $audioPlayer)
                
            case .textWithDocument:
                TextWithDocumentBubble(message: message, bubbleColor: bubbleColor, textColor: textColor, isFromCurrentUser: isFromCurrentUser)
            }
        }
    }
}

// MARK: - Text Only Bubble
struct TextOnlyBubble: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.isEncrypted {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.7))
                    .padding(.leading, 12)
                    .padding(.top, 8)
            }
            Text(message.message)
                .font(.body)
                .foregroundColor(textColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleColor)
            .cornerRadius(16)
    }
}

// MARK: - Image Only Bubble
struct ImageOnlyBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    @Binding var showingFullScreen: Bool
    
    var body: some View {
        if let attachment = message.attachment {
            if let imageURL = attachment.url, !imageURL.isEmpty {
                // Handle both full URLs and filenames
                let fullURL = getFullImageURL(from: imageURL)
                
                if let url = URL(string: fullURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250, maxHeight: 300)
                                .cornerRadius(12)
                                .onTapGesture {
                                    showingFullScreen = true
                                }
                                .onAppear {
                                    print("🖼️ ImageOnlyBubble: Successfully loaded image")
                                }
                                
                        case .failure(let error):
                            imageFallbackView(filename: attachment.filename)
                                .onAppear {
                                    print("🖼️ ImageOnlyBubble: Failed to load image: \(error)")
                                    print("🖼️ ImageOnlyBubble: Failed URL: \(fullURL)")
                                }
                                
                        case .empty:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 250, height: 200)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                )
                                .onAppear {
                                    print("🖼️ ImageOnlyBubble: Loading image...")
                                }
                                
                        @unknown default:
                            imageFallbackView(filename: attachment.filename)
                                .onAppear {
                                    print("🖼️ ImageOnlyBubble: Unknown loading state")
                                }
                        }
                    }
                    .onAppear {
                        print("🖼️ ImageOnlyBubble: Loading image from URL: \(fullURL)")
                        print("🖼️ ImageOnlyBubble: Original URL: \(imageURL)")
                        print("🖼️ ImageOnlyBubble: Message sender: \(message.sender)")
                        print("🖼️ ImageOnlyBubble: Is from current user: \(isFromCurrentUser)")
                    }
                } else {
                    // Invalid URL - show fallback
                    imageFallbackView(filename: attachment.filename)
                        .onAppear {
                            print("🖼️ ImageOnlyBubble: Invalid URL - \(fullURL)")
                        }
                }
            } else {
                // No URL - show fallback
                imageFallbackView(filename: attachment.filename)
            }
        } else {
            // No attachment - show generic fallback
            imageFallbackView(filename: "image")
        }
    }
    
    private func getFullImageURL(from imageURL: String) -> String {
        if imageURL.hasPrefix("http") {
            // Already a full URL, use as-is
            return imageURL
        } else if imageURL.hasPrefix("/api/files/") {
            // Relative URL starting with /api/files/
            return "\(ServerConfig.httpBaseURL)\(imageURL)"
        } else {
            // Just a filename
            return ServerConfig.getFileURL(for: imageURL)
        }
    }
    
    @ViewBuilder
    private func imageFallbackView(filename: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.blue.opacity(0.2))
            .frame(width: 250, height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    
                    Text("Image")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    if !filename.isEmpty && filename != "image" && !filename.hasPrefix("placeholder_") {
                        Text(filename)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            )
            .onTapGesture {
                showingFullScreen = true
            }
    }
}

// MARK: - Video Only Bubble
struct VideoOnlyBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    @Binding var showingVideoPlayer: Bool
    
    var body: some View {
        if let attachment = message.attachment,
           let videoURL = attachment.url {
            
            // Handle both full URLs and filenames
            let fullURL = videoURL.hasPrefix("/api/files/") ? 
                "\(ServerConfig.httpBaseURL)\(videoURL)" : 
                ServerConfig.getFileURL(for: videoURL)
            
            if let url = URL(string: fullURL) {
            
            VStack(spacing: 8) {
                // Video placeholder (no thumbnail available from server)
                ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 250, height: 200)
                            .overlay(
                                Image(systemName: "video")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    
                    // Play button overlay
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        )
                }
                .onTapGesture {
                    showingVideoPlayer = true
                }
                
                // Video info
                    HStack {
                        Image(systemName: "video")
                    Text("Video")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            }
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Only Bubble
struct AudioOnlyBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    @Binding var isPlaying: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDragging: Bool = false
    @State private var playbackTimer: Timer?
    
    var body: some View {
        if let attachment = message.attachment {
            if let audioURL = attachment.url, !audioURL.isEmpty {
                // Audio with URL - show playable audio
                audioPlayerView(attachment: attachment)
            } else {
                // No URL - show placeholder
                audioPlaceholderView(attachment: attachment)
            }
        } else {
            // No attachment - show generic placeholder
            audioPlaceholderView(attachment: nil)
        }
    }
    
    @ViewBuilder
    private func audioPlayerView(attachment: Attachment) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Play/Pause button
                Button(action: toggleAudioPlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(isFromCurrentUser ? .white : .blue)
                }
                
                // Time display
                Text(formatDuration(currentTime))
                    .font(.caption)
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                    .frame(width: 35, alignment: .leading)
                
                // Seek bar - centered in the available space
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track - full width
                        Rectangle()
                            .fill(isFromCurrentUser ? Color.white.opacity(0.3) : Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width, height: 4)
                            .cornerRadius(2)
                        
                        // Progress track - starts from left, grows to right
                        Rectangle()
                            .fill(isFromCurrentUser ? .white : .blue)
                            .frame(width: duration > 0 ? geometry.size.width * (currentTime / duration) : 0, height: 4)
                            .cornerRadius(2)
                            .animation(.linear(duration: 0.1), value: currentTime)
                    }
                    .frame(height: 20, alignment: .center)
                    .gesture(
                        SimultaneousGesture(
                            // Tap gesture for seeking to center
                            TapGesture()
                                .onEnded { _ in
                                    // Tap seeks to center (50% of audio duration)
                                    seekToCenter()
                                },
                            // Drag gesture for precise seeking
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    seekToPosition(at: value.location, in: geometry.size.width)
                                }
                                .onEnded { value in
                                    isDragging = false
                                    seekToPosition(at: value.location, in: geometry.size.width)
                                }
                        )
                    )
                }
                .frame(height: 20)
                
                // Total duration
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isFromCurrentUser ? .blue : Color(.systemGray5))
        .cornerRadius(16)
        .onAppear {
            setupAudioPlayer()
        }
        .onDisappear {
            stopPlaybackTimer()
        }
    }
    
    @ViewBuilder
    private func audioPlaceholderView(attachment: Attachment?) -> some View {
        HStack(spacing: 12) {
            // Disabled play button
            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(isFromCurrentUser ? .white.opacity(0.5) : .gray)
            
            VStack(alignment: .leading, spacing: 4) {
                // Static waveform representation
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { index in
                        Rectangle()
                            .fill(isFromCurrentUser ? .white.opacity(0.3) : .gray.opacity(0.5))
                            .frame(width: 2, height: CGFloat.random(in: 4...20))
                    }
                }
                
                HStack {
                    Text("Audio")
                        .font(.caption)
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                    
                    if let attachment = attachment, !attachment.filename.isEmpty && attachment.filename != "placeholder_audio" {
                        Text("• \(attachment.filename)")
                            .font(.caption2)
                            .foregroundColor(isFromCurrentUser ? .white.opacity(0.6) : .secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.6) : .secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isFromCurrentUser ? .blue.opacity(0.7) : Color(.systemGray5).opacity(0.7))
        .cornerRadius(16)
    }
    
    private func toggleAudioPlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            stopPlaybackTimer()
        } else {
            playAudio()
        }
    }
    
    private func setupAudioPlayer() {
        guard let attachment = message.attachment,
              let audioURL = attachment.url,
              !audioURL.isEmpty else { return }
        
        // Note: Duration not available from server response
        // Audio duration will be determined when the file is loaded
    }
    
    private func seekToPosition(at location: CGPoint, in width: CGFloat) {
        guard duration > 0 else { return }
        
        let percentage = max(0, min(1, location.x / width))
        let seekTime = duration * percentage
        
        currentTime = seekTime
        audioPlayer?.currentTime = seekTime
        
        print("🎵 Seeking to: \(formatDuration(seekTime)) (\(Int(percentage * 100))%)")
    }
    
    private func seekToCenter() {
        guard duration > 0 else { return }
        
        let centerTime = duration * 0.5 // 50% of audio duration
        currentTime = centerTime
        audioPlayer?.currentTime = centerTime
        
        print("🎵 Seeking to center: \(formatDuration(centerTime)) (50%)")
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer() // Stop any existing timer
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer, player.isPlaying else { return }
            
            if !isDragging {
                currentTime = player.currentTime
            }
            
            // Update duration if not set
            if duration == 0 && player.duration > 0 {
                duration = player.duration
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func playAudio() {
        guard let attachment = message.attachment,
              let audioURL = attachment.url,
              let url = URL(string: getFullAudioURL(from: audioURL)) else { 
            print("❌ Audio playback failed: Invalid URL")
            return 
        }
        
        print("🎵 Attempting to play audio from URL: \(url)")
        
        // Try to play directly - AVAudioPlayer will handle errors gracefully
        startAudioPlayback(url: url)
    }
    
    
    private func startAudioPlayback(url: URL) {
        do {
            print("🎵 Setting up audio session...")
            
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            print("🎵 Creating AVAudioPlayer with URL: \(url)")
            
            // Try to download and play the audio file instead of streaming
            downloadAndPlayAudio(from: url)
            
        } catch {
            print("❌ Error setting up audio session: \(error)")
            isPlaying = false
        }
    }
    
    private func downloadAndPlayAudio(from url: URL) {
        print("🎵 Downloading audio file for local playback...")
        
        URLSession.shared.dataTask(with: url) { [self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error downloading audio: \(error)")
                    self.isPlaying = false
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    print("❌ No audio data received")
                    self.isPlaying = false
                    return
                }
                
                print("🎵 Downloaded \(data.count) bytes of audio data")
                
                // Save to temporary file and play
                self.playAudioFromData(data)
            }
        }.resume()
    }
    
    private func playAudioFromData(_ data: Data) {
        do {
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio.m4a")
            try data.write(to: tempURL)
            print("🎵 Saved audio to temporary file: \(tempURL)")
            
            // Create AVAudioPlayer with local file
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = AudioPlayerDelegate { [self] in
                print("🎵 Audio playback finished")
                isPlaying = false
                stopPlaybackTimer()
                currentTime = 0
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            print("🎵 Preparing audio to play...")
            if audioPlayer?.prepareToPlay() == true {
                // Set duration
                duration = audioPlayer?.duration ?? 0
                print("🎵 Audio duration: \(formatDuration(duration))")
                
                print("🎵 Starting audio playback...")
                audioPlayer?.play()
                isPlaying = true
                startPlaybackTimer()
                print("✅ Audio playback started successfully")
            } else {
                print("❌ Audio playback failed: Could not prepare to play")
                print("❌ Audio player duration: \(audioPlayer?.duration ?? 0)")
                isPlaying = false
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("❌ Error playing audio from data: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            isPlaying = false
        }
    }
    
    private func getFullAudioURL(from audioURL: String) -> String {
        if audioURL.hasPrefix("http") {
            // Already a full URL, use as-is
            return audioURL
        } else if audioURL.hasPrefix("/api/files/") {
            // Relative URL starting with /api/files/
            return "\(ServerConfig.httpBaseURL)\(audioURL)"
        } else {
            // Just a filename
            return ServerConfig.getFileURL(for: audioURL)
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Document Only Bubble
struct DocumentOnlyBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    
    var body: some View {
        if let attachment = message.attachment {
            HStack(spacing: 12) {
                // Document icon
                Image(systemName: getDocumentIcon(for: attachment))
                    .font(.title2)
                    .foregroundColor(isFromCurrentUser ? .white : .blue)
                    .frame(width: 30, height: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename.isEmpty ? "Document" : attachment.filename)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .lineLimit(2)
                    
                    if let size = attachment.size, size > 0 {
                        Text(FileUploadService.formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                    } else {
                        Text("Unknown size")
                            .font(.caption)
                            .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(isFromCurrentUser ? .white : .blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromCurrentUser ? .blue : Color(.systemGray5))
            .cornerRadius(16)
            .onTapGesture {
                // Handle document download/view
                if let url = attachment.url, !url.isEmpty {
                    openDocument(url: url)
                } else {
                    print("📄 Document URL is empty, cannot open")
                }
            }
        } else {
            // No attachment - show fallback
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.title2)
                    .foregroundColor(isFromCurrentUser ? .white : .blue)
                    .frame(width: 30, height: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Document")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                    
                    Text("No file available")
                        .font(.caption)
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromCurrentUser ? .blue : Color(.systemGray5))
            .cornerRadius(16)
        }
    }
    
    private func getDocumentIcon(for attachment: Attachment) -> String {
        guard let mimeType = attachment.mimeType else { return "doc" }
        
        if mimeType.contains("pdf") {
            return "doc.text"
        } else if mimeType.contains("word") {
            return "doc.richtext"
        } else if mimeType.contains("text") {
            return "doc.text"
        } else {
            return "doc"
        }
    }
    
    private func openDocument(url: String) {
        print("Opening document: \(url)")
        
        // Convert relative URL to absolute URL
        let absoluteUrl: String
        if url.hasPrefix("http") {
            // Already absolute URL
            absoluteUrl = url
        } else {
            // Convert relative URL to absolute
            absoluteUrl = "http://\(ServerConfig.serverIP):\(ServerConfig.serverPort)\(url)"
        }
        
        print("🔗 Opening absolute URL: \(absoluteUrl)")
        
        guard let urlObject = URL(string: absoluteUrl) else {
            print("❌ Invalid document URL: \(absoluteUrl)")
            return
        }
        
        // Open the document URL
        if UIApplication.shared.canOpenURL(urlObject) {
            UIApplication.shared.open(urlObject) { success in
                if success {
                    print("✅ Document opened successfully")
                } else {
                    print("❌ Failed to open document")
                }
            }
        } else {
            print("❌ Cannot open document URL: \(absoluteUrl)")
        }
    }
}

// MARK: - Text with Media Bubbles
struct TextWithImageBubble: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    let isFromCurrentUser: Bool
    @Binding var showingFullScreen: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextOnlyBubble(message: message, bubbleColor: bubbleColor, textColor: textColor)
            ImageOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, showingFullScreen: $showingFullScreen)
        }
    }
}

struct TextWithVideoBubble: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    let isFromCurrentUser: Bool
    @Binding var showingVideoPlayer: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextOnlyBubble(message: message, bubbleColor: bubbleColor, textColor: textColor)
            VideoOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, showingVideoPlayer: $showingVideoPlayer)
        }
    }
}

struct TextWithAudioBubble: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    let isFromCurrentUser: Bool
    @Binding var isPlaying: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextOnlyBubble(message: message, bubbleColor: bubbleColor, textColor: textColor)
            AudioOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser, isPlaying: $isPlaying, audioPlayer: $audioPlayer)
        }
    }
}

struct TextWithDocumentBubble: View {
    let message: ChatMessage
    let bubbleColor: Color
    let textColor: Color
    let isFromCurrentUser: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextOnlyBubble(message: message, bubbleColor: bubbleColor, textColor: textColor)
            DocumentOnlyBubble(message: message, isFromCurrentUser: isFromCurrentUser)
        }
    }
}

// MARK: - Audio Player Delegate
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - Local Image Viewer
struct LocalImageView: View {
    let image: UIImage
    @Binding var isPresented: Bool
    let onSend: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        onSend()
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Full Screen Image Viewer
struct FullScreenImageView: View {
    let imageURL: String
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let url = URL(string: ServerConfig.getFileURL(for: imageURL)) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .ignoresSafeArea()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Full Screen Video Player
struct FullScreenVideoPlayer: View {
    let videoURL: URL
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        player?.pause()
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                print("🎥 Video player appeared with URL: \(videoURL)")
                setupPlayer()
            }
            .onDisappear {
                print("🎥 Video player disappeared, cleaning up")
                player?.pause()
                player = nil
            }
        }
    }
    
    private func setupPlayer() {
        let newPlayer = AVPlayer(url: videoURL)
        self.player = newPlayer
        
        // Check if the item can be played
        let playerItem = newPlayer.currentItem
        print("🎥 Player item status: \(playerItem?.status.rawValue ?? -1)")
        print("🎥 Player item error: \(playerItem?.error?.localizedDescription ?? "none")")
        
        // Add notification for when video is ready to play
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: playerItem,
            queue: .main
        ) { _ in
            print("🎥 New access log entry - video is loading")
        }
        
        // Add notification for playback errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ Video failed to play: \(error.localizedDescription)")
            }
        }
        
        // Start playing automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🎥 Attempting to play video...")
            print("🎥 Player rate before play: \(newPlayer.rate)")
            newPlayer.play()
            print("🎥 Player rate after play: \(newPlayer.rate)")
            
            // Check status after attempting to play
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🎥 Player status: \(newPlayer.status.rawValue)")
                print("🎥 Player current time: \(newPlayer.currentTime().seconds)")
                print("🎥 Player error: \(newPlayer.error?.localizedDescription ?? "none")")
                print("🎥 Player item error: \(newPlayer.currentItem?.error?.localizedDescription ?? "none")")
                
                if let item = newPlayer.currentItem {
                    print("🎥 Item duration: \(item.duration.seconds)")
                    print("🎥 Item is playback likely to keep up: \(item.isPlaybackLikelyToKeepUp)")
                    print("🎥 Item is playback buffer empty: \(item.isPlaybackBufferEmpty)")
                    print("🎥 Item is playback buffer full: \(item.isPlaybackBufferFull)")
                }
            }
        }
    }
}
