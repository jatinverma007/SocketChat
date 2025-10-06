//
//  ChatWebSocketManager.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import Combine
import Network

class ChatWebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var messageSubject = PassthroughSubject<ChatMessage, Never>()
    var messagePublisher: AnyPublisher<ChatMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    private var typingSubject = PassthroughSubject<(String, Bool), Never>() // (username, isTyping)
    var typingPublisher: AnyPublisher<(String, Bool), Never> {
        typingSubject.eraseToAnyPublisher()
    }
    
    private var reactionSubject = PassthroughSubject<ReactionEvent, Never>()
    var reactionPublisher: AnyPublisher<ReactionEvent, Never> {
        reactionSubject.eraseToAnyPublisher()
    }
    
    // Debug: Track message publishing
    private var publishedMessageCount = 0
    
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    // Store connection parameters for automatic reconnection
    private var lastToken: String?
    private var lastRoomId: String?
    
    // Token refresh handling
    private let keychainService = KeychainService.shared
    
    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var isNetworkAvailable = true
    
    // MARK: - Connection Management
    func connect(token: String, roomId: String = "general") {
        // Store connection parameters for reconnection
        lastToken = token
        lastRoomId = roomId
        
        // Start network monitoring if not already started
        startNetworkMonitoring()
        
        // Construct the WebSocket URL properly
        let wsURL = "\(ServerConfig.wsChat)/\(roomId)?token=\(token)"
        print("🔌 WebSocket: Constructed URL: \(wsURL)")
        print("🔌 WebSocket: Base wsChat URL: \(ServerConfig.wsChat)")
        print("🔌 WebSocket: Server IP: \(ServerConfig.serverIP)")
        print("🔌 WebSocket: Server Port: \(ServerConfig.serverPort)")
        print("🔌 WebSocket: wsBaseURL: \(ServerConfig.wsBaseURL)")
        
        guard let url = URL(string: wsURL) else {
            print("❌ WebSocket: Invalid WebSocket URL: \(wsURL)")
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        print("🔌 WebSocket: Parsed URL scheme: \(url.scheme ?? "nil")")
        print("🔌 WebSocket: Parsed URL host: \(url.host ?? "nil")")
        print("🔌 WebSocket: Parsed URL port: \(url.port ?? -1)")
        print("🔌 WebSocket: Parsed URL path: \(url.path)")
        
        // Validate that we're using the correct WebSocket scheme
        guard url.scheme == "ws" else {
            print("❌ WebSocket: Invalid scheme '\(url.scheme ?? "nil")' - expected 'ws'")
            connectionError = "Invalid WebSocket scheme"
            return
        }
        
        print("🔌 WebSocket: Final URL: \(url.absoluteString)")
        print("🔌 WebSocket: Token: \(token.prefix(20))...")
        
        // Always disconnect existing connection first
        if webSocketTask != nil {
            print("🔌 WebSocket: Disconnecting existing connection")
            disconnect()
        }
        
        // Create URLSession with proper configuration for WebSocket
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // Increased to 60 seconds
        config.timeoutIntervalForResource = 120 // Increased to 2 minutes
        config.waitsForConnectivity = true      // Wait for network connectivity
        config.allowsCellularAccess = true      // Allow cellular connections
        urlSession = URLSession(configuration: config)
        webSocketTask = urlSession?.webSocketTask(with: url)
        
        // Add connection state monitoring
        webSocketTask?.resume()
        
        // Store connection parameters for potential reconnection
        lastToken = token
        lastRoomId = roomId
        
        // Reset connection state
        isConnected = false
        connectionError = nil
        reconnectAttempts = 0
        
        print("🔌 WebSocket: Connection attempt started")
        print("🔌 WebSocket: Task state: \(webSocketTask?.state.rawValue ?? -1)")
        
        // Start receiving messages
        receiveMessage()
        
        // Set up a timer to check connection status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkConnectionStatus()
        }
    }
    
    func disconnect() {
        print("🔌 WebSocket: Disconnecting...")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        print("🔌 WebSocket: Disconnected")
    }
    
    // MARK: - Connection Status Monitoring
    private func checkConnectionStatus() {
        guard let task = webSocketTask else {
            print("🔌 WebSocket: No task to check status")
            return
        }
        
        print("🔌 WebSocket: Checking connection status...")
        print("🔌 WebSocket: Task state: \(task.state.rawValue)")
        print("🔌 WebSocket: Is connected: \(isConnected)")
        
        switch task.state {
        case .running:
            print("🔌 WebSocket: Task is running")
            if !isConnected {
                print("🔌 WebSocket: Task running but not marked as connected - waiting for first message")
            }
        case .suspended:
            print("🔌 WebSocket: Task is suspended")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        case .canceling:
            print("🔌 WebSocket: Task is canceling")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        case .completed:
            print("🔌 WebSocket: Task is completed")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        @unknown default:
            print("🔌 WebSocket: Unknown task state: \(task.state.rawValue)")
        }
    }
    
    // MARK: - Reconnect
    func reconnect(token: String, roomId: String = "general") {
        print("🔌 WebSocket: Manual reconnect requested")
        disconnect()
        connect(token: token, roomId: roomId)
    }
    
    // MARK: - Auto Reconnect (uses stored parameters)
    func autoReconnect() {
        guard let token = lastToken, let roomId = lastRoomId else {
            print("❌ WebSocket: Cannot auto-reconnect - missing connection parameters")
            return
        }
        print("🔌 WebSocket: Auto-reconnect requested")
        disconnect()
        connect(token: token, roomId: roomId)
    }
    
    // MARK: - Debug Information
    func getDebugInfo() -> String {
        return """
        WebSocket Debug Info:
        - Is Connected: \(isConnected)
        - Task State: \(webSocketTask?.state.rawValue ?? -1)
        - Messages Published: \(publishedMessageCount)
        - Last Token: \(lastToken?.prefix(20) ?? "nil")...
        - Last Room ID: \(lastRoomId ?? "nil")
        """
    }
    
    // MARK: - Connection Health Check
    func checkAndFixConnection(token: String, roomId: String = "general") {
        print("🔌 WebSocket: Checking connection health...")
        
        guard let task = webSocketTask else {
            print("🔌 WebSocket: No task exists - reconnecting")
            connect(token: token, roomId: roomId)
            return
        }
        
        switch task.state {
        case .running:
            if !isConnected {
                print("🔌 WebSocket: Task running but not connected - this might be a state issue")
                // Try to send a ping to test the connection
                sendPing()
            } else {
                print("🔌 WebSocket: Connection appears healthy")
            }
        case .suspended, .canceling, .completed:
            print("🔌 WebSocket: Task in bad state (\(task.state.rawValue)) - reconnecting")
            connect(token: token, roomId: roomId)
        @unknown default:
            print("🔌 WebSocket: Unknown task state - reconnecting")
            connect(token: token, roomId: roomId)
        }
    }
    
    // MARK: - Message Handling
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Mark as connected when we receive the first message
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if !self.isConnected {
                        self.isConnected = true
                        self.connectionError = nil
                        print("🔌 WebSocket: Connection established - starting ping timer")
                        self.startPingTimer()
                    }
                }
                
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
                self?.handleConnectionError(error)
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        print("🔌 WebSocket: Received message: \(text)")
        guard let data = text.data(using: .utf8) else { 
            print("❌ WebSocket: Failed to convert message to data")
            return 
        }
        
        do {
            let decoder = JSONDecoder()
            // Don't set date decoding strategy for WebSocket messages since they might not have timestamps
            
            // Try to parse as WebSocketMessage first (most common)
            print("🔌 WebSocket: Attempting to decode as WebSocketMessage...")
            if let webSocketMessage = try? decoder.decode(WebSocketMessage.self, from: data) {
                print("🔌 WebSocket: Successfully decoded WebSocketMessage")
                print("🔌 WebSocket: Parsed WebSocketMessage - Type: \(webSocketMessage.type), Room: \(webSocketMessage.room_id ?? -1), Sender: \(webSocketMessage.sender ?? "unknown"), Content: \(webSocketMessage.messageContent)")
                print("🔌 WebSocket: File data - URL: \(webSocketMessage.file_url ?? "nil"), Name: \(webSocketMessage.file_name ?? "nil"), Type: \(webSocketMessage.message_type ?? "nil")")
                
                // Process different message types
                switch webSocketMessage.type {
                case "message":
                    // This is a chat message
                    var attachment: Attachment? = nil
                    
                    // Process attachment data if present (check both formats)
                    if let wsAttachment = webSocketMessage.attachment {
                        // Format 1: Attachment object
                        let attachmentType: Attachment.AttachmentType
                        switch wsAttachment.type {
                        case "image": attachmentType = .image
                        case "video": attachmentType = .video
                        case "audio": attachmentType = .audio
                        case "document": attachmentType = .document
                        default: attachmentType = .file
                        }
                        
                        attachment = Attachment(
                            type: attachmentType,
                            filename: wsAttachment.filename ?? "",
                            url: wsAttachment.url,
                            size: wsAttachment.size,
                            mimeType: wsAttachment.mime_type
                        )
                        
                        print("🔌 WebSocket: Processed attachment object - Type: \(attachmentType), URL: \(wsAttachment.url ?? "nil")")
                    } else if let fileUrl = webSocketMessage.file_url, 
                              let fileName = webSocketMessage.file_name, 
                              !fileUrl.isEmpty, !fileName.isEmpty {
                        // Format 2: Direct file fields in message
                        let attachmentType: Attachment.AttachmentType
                        if let mimeType = webSocketMessage.mime_type {
                            if mimeType.hasPrefix("image/") {
                                attachmentType = .image
                            } else if mimeType.hasPrefix("video/") {
                                attachmentType = .video
                            } else if mimeType.hasPrefix("audio/") {
                                attachmentType = .audio
                            } else {
                                attachmentType = .document
                            }
                        } else if let messageType = webSocketMessage.message_type {
                            switch messageType {
                            case "image": attachmentType = .image
                            case "video": attachmentType = .video
                            case "audio": attachmentType = .audio
                            case "document": attachmentType = .document
                            default: attachmentType = .file
                            }
                        } else {
                            attachmentType = .file
                        }
                        
                        attachment = Attachment(
                            type: attachmentType,
                            filename: fileName,
                            url: fileUrl,
                            size: webSocketMessage.file_size,
                            mimeType: webSocketMessage.mime_type
                        )
                        
                        print("🔌 WebSocket: Processed direct file fields - Type: \(attachmentType), URL: \(fileUrl)")
                    }
                    
                    // Determine message type
                    let messageType: MessageType
                    if let attachment = attachment {
                        let hasText = !webSocketMessage.messageContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        messageType = MessageType.fromAttachment(attachment, hasText: hasText)
                    } else {
                        messageType = .text
                    }
                    
                    let chatMessage = ChatMessage(
                        id: "server_\(webSocketMessage.message_id)", // Use server message ID as local ID for consistency
                        serverMessageId: webSocketMessage.message_id, // Use actual message_id from server
                        roomId: String(webSocketMessage.room_id ?? -1),
                        sender: webSocketMessage.sender ?? "unknown",
                        message: webSocketMessage.messageContent,
                        timestamp: Date(),
                        attachment: attachment,
                        messageType: messageType,
                        reactions: [], // Initialize with empty reactions
                        userReaction: nil // Initialize with no user reaction
                    )
                    
                    print("🔌 WebSocket: Publishing chat message to UI - \(chatMessage.message)")
                    self.publishedMessageCount += 1
                    print("🔌 WebSocket: Total messages published: \(self.publishedMessageCount)")
                    DispatchQueue.main.async {
                        print("🔌 WebSocket: Sending chat message to subject on main queue")
                        self.messageSubject.send(chatMessage)
                        print("🔌 WebSocket: Chat message sent to subject successfully")
                    }
                    
                case "user_joined":
                    // User joined notification - don't display in chat
                    print("🔌 WebSocket: User joined notification received - not displaying in chat")
                    // Skip publishing user join messages to the UI
                
                case "typing_start":
                    // User started typing
                    if let sender = webSocketMessage.sender {
                        print("⌨️ WebSocket: \(sender) started typing")
                        DispatchQueue.main.async {
                            self.typingSubject.send((sender, true))
                        }
                    }
                
                case "typing_stop":
                    // User stopped typing
                    if let sender = webSocketMessage.sender {
                        print("⌨️ WebSocket: \(sender) stopped typing")
                        DispatchQueue.main.async {
                            self.typingSubject.send((sender, false))
                        }
                    }
                
                case "reaction_added", "reaction_removed":
                    // Handle reaction events
                    print("🔖 WebSocket: Reaction event received - \(webSocketMessage.type)")
                    // Try to decode as ReactionEvent
                    if let reactionEvent = try? decoder.decode(ReactionEvent.self, from: data) {
                        print("🔖 WebSocket: Successfully decoded ReactionEvent")
                        DispatchQueue.main.async {
                            self.reactionSubject.send(reactionEvent)
                        }
                    } else {
                        print("❌ WebSocket: Failed to decode ReactionEvent")
                    }
                    
                default:
                    print("🔌 WebSocket: Unknown message type: \(webSocketMessage.type)")
                }
            } else {
                print("❌ WebSocket: Failed to decode as WebSocketMessage, trying other parsers...")
            }
            
            // Try to parse as connection message (only for type "connected")
            if let connectionMessage = try? decoder.decode(WebSocketConnectionMessage.self, from: data),
                    connectionMessage.type == "connected" {
                print("🔌 WebSocket: Connection message - \(connectionMessage.message) - not displaying in chat")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.connectionError = nil
                    // Reset reconnection attempts on successful connection
                    self.reconnectAttempts = 0
                    self.reconnectTimer?.invalidate()
                    self.reconnectTimer = nil
                }
                // Don't publish connection messages to the UI
            }
            
            // Try to parse as error message
            if let errorMessage = try? decoder.decode(WebSocketErrorMessage.self, from: data) {
                print("⚠️ WebSocket: Parsed as error message - Type: \(errorMessage.type), Message: \(errorMessage.message)")
                print("⚠️ WebSocket: Error message - \(errorMessage.message)")
                DispatchQueue.main.async {
                    self.connectionError = errorMessage.message
                }
            }
            
            // Try to parse as generic message format (fallback)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let type = json["type"] as? String {
                print("🔌 WebSocket: Parsed as generic message format - Type: \(type)")
                
                let roomId = json["room_id"] as? Int ?? -1
                let messageId = json["message_id"] as? Int
                let sender = json["sender"] as? String ?? "unknown"
                let content = json["content"] as? String ?? json["message"] as? String ?? ""
                
                // Handle different message types
                switch type {
                case "message":
                    // Process attachment data if present
                    var attachment: Attachment? = nil
                    
                    // Check for direct file fields
                    if let fileUrl = json["file_url"] as? String,
                       let fileName = json["file_name"] as? String,
                       !fileUrl.isEmpty, !fileName.isEmpty {
                        
                        let messageType = json["message_type"] as? String ?? "file"
                        let fileSize = json["file_size"] as? Int
                        let mimeType = json["mime_type"] as? String
                        
                        let attachmentType: Attachment.AttachmentType
                        if let mimeType = mimeType {
                            if mimeType.hasPrefix("image/") {
                                attachmentType = .image
                            } else if mimeType.hasPrefix("video/") {
                                attachmentType = .video
                            } else if mimeType.hasPrefix("audio/") {
                                attachmentType = .audio
                            } else {
                                attachmentType = .document
                            }
                        } else {
                            // Fallback to message_type
                            switch messageType {
                            case "image": attachmentType = .image
                            case "video": attachmentType = .video
                            case "audio": attachmentType = .audio
                            case "document": attachmentType = .document
                            default: attachmentType = .file
                            }
                        }
                        
                        // Convert relative URL to absolute URL
                        let absoluteUrl = fileUrl.hasPrefix("http") ? fileUrl : "http://\(ServerConfig.serverIP):\(ServerConfig.serverPort)\(fileUrl)"
                        
                        attachment = Attachment(
                            type: attachmentType,
                            filename: fileName,
                            url: absoluteUrl,
                            size: fileSize,
                            mimeType: mimeType
                        )
                        
                        print("🔌 WebSocket: Generic parser - Created attachment - Type: \(attachmentType), URL: \(absoluteUrl)")
                    }
                    
                    // Determine message type
                    let messageType: MessageType
                    if let attachment = attachment {
                        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        messageType = MessageType.fromAttachment(attachment, hasText: hasText)
                    } else {
                        messageType = .text
                    }
                    
                    let chatMessage = ChatMessage(
                        id: "server_\(messageId)", // Use server message ID as local ID for consistency
                        serverMessageId: messageId, // Use actual message_id from server
                        roomId: String(roomId),
                        sender: sender,
                        message: content,
                        timestamp: Date(),
                        attachment: attachment,
                        messageType: messageType
                    )
                    
                    print("🔌 WebSocket: Publishing generic chat message to UI - \(chatMessage.message)")
                    self.publishedMessageCount += 1
                    DispatchQueue.main.async {
                        self.messageSubject.send(chatMessage)
                    }
                    
                case "user_joined":
                    // User joined notification - don't display in chat
                    print("🔌 WebSocket: Generic parser - User joined notification received - not displaying in chat")
                    // Skip publishing user join messages to the UI
                    
                case "connected":
                    // Connection confirmation - don't display in chat
                    print("🔌 WebSocket: Generic parser - Connection message received - not displaying in chat")
                    // Skip publishing connection messages to the UI
                
                case "typing_start":
                    // User started typing
                    print("⌨️ WebSocket: Generic parser - User started typing")
                    DispatchQueue.main.async {
                        self.typingSubject.send((sender, true))
                    }
                
                case "typing_stop":
                    // User stopped typing
                    print("⌨️ WebSocket: Generic parser - User stopped typing")
                    DispatchQueue.main.async {
                        self.typingSubject.send((sender, false))
                    }
                
                case "reaction_added", "reaction_removed":
                    // Handle reaction events in generic parser
                    print("🔖 WebSocket: Generic parser - Reaction event received - \(type)")
                    // Try to decode as ReactionEvent
                    if let reactionEvent = try? decoder.decode(ReactionEvent.self, from: data) {
                        print("🔖 WebSocket: Generic parser - Successfully decoded ReactionEvent")
                        DispatchQueue.main.async {
                            self.reactionSubject.send(reactionEvent)
                        }
                    } else {
                        print("❌ WebSocket: Generic parser - Failed to decode ReactionEvent")
                    }
                    
                default:
                    print("🔌 WebSocket: Generic parser - Unknown message type: \(type)")
                }
            }
            else {
                print("❌ WebSocket: Unknown message format: \(text)")
                // Try to parse as generic JSON to see what fields are available
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔌 WebSocket: Available JSON fields: \(json.keys)")
                }
            }
        } catch {
            print("❌ WebSocket: Failed to parse message: \(error)")
            print("❌ WebSocket: Raw message: \(text)")
            // Try to parse as generic JSON to see what fields are available
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🔌 WebSocket: Available JSON fields: \(json.keys)")
            }
        }
    }
    
    // MARK: - Send Message
    func sendMessage(roomId: String, message: String, sender: String = "admin") {
        // Check if we have a valid WebSocket task
        guard let task = webSocketTask else {
            print("❌ WebSocket: Cannot send message - no WebSocket task")
            DispatchQueue.main.async {
                self.connectionError = "WebSocket task not available"
            }
            return
        }
        
        // Check task state
        print("🔌 WebSocket: Task state before send: \(task.state.rawValue)")
        print("🔌 WebSocket: Is connected: \(isConnected)")
        
        // Only send if task is running
        guard task.state == .running else {
            print("❌ WebSocket: Cannot send message - task state is \(task.state.rawValue)")
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionError = "WebSocket task not running"
            }
            return
        }
        
        let messageData = [
            "type": "message",
            "room_id": Int(roomId) ?? 0,
            "content": message,
            "sender": sender
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            print("🔌 WebSocket: Sending message: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
            
            task.send(message) { [weak self] error in
                if let error = error {
                    print("❌ WebSocket: Failed to send message: \(error)")
                    DispatchQueue.main.async {
                        self?.isConnected = false
                        self?.connectionError = "Failed to send message: \(error.localizedDescription)"
                    }
                } else {
                    print("✅ WebSocket: Message sent successfully")
                    // Check connection status after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let self = self {
                            print("🔌 WebSocket: Connection status after send: \(self.isConnected)")
                            if let task = self.webSocketTask {
                                print("🔌 WebSocket: Task state after send: \(task.state.rawValue)")
                            }
                        }
                    }
                }
            }
        } catch {
            print("❌ WebSocket: Failed to encode message: \(error)")
            DispatchQueue.main.async {
                self.connectionError = "Failed to encode message"
            }
        }
    }
    
    // MARK: - Send Message with Attachment
    func sendMessageWithAttachment(roomId: String, message: String, sender: String, attachment: Attachment?, messageType: MessageType) {
        // Check if we have a valid WebSocket task
        guard let task = webSocketTask else {
            print("❌ WebSocket: Cannot send message - no WebSocket task")
            DispatchQueue.main.async {
                self.connectionError = "WebSocket task not available"
            }
            return
        }
        
        // Check task state
        print("🔌 WebSocket: Task state before send: \(task.state.rawValue)")
        print("🔌 WebSocket: Is connected: \(isConnected)")
        
        // Only send if task is running
        guard task.state == .running else {
            print("❌ WebSocket: Cannot send message - task state is \(task.state.rawValue)")
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionError = "WebSocket task not running"
            }
            return
        }
        
        var messageData: [String: Any] = [
            "type": "message",
            "room_id": Int(roomId) ?? 0,
            "content": message,
            "sender": sender,
            "message_type": messageType.rawValue
        ]
        
        // Add attachment info if present
        if let attachment = attachment {
            let attachmentData: [String: Any] = [
                "type": attachment.type.rawValue,
                "filename": attachment.filename,
                "url": attachment.url ?? "",
                "size": attachment.size ?? 0,
                "mime_type": attachment.mimeType ?? ""
            ]
            messageData["attachment"] = attachmentData
            
            print("🔌 WebSocket: Sending attachment data:")
            print("🔌   - Type: \(attachment.type.rawValue)")
            print("🔌   - Filename: \(attachment.filename)")
            print("🔌   - URL: \(attachment.url ?? "nil")")
            print("🔌   - Size: \(attachment.size ?? 0)")
            print("🔌   - MIME: \(attachment.mimeType ?? "nil")")
        } else {
            print("🔌 WebSocket: No attachment data to send")
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "Unable to encode"
            print("🔌 WebSocket: Complete message being sent:")
            print("🔌 \(jsonString)")
            
            // Pretty print the JSON for easier debugging
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("🔌 Formatted JSON:")
                print(prettyString)
            }
            
            task.send(message) { [weak self] error in
                if let error = error {
                    print("❌ WebSocket: Failed to send message with attachment: \(error)")
                    DispatchQueue.main.async {
                        self?.isConnected = false
                        self?.connectionError = "Failed to send message: \(error.localizedDescription)"
                    }
                } else {
                    print("✅ WebSocket: Message with attachment sent successfully")
                    // Check connection status after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let self = self {
                            print("🔌 WebSocket: Connection status after send: \(self.isConnected)")
                            if let task = self.webSocketTask {
                                print("🔌 WebSocket: Task state after send: \(task.state.rawValue)")
                            }
                        }
                    }
                }
            }
        } catch {
            print("❌ WebSocket: Failed to serialize message with attachment: \(error)")
            DispatchQueue.main.async {
                self.connectionError = "Failed to serialize message: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Send Reaction
    func sendReaction(messageId: Int, reactionType: ReactionType, action: ReactionAction = .add) {
        guard let task = webSocketTask else {
            print("❌ WebSocket: Cannot send reaction - no WebSocket task")
            return
        }
        
        guard task.state == .running else {
            print("❌ WebSocket: Cannot send reaction - WebSocket not running (state: \(task.state.rawValue))")
            return
        }
        
        guard isConnected else {
            print("❌ WebSocket: Cannot send reaction - not connected (isConnected: \(isConnected))")
            return
        }
        
        let reactionData = [
            "type": "reaction",
            "message_id": messageId,
            "reaction_type": reactionType.rawValue,
            "action": action.rawValue
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: reactionData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            print("🔖 WebSocket: Sending reaction: \(action.rawValue) \(reactionType.rawValue) for message \(messageId)")
            
            task.send(message) { [weak self] error in
                if let error = error {
                    print("❌ WebSocket: Failed to send reaction: \(error)")
                    DispatchQueue.main.async {
                        self?.connectionError = "Failed to send reaction: \(error.localizedDescription)"
                    }
                } else {
                    print("✅ WebSocket: Reaction sent successfully")
                }
            }
        } catch {
            print("❌ WebSocket: Failed to encode reaction: \(error)")
            DispatchQueue.main.async {
                self.connectionError = "Failed to encode reaction"
            }
        }
    }
    
    // MARK: - Send Typing Indicator
    func sendTypingIndicator(roomId: String, isTyping: Bool, sender: String) {
        guard let task = webSocketTask, task.state == .running else {
            print("❌ WebSocket: Cannot send typing indicator - not connected")
            return
        }
        
        let typingData = [
            "type": isTyping ? "typing_start" : "typing_stop",
            "room_id": Int(roomId) ?? 0,
            "sender": sender
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: typingData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            print("⌨️ WebSocket: Sending typing indicator: \(isTyping ? "started" : "stopped")")
            
            task.send(message) { error in
                if let error = error {
                    print("❌ WebSocket: Failed to send typing indicator: \(error)")
                } else {
                    print("✅ WebSocket: Typing indicator sent successfully")
                }
            }
        } catch {
            print("❌ WebSocket: Failed to encode typing indicator: \(error)")
        }
    }
    
    // MARK: - Subscribe to Room (Deprecated - server handles room subscription via URL)
    func subscribeToRoom(_ roomId: String) {
        // No longer needed - server handles room subscription via the WebSocket URL
        print("🔌 WebSocket: Room subscription handled by server via URL")
    }
    
    // MARK: - Error Handling & Reconnection
    private func handleConnectionError(_ error: Error) {
        print("❌ WebSocket: Connection error: \(error)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionError = error.localizedDescription
        }
        
        // Handle timeout errors specifically
        if let nsError = error as? NSError {
            if nsError.domain == "NSURLErrorDomain" && nsError.code == -1001 {
                print("❌ WebSocket: Request timeout - attempting reconnection")
                scheduleReconnect()
                return
            } else if nsError.domain == "NSURLErrorDomain" && nsError.code == -1004 {
                print("❌ WebSocket: Could not connect to server - server may be down")
                scheduleReconnect()
                return
            } else if nsError.domain == "NSURLErrorDomain" && nsError.code == -1009 {
                print("❌ WebSocket: No internet connection")
                scheduleReconnect()
                return
            }
        }
        
        // Check if this is a socket disconnection error
        if let posixError = error as? NSError, posixError.domain == "NSPOSIXErrorDomain" {
            switch posixError.code {
            case 53: // Software caused connection abort
                print("❌ WebSocket: Connection aborted by server - attempting reconnection")
                // This is likely a server-side timeout or intentional disconnection
                // Attempt to reconnect after a short delay
                if let token = self.lastToken, let roomId = self.lastRoomId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("🔌 WebSocket: Auto-reconnecting after server abort...")
                        self.connect(token: token, roomId: roomId)
                    }
                } else {
                    print("❌ WebSocket: Cannot auto-reconnect - missing connection parameters")
                }
            case 57: // Socket is not connected
                print("❌ WebSocket: Socket disconnected - server closed connection")
                print("❌ WebSocket: This might be due to token expiration or server restart")
                // Attempt to reconnect after a delay for socket disconnection
                if let token = self.lastToken, let roomId = self.lastRoomId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        print("🔌 WebSocket: Attempting reconnection after socket disconnect...")
                        self.connect(token: token, roomId: roomId)
                    }
                }
            case 54: // Connection reset by peer
                print("❌ WebSocket: Connection reset by peer")
            default:
                print("❌ WebSocket: POSIX error code: \(posixError.code)")
            }
        }
        
        // Don't attempt to reconnect for certain errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                if reconnectAttempts < maxReconnectAttempts {
                    scheduleReconnect()
                }
            default:
                print("❌ WebSocket: Not attempting reconnect for error: \(urlError.code)")
            }
        }
    }
    
    // MARK: - Ping/Pong for Connection Keep-Alive
    private func startPingTimer() {
        pingTimer?.invalidate()
        // Send ping every 15 seconds to keep connection alive
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        guard let task = webSocketTask, task.state == .running else {
            print("🔌 WebSocket: Cannot send ping - task not running")
            return
        }
        
        print("🔌 WebSocket: Sending ping")
        task.sendPing { [weak self] error in
            if let error = error {
                print("❌ WebSocket: Ping failed: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.connectionError = "Ping failed: \(error.localizedDescription)"
                }
            } else {
                print("✅ WebSocket: Ping successful")
            }
        }
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ WebSocket: Max reconnection attempts reached - stopping reconnection attempts")
            DispatchQueue.main.async {
                self.connectionError = "Connection failed after \(self.maxReconnectAttempts) attempts"
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0) // Exponential backoff, max 60 seconds
        
        print("🔌 WebSocket: Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        // Cancel any existing reconnect timer
        reconnectTimer?.invalidate()
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Check if we're still disconnected before attempting reconnection
            guard !self.isConnected else {
                print("🔌 WebSocket: Already connected, canceling reconnection attempt")
                return
            }
            
            if let token = self.lastToken, let roomId = self.lastRoomId {
                print("🔌 WebSocket: Attempting reconnection... (attempt \(self.reconnectAttempts))")
                self.connect(token: token, roomId: roomId)
            } else {
                print("❌ WebSocket: Cannot reconnect - missing connection parameters")
            }
        }
    }
    
    // MARK: - Network Monitoring
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasAvailable = self?.isNetworkAvailable ?? false
                self?.isNetworkAvailable = path.status == .satisfied
                
                print("🌐 Network status: \(path.status)")
                
                // If network became available and we were disconnected, try to reconnect
                if self?.isNetworkAvailable == true && wasAvailable == false {
                    print("🌐 Network restored - attempting to reconnect WebSocket")
                    if let token = self?.lastToken, let roomId = self?.lastRoomId {
                        self?.connect(token: token, roomId: roomId)
                    }
                } else if self?.isNetworkAvailable == false {
                    print("🌐 Network lost - WebSocket connection will be affected")
                    self?.connectionError = "No network connection"
                }
            }
        }
        
        networkMonitor.start(queue: networkQueue)
    }
    
    private func stopNetworkMonitoring() {
        networkMonitor.cancel()
    }
    
    // MARK: - Connection Management
    func resetConnectionState() {
        print("🔌 WebSocket: Resetting connection state")
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionError = nil
        }
    }
    
    func reconnectWithFreshToken() {
        print("🔌 WebSocket: Attempting to reconnect with fresh token")
        
        // Get fresh token from keychain
        guard let freshToken = keychainService.getToken(),
              let roomId = lastRoomId else {
            print("❌ WebSocket: Cannot reconnect - missing token or room ID")
            return
        }
        
        // Update stored token
        lastToken = freshToken
        
        // Disconnect current connection
        disconnect()
        
        // Reconnect with fresh token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connect(token: freshToken, roomId: roomId)
        }
    }
    
    deinit {
        stopNetworkMonitoring()
        disconnect()
    }
}
