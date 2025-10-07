//
//  ChatViewModel.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import Combine
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentRoom: ChatRoom?
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var typingUsers: Set<String> = [] // Track who is typing
    
    private let messageService = MessageService()
    private let roomService = RoomService()
    private let webSocketManager = ChatWebSocketManager()
    private let reactionService = ReactionService.shared
    private let keychainService = KeychainService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupWebSocketSubscriptions()
        setupForegroundObserver()
    }
    
    // MARK: - Setup
    private func setupWebSocketSubscriptions() {
        // Subscribe to WebSocket connection status
        webSocketManager.$isConnected
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
        
        // Subscribe to connection errors
        webSocketManager.$connectionError
            .assign(to: \.connectionError, on: self)
            .store(in: &cancellables)
        
        // Subscribe to incoming messages
        webSocketManager.messagePublisher
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
        
        // Subscribe to typing indicators
        webSocketManager.typingPublisher
            .sink { [weak self] (username, isTyping) in
                print("⌨️ ChatViewModel: Typing indicator - \(username): \(isTyping)")
                self?.handleTypingIndicator(username: username, isTyping: isTyping)
            }
            .store(in: &cancellables)
        
        // Subscribe to reaction events
        webSocketManager.reactionPublisher
            .sink { [weak self] reactionEvent in
                print("🔖 ChatViewModel: Reaction event - \(reactionEvent.type) for message \(reactionEvent.messageId)")
                self?.handleReactionEvent(reactionEvent)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Setup Foreground Observer
    private func setupForegroundObserver() {
        // Listen for app foreground notifications
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppForeground()
            }
            .store(in: &cancellables)
        
        // Listen for app background notifications
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppBackground()
            }
            .store(in: &cancellables)
        
        // Listen for network reachability changes
        // Note: NSURLSessionDataTaskDidBecomeInvalid is not available as a notification name
        // Instead, we'll rely on WebSocket connection status and app lifecycle events
        // to handle network issues
    }
    
    // MARK: - App Lifecycle Handlers
    private func handleAppForeground() {
        print("🔄 ChatViewModel: App entered foreground, checking WebSocket connectivity...")
        
        // Check if we have a current room and should be connected
        guard let room = currentRoom else {
            print("🔄 ChatViewModel: No current room, skipping connectivity check")
            return
        }
        
        // Check current connection status
        if !isConnected {
            print("🔄 ChatViewModel: WebSocket disconnected, attempting to reconnect...")
            reconnectToWebSocket(roomId: room.id)
        } else {
            print("🔄 ChatViewModel: WebSocket appears connected, sending ping to verify...")
            // Send a ping message to verify connection is still alive
            verifyConnection()
        }
    }
    
    private func handleAppBackground() {
        print("🔄 ChatViewModel: App entered background")
        // Don't disconnect immediately, let the WebSocket manager handle it
        // This allows for background processing if needed
    }
    
    private func handleNetworkIssue() {
        print("🔄 ChatViewModel: Network issue detected")
        // Mark connection as potentially problematic
        if isConnected {
            print("🔄 ChatViewModel: Attempting to refresh connection...")
            guard let room = currentRoom else { return }
            reconnectToWebSocket(roomId: room.id)
        }
    }
    
    private func verifyConnection() {
        // Send a simple message to verify connection is alive
        guard let room = currentRoom else { return }
        let username = keychainService.getUsername() ?? "Unknown"
        
        // Send a ping message (this will be handled by the server or ignored)
        webSocketManager.sendMessage(roomId: room.id, message: "ping", sender: username)
        
        // Set a timer to check if we receive a response or if connection is still good
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            if let self = self, !self.isConnected {
                print("🔄 ChatViewModel: Connection verification failed, reconnecting...")
                self.reconnectToWebSocket(roomId: room.id)
            }
        }
    }
    
    // MARK: - Connect to WebSocket
    func connectToWebSocket(roomId: String = "general") {
        guard let token = keychainService.getToken() else {
            errorMessage = "No authentication token found"
            return
        }
        
        webSocketManager.connect(token: token, roomId: roomId)
    }

    
    // MARK: - Reconnect to WebSocket
    func reconnectToWebSocket(roomId: String = "general") {
        guard let token = keychainService.getToken() else {
            errorMessage = "No authentication token found"
            return
        }
        
        webSocketManager.reconnect(token: token, roomId: roomId)
    }
    
    // MARK: - Auto Reconnect to WebSocket
    func autoReconnectToWebSocket() {
        webSocketManager.autoReconnect()
    }
    
    // MARK: - Join Room
    func joinRoom(_ room: ChatRoom) {
        currentRoom = room
        messages = []
        
        // Connect to WebSocket for the room
        connectToWebSocket(roomId: room.id)
        
        // Load previous messages
        loadPreviousMessages(for: room.id)
    }
    
    func leaveRoom() {
        print("📱 ChatViewModel: Leaving room - keeping WebSocket connection alive")
        currentRoom = nil
        messages = []
        // Don't disconnect WebSocket - keep connection alive for other rooms
    }
    
    // This should only be called when user logs out or app terminates
    func disconnectWebSocket() {
        print("📱 ChatViewModel: Disconnecting WebSocket (logout/termination)")
        webSocketManager.disconnect()
    }
    
    // MARK: - Load Previous Messages
    private func loadPreviousMessages(for roomId: String, retryCount: Int = 0) {
        guard let token = keychainService.getToken() else { 
            print("❌ No auth token available for loading messages")
            return 
        }
        
        isLoading = true
        print("📱 Loading previous messages for room \(roomId) (attempt \(retryCount + 1))")
        
        Task {
            do {
                let previousMessages = try await messageService.fetchMessages(for: roomId, token: token)
                
                await MainActor.run {
                    self.messages = previousMessages.sorted { $0.timestamp < $1.timestamp }
                    self.isLoading = false
                    self.errorMessage = nil
                    print("📱 Successfully loaded \(previousMessages.count) messages with reactions")
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("❌ Failed to load messages: \(error)")
                    
                    // Retry up to 3 times with exponential backoff
                    if retryCount < 2 {
                        let delay = pow(2.0, Double(retryCount)) // 1, 2, 4 seconds
                        print("📱 Retrying message load in \(delay) seconds...")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.loadPreviousMessages(for: roomId, retryCount: retryCount + 1)
                        }
                    } else {
                        self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
                        print("❌ Max retry attempts reached for loading messages")
                    }
                }
            }
        }
    }
    
    // MARK: - Send Message
    func sendMessage(_ text: String) {
        guard let room = currentRoom,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let message = ChatMessage(
            id: "local_\(UUID().uuidString)", // Generate consistent local ID
            roomId: room.id,
            sender: keychainService.getUsername() ?? "Unknown",
            message: text.trimmingCharacters(in: .whitespacesAndNewlines),
            messageType: .text,
            reactions: [],
            userReaction: nil
        )
        
        // Add message to local array immediately for better UX
        messages.append(message)
        
        // Send via WebSocket
        let username = keychainService.getUsername() ?? "Unknown"
        webSocketManager.sendMessage(roomId: room.id, message: text, sender: username)
        
        // Stop typing indicator when message is sent
        sendTypingIndicator(isTyping: false)
    }
    
    // MARK: - Send Message with Attachment
    func sendMessageWithAttachment(_ message: ChatMessage) {
        guard let room = currentRoom else { return }
        
        // Add message to local array immediately for better UX
        messages.append(message)
        
        // Send via WebSocket with attachment info
        let username = keychainService.getUsername() ?? "Unknown"
        webSocketManager.sendMessageWithAttachment(
            roomId: room.id,
            message: message.message,
            sender: username,
            attachment: message.attachment,
            messageType: message.messageType
        )
        
        // Stop typing indicator when message is sent
        sendTypingIndicator(isTyping: false)
    }
    
    // MARK: - Typing Indicators
    func sendTypingIndicator(isTyping: Bool) {
        guard let room = currentRoom else { return }
        let username = keychainService.getUsername() ?? "Unknown"
        webSocketManager.sendTypingIndicator(roomId: room.id, isTyping: isTyping, sender: username)
    }
    
    private func handleTypingIndicator(username: String, isTyping: Bool) {
        print("⌨️ ViewModel: handleTypingIndicator - username: \(username), isTyping: \(isTyping)")
        
        // Don't show typing indicator for current user
        let currentUser = keychainService.getUsername() ?? ""
        print("⌨️ ViewModel: Current user: \(currentUser)")
        
        guard username != currentUser else {
            print("⌨️ ViewModel: Ignoring typing indicator for current user")
            return
        }
        
        if isTyping {
            print("⌨️ ViewModel: Adding \(username) to typing users")
            typingUsers.insert(username)
        } else {
            print("⌨️ ViewModel: Removing \(username) from typing users")
            typingUsers.remove(username)
        }
        
        print("⌨️ ViewModel: Current typing users: \(typingUsers)")
    }
    
    // MARK: - Handle Reaction Events
    private func handleReactionEvent(_ reactionEvent: ReactionEvent) {
        print("🔖 ViewModel: handleReactionEvent - type: \(reactionEvent.type), messageId: \(reactionEvent.messageId)")
        
        // Find the message by server message ID
        guard let messageIndex = messages.firstIndex(where: { $0.serverMessageId == reactionEvent.messageId }) else {
            print("❌ ViewModel: Message not found with server ID: \(reactionEvent.messageId)")
            return
        }
        
        print("🔖 ViewModel: Found message at index \(messageIndex) to update with reactions")
        print("🔖 ViewModel: Reaction summary: \(reactionEvent.reactionSummary)")
        
        // Update the message with new reaction data
        var updatedMessage = messages[messageIndex]
        updatedMessage.reactions = reactionEvent.reactionSummary
        
        // Determine if current user has a reaction on this message
        let currentUser = getCurrentUsername()
        updatedMessage.userReaction = reactionEvent.reactionSummary.first { reactionSummary in
            reactionSummary.users.contains(currentUser)
        }?.reactionType
        
        // Update the message in the array
        messages[messageIndex] = updatedMessage
        
        print("🔖 ViewModel: Updated message with \(reactionEvent.reactionSummary.count) reaction types")
    }
    
    // MARK: - Reaction Management
    func addReaction(to messageId: String, reactionType: ReactionType) async {
        print("🔖 ChatViewModel: addReaction called with messageId: \(messageId), reactionType: \(reactionType.rawValue)")
        print("🔖 ChatViewModel: Available message IDs: \(messages.map { $0.id })")
        
        // Find the message by its UUID and get the server message ID
        print("🔖 ChatViewModel: Looking for message with ID: \(messageId)")
        print("🔖 ChatViewModel: Total messages in array: \(messages.count)")
        
        guard let message = messages.first(where: { $0.id == messageId }) else {
            print("❌ ChatViewModel: Message not found with ID: \(messageId)")
            print("❌ ChatViewModel: Available message IDs: \(messages.map { $0.id })")
            print("❌ ChatViewModel: Available messages: \(messages.map { "\($0.id): \($0.message)" })")
            return
        }
        
        print("🔖 ChatViewModel: Found message: \(message.message) with serverMessageId: \(message.serverMessageId ?? -1)")
        
        // Check if this is a locally created message without server ID yet
        guard let serverMessageId = message.serverMessageId else {
            print("⚠️ ChatViewModel: No server message ID available for message: \(messageId)")
            print("⚠️ ChatViewModel: This might be a locally created message that hasn't been confirmed by the server yet")
            
            // For locally created messages, we'll show a user-friendly message
            await MainActor.run {
                self.errorMessage = "Please wait for the message to be sent before adding reactions"
            }
            
            // Clear the error message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.errorMessage = nil
            }
            return
        }
        
        print("🔖 ChatViewModel: Adding reaction \(reactionType.rawValue) to message \(messageId) (server ID: \(serverMessageId))")
        
        Task {
            do {
                print("🔖 ChatViewModel: About to call reactionService.addReaction...")
                let response = try await reactionService.addReaction(messageId: serverMessageId, reactionType: reactionType)
                print("✅ ChatViewModel: Reaction added successfully: \(response.message)")
                
                // Send reaction via WebSocket for real-time updates
                // Note: This will fail silently if WebSocket is not connected, but the reaction was already saved to server
                print("🔖 ChatViewModel: Sending reaction via WebSocket...")
                webSocketManager.sendReaction(messageId: serverMessageId, reactionType: reactionType, action: .add)
                
            } catch {
                print("❌ ChatViewModel: Failed to add reaction: \(error)")
                print("❌ ChatViewModel: Error details: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to add reaction: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func removeReaction(from messageId: String) async {
        // Find the message by its UUID and get the server message ID
        guard let message = messages.first(where: { $0.id == messageId }) else {
            print("❌ ChatViewModel: Message not found with ID: \(messageId)")
            return
        }
        
        // Check if this is a locally created message without server ID yet
        guard let serverMessageId = message.serverMessageId else {
            print("⚠️ ChatViewModel: No server message ID available for message: \(messageId)")
            print("⚠️ ChatViewModel: This might be a locally created message that hasn't been confirmed by the server yet")
            
            // For locally created messages, we'll show a user-friendly message
            await MainActor.run {
                self.errorMessage = "Please wait for the message to be sent before removing reactions"
            }
            
            // Clear the error message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.errorMessage = nil
            }
            return
        }
        
        print("🔖 ChatViewModel: Removing reaction from message \(messageId) (server ID: \(serverMessageId))")
        
        // Optimistically update UI immediately
        await MainActor.run {
            if let messageIndex = self.messages.firstIndex(where: { $0.id == messageId }) {
                var updatedMessage = self.messages[messageIndex]
                updatedMessage.userReaction = nil
                
                // Remove the user's reaction from the reactions array
                if let userReaction = message.userReaction {
                    if let reactionIndex = updatedMessage.reactions.firstIndex(where: { $0.reactionType == userReaction }) {
                        var reaction = updatedMessage.reactions[reactionIndex]
                        reaction.count = max(0, reaction.count - 1)
                        
                        if reaction.count == 0 {
                            updatedMessage.reactions.remove(at: reactionIndex)
                        } else {
                            // Remove current user from users array
                            reaction.users.removeAll { $0 == self.getCurrentUsername() }
                            updatedMessage.reactions[reactionIndex] = reaction
                        }
                    }
                }
                
                self.messages[messageIndex] = updatedMessage
                print("🔖 ChatViewModel: Optimistically updated UI - removed user reaction")
            }
        }
        
        Task {
            do {
                let response = try await reactionService.removeReaction(messageId: serverMessageId)
                print("✅ ChatViewModel: Reaction removed successfully: \(response.message)")
                
                // Send reaction removal via WebSocket for real-time updates
                // Use the actual reaction type that was removed, not hardcoded thumbsUp
                if let userReaction = message.userReaction {
                    webSocketManager.sendReaction(messageId: serverMessageId, reactionType: userReaction, action: .remove)
                }
                
            } catch {
                print("❌ ChatViewModel: Failed to remove reaction: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to remove reaction: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Handle Incoming Message
    private func handleIncomingMessage(_ message: ChatMessage) {
        // Post notification that a new message was received (for any room)
        NotificationCenter.default.post(name: NSNotification.Name("NewMessageReceived"), object: nil, userInfo: ["message": message])
        
        // Only add message if it's for the current room
        if let currentRoomId = currentRoom?.id, message.roomId == currentRoomId {
            // Check if this is a server confirmation of a locally created message
            if let serverMessageId = message.serverMessageId {
                // Try to find a matching local message without server ID
                if let localMessageIndex = messages.firstIndex(where: { localMessage in
                    localMessage.serverMessageId == nil &&
                    localMessage.message == message.message &&
                    localMessage.sender == message.sender &&
                    abs(localMessage.timestamp.timeIntervalSince(message.timestamp)) < 10.0 // Within 10 seconds
                }) {
                    // Update the local message with the server message ID
                    var updatedMessage = messages[localMessageIndex]
                    updatedMessage.serverMessageId = serverMessageId
                    messages[localMessageIndex] = updatedMessage
                    
                    print("🔄 ChatViewModel: Updated local message with server ID: \(serverMessageId)")
                    return
                }
            }
            
            // Check if message already exists (avoid duplicates)
            let messageExists = messages.contains { existingMessage in
                existingMessage.message == message.message &&
                existingMessage.sender == message.sender &&
                abs(existingMessage.timestamp.timeIntervalSince(message.timestamp)) < 5.0 // Within 5 seconds
            }
            
            if !messageExists {
                messages.append(message)
                messages.sort { $0.timestamp < $1.timestamp }
            }
        }
    }
    
    // MARK: - Clear Error
    func clearError() {
        errorMessage = nil
        connectionError = nil
    }
    
    // MARK: - Get Current User
    func getCurrentUsername() -> String {
        return keychainService.getUsername() ?? "Unknown"
    }
    
    // MARK: - Check if Message is from Current User
    func isMessageFromCurrentUser(_ message: ChatMessage) -> Bool {
        let currentUser = getCurrentUsername()
        let isFromCurrent = message.sender == currentUser
        print("💬 ChatViewModel: Message sender: '\(message.sender)', Current user: '\(currentUser)', IsFromCurrent: \(isFromCurrent)")
        return isFromCurrent
    }
    
    // MARK: - Connectivity Check
    func checkConnectivityStatus() -> String {
        let status: String
        if isConnected {
            status = "✅ Connected"
        } else if let error = connectionError {
            status = "❌ Error: \(error)"
        } else {
            status = "⚠️ Disconnected"
        }
        
        return """
        WebSocket Status: \(status)
        Current Room: \(currentRoom?.name ?? "None")
        Last Check: \(Date().formatted(date: .omitted, time: .shortened))
        """
    }
    
    // MARK: - WebSocket Connection Management
    func disconnectFromWebSocket() {
        webSocketManager.disconnect()
    }
    
}
