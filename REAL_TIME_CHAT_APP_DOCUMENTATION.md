# Building a Real-Time Chat Application with SwiftUI and WebSocket

## Table of Contents
1. [Introduction](#introduction)
2. [Project Overview](#project-overview)
3. [Architecture](#architecture)
4. [Core Components](#core-components)
5. [Implementation Guide](#implementation-guide)
6. [Key Features](#key-features)
7. [WebSocket Implementation](#websocket-implementation)
8. [Media Upload & Display](#media-upload--display)
9. [Authentication & Token Management](#authentication--token-management)
10. [Best Practices](#best-practices)
11. [Conclusion](#conclusion)

## Introduction

In this comprehensive guide, we'll explore how to build a fully-featured real-time chat application using SwiftUI and WebSocket technology. This modern chat app includes text messaging, media sharing (images, videos, audio, documents), real-time typing indicators, and robust authentication with automatic token refresh.

## Project Overview

### What We're Building
- **Real-time messaging** with instant message delivery
- **Media sharing** supporting images, videos, audio, and documents
- **Typing indicators** showing when users are typing
- **Secure authentication** with JWT tokens and automatic refresh
- **File upload** with progress tracking and error handling
- **Modern SwiftUI interface** with responsive design

### Technology Stack
- **Frontend**: SwiftUI (iOS 15+)
- **Backend**: Node.js/Express with WebSocket support
- **Authentication**: JWT tokens with refresh token mechanism
- **File Storage**: Local file serving with upload capabilities
- **Real-time Communication**: WebSocket connections

## Architecture

### High-Level Architecture
```
┌─────────────────┐    WebSocket     ┌─────────────────┐
│   iOS Client    │ ◄─────────────► │   Backend API   │
│   (SwiftUI)     │                 │   (Node.js)     │
└─────────────────┘                 └─────────────────┘
         │                                   │
         │ HTTP/REST                        │
         ▼                                   ▼
┌─────────────────┐                 ┌─────────────────┐
│   Keychain      │                 │   File Storage  │
│   (Secure)      │                 │   (Uploads)     │
└─────────────────┘                 └─────────────────┘
```

### iOS App Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                        │
├─────────────────────────────────────────────────────────┤
│                   ViewModels                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │AuthViewModel│ │ChatViewModel│ │RoomViewModel│      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
├─────────────────────────────────────────────────────────┤
│                    Services                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │AuthService  │ │WebSocketMgr │ │MessageService│      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
├─────────────────────────────────────────────────────────┤
│                    Models                               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │   User      │ │ChatMessage  │ │ ChatRoom    │      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Data Models

#### ChatMessage Model
```swift
struct ChatMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let sender: String
    let message: String
    let timestamp: Date
    let attachment: Attachment?
    let messageType: MessageType
    
    init(id: String = UUID().uuidString, 
         roomId: String, 
         sender: String, 
         message: String, 
         timestamp: Date = Date(), 
         attachment: Attachment? = nil, 
         messageType: MessageType = .text) {
        self.id = id
        self.roomId = roomId
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
        self.attachment = attachment
        self.messageType = messageType
    }
}
```

#### Attachment Model
```swift
struct Attachment: Codable {
    let type: AttachmentType
    let filename: String
    let url: String?
    let size: Int?
    let mimeType: String?
    let thumbnailUrl: String?
    let duration: Double?
    let width: Int?
    let height: Int?
}

enum AttachmentType: String, Codable {
    case image = "image"
    case video = "video"
    case audio = "audio"
    case document = "document"
    case file = "file"
}
```

### 2. WebSocket Manager

#### Core WebSocket Implementation
```swift
class ChatWebSocketManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var typingUsers: [String] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var messageSubject = PassthroughSubject<ChatMessage, Never>()
    private var typingSubject = PassthroughSubject<(String, Bool), Never>()
    
    func connect(token: String, roomId: Int) {
        let url = URL(string: "\(ServerConfig.wsBaseURL)/ws/chat/\(roomId)?token=\(token)")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        setupWebSocketSubscriptions()
        startPingTimer()
    }
    
    private func setupWebSocketSubscriptions() {
        messageSubject
            .sink { [weak self] message in
                // Handle incoming messages
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
    }
}
```

### 3. Authentication System

#### JWT Token Management
```swift
class AuthService: ObservableObject {
    private let session: URLSession
    
    func login(username: String, password: String) async throws -> AuthResponse {
        let url = URL(string: ServerConfig.authLogin)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let loginRequest = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(loginRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.loginFailed
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        let url = URL(string: ServerConfig.authRefresh)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let refreshRequest = RefreshTokenRequest(refresh_token: refreshToken)
        request.httpBody = try JSONEncoder().encode(refreshRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.refreshTokenFailed
        }
        
        return try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
    }
}
```

## Implementation Guide

### Step 1: Project Setup

1. **Create a new SwiftUI project** in Xcode
2. **Add required frameworks**:
   - `Combine` for reactive programming
   - `AVFoundation` for audio recording
   - `PhotosUI` for media selection

3. **Project structure**:
```
ChatApp/
├── Models/
│   ├── ChatMessage.swift
│   ├── ChatRoom.swift
│   └── User.swift
├── Services/
│   ├── AuthService.swift
│   ├── ChatWebSocketManager.swift
│   ├── MessageService.swift
│   └── RoomService.swift
├── ViewModels/
│   ├── AuthViewModel.swift
│   └── ChatViewModel.swift
└── Views/
    ├── ChatView.swift
    ├── LoginView.swift
    └── MessageBubbleComponents.swift
```

### Step 2: Configure Server Settings

```swift
struct ServerConfig {
    static let serverIP = "172.20.10.2"  // Your server IP
    static let serverPort = "8000"
    
    static let httpBaseURL = "http://\(serverIP):\(serverPort)"
    static let wsBaseURL = "ws://\(serverIP):\(serverPort)"
    
    // API Endpoints
    static let authLogin = "\(httpBaseURL)/api/auth/login"
    static let authRefresh = "\(httpBaseURL)/api/auth/refresh"
    static let rooms = "\(httpBaseURL)/api/rooms"
    static let messages = "\(httpBaseURL)/api/messages"
    static let wsChat = "\(wsBaseURL)/ws/chat"
    
    // File handling
    static let uploadFile = "\(httpBaseURL)/api/upload-file"
    static let fileServing = "\(httpBaseURL)/api/files"
    static let maxFileSize = 10 * 1024 * 1024 // 10MB
}
```

### Step 3: Implement WebSocket Connection

#### WebSocket Message Handling
```swift
private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    
    do {
        let decoder = JSONDecoder()
        
        // Try to parse as WebSocketMessage first (most common)
        if let webSocketMessage = try? decoder.decode(WebSocketMessage.self, from: data) {
            switch webSocketMessage.type {
            case "message":
                // Process chat message
                let chatMessage = ChatMessage(
                    id: UUID().uuidString,
                    roomId: String(webSocketMessage.room_id ?? -1),
                    sender: webSocketMessage.sender ?? "unknown",
                    message: webSocketMessage.messageContent,
                    timestamp: Date(),
                    attachment: processAttachment(from: webSocketMessage),
                    messageType: determineMessageType(from: webSocketMessage)
                )
                
                DispatchQueue.main.async {
                    self.messageSubject.send(chatMessage)
                }
                
            case "typing_start":
                // Handle typing indicator
                if let sender = webSocketMessage.sender {
                    DispatchQueue.main.async {
                        self.typingSubject.send((sender, true))
                    }
                }
                
            default:
                print("Unknown message type: \(webSocketMessage.type)")
            }
        }
    } catch {
        print("Failed to parse WebSocket message: \(error)")
    }
}
```

### Step 4: Create Chat Interface

#### Main Chat View
```swift
struct ChatView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var mediaCaptureService = MediaCaptureService.shared
    @StateObject private var fileUploadService = FileUploadService.shared
    
    let room: ChatRoom
    @State private var messageText = ""
    @State private var showingMediaPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chatViewModel.messages) { message in
                            EnhancedMessageBubbleView(
                                message: message, 
                                isFromCurrentUser: chatViewModel.isMessageFromCurrentUser(message)
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: chatViewModel.messages.count) { _ in
                    if let lastMessage = chatViewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            // Typing Indicator
            if !chatViewModel.typingUsers.isEmpty {
                HStack {
                    Text("\(chatViewModel.typingUsers.joined(separator: ", ")) is typing...")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
            }
            
            // Message Input Area
            HStack {
                Button(action: { showingMediaPicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                TextField("Message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...5)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(18)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .navigationTitle(room.name)
        .onAppear {
            chatViewModel.joinRoom(room)
        }
    }
    
    private func sendMessage() {
        chatViewModel.sendMessage(messageText)
        messageText = ""
    }
}
```

## Key Features

### 1. Real-Time Messaging
- **Instant delivery** using WebSocket connections
- **Message persistence** with server-side storage
- **Typing indicators** for better user experience
- **Message status** tracking (sent, delivered, read)

### 2. Media Sharing
- **Image sharing** with preview and full-screen view
- **Video sharing** with thumbnail preview
- **Audio recording** with playback controls
- **Document sharing** with file type detection
- **File upload progress** tracking

### 3. Authentication & Security
- **JWT token-based** authentication
- **Automatic token refresh** to prevent session expiry
- **Secure keychain storage** for sensitive data
- **Session management** with logout functionality

### 4. User Experience
- **Modern SwiftUI interface** with smooth animations
- **Responsive design** for different screen sizes
- **Error handling** with user-friendly messages
- **Offline support** with message queuing

## WebSocket Implementation

### Connection Management
```swift
class ChatWebSocketManager: ObservableObject {
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    func connect(token: String, roomId: Int) {
        let url = URL(string: "\(ServerConfig.wsBaseURL)/ws/chat/\(roomId)?token=\(token)")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        setupWebSocketSubscriptions()
        startPingTimer()
        startNetworkMonitoring()
    }
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else { return }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let token = self.lastToken, let roomId = self.lastRoomId {
                self.connect(token: token, roomId: roomId)
            }
        }
    }
}
```

### Message Types
```swift
// WebSocket Message Models
struct WebSocketMessage: Codable {
    let type: String
    let room_id: Int?
    let sender: String?
    let content: String?
    let message: String?
    let timestamp: String?
    let attachment: WebSocketAttachment?
    let message_type: String?
    
    // Direct file fields
    let file_url: String?
    let file_name: String?
    let file_size: Int?
    let mime_type: String?
    
    var messageContent: String {
        if let content = content, !content.isEmpty {
            return content
        } else {
            return message ?? ""
        }
    }
}
```

## Media Upload & Display

### File Upload Service
```swift
class FileUploadService: ObservableObject {
    @Published var uploadProgress: [String: UploadProgress] = [:]
    
    func uploadFile(_ data: Data, filename: String, mimeType: String) async throws -> String {
        let uploadId = UUID().uuidString
        let url = URL(string: ServerConfig.uploadFile)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UploadError.uploadFailed
        }
        
        if let responseString = String(data: responseData, encoding: .utf8),
           let responseData = responseString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let filename = json["filename"] as? String {
            return filename
        }
        
        throw UploadError.invalidResponse
    }
}
```

### Media Display Components
```swift
struct ImageOnlyBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    @Binding var showingFullScreen: Bool
    
    var body: some View {
        if let attachment = message.attachment,
           let urlString = attachment.url,
           let url = URL(string: getFullImageURL(from: urlString)) {
            
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .onTapGesture {
                        showingFullScreen = true
                    }
            } placeholder: {
                ProgressView()
                    .frame(height: 200)
            }
            .frame(maxHeight: 300)
        } else {
            imageFallbackView
        }
    }
    
    private func getFullImageURL(from urlString: String) -> String {
        if urlString.hasPrefix("http") {
            return urlString
        } else {
            return "\(ServerConfig.httpBaseURL)\(urlString)"
        }
    }
}
```

## Authentication & Token Management

### Automatic Token Refresh
```swift
// Enhanced RoomService with automatic token refresh
func getRooms(token: String) async throws -> [ChatRoom] {
    // ... make request ...
    
    guard httpResponse.statusCode == 200 else {
        // Handle 401 Unauthorized - try to refresh token
        if httpResponse.statusCode == 401 {
            if let newToken = await attemptTokenRefresh() {
                return try await getRooms(token: newToken)
            } else {
                throw RoomError.unauthorized
            }
        }
        throw RoomError.fetchFailed
    }
    
    // ... handle response ...
}

private func attemptTokenRefresh() async -> String? {
    let keychainService = KeychainService.shared
    let authService = AuthService()
    
    guard let refreshToken = keychainService.getRefreshToken() else {
        return nil
    }
    
    do {
        let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken)
        
        // Update tokens in keychain
        keychainService.saveToken(refreshResponse.access_token)
        if let newRefreshToken = refreshResponse.refresh_token {
            keychainService.saveRefreshToken(newRefreshToken)
        }
        
        return refreshResponse.access_token
    } catch {
        return nil
    }
}
```

### Secure Keychain Storage
```swift
class KeychainService {
    static let shared = KeychainService()
    
    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"
    private let usernameKey = "username"
    
    func saveToken(_ token: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
}
```

## Best Practices

### 1. Error Handling
- **Comprehensive error types** for different failure scenarios
- **User-friendly error messages** with actionable suggestions
- **Automatic retry mechanisms** for transient failures
- **Graceful degradation** when services are unavailable

### 2. Performance Optimization
- **Lazy loading** for message history
- **Image caching** for media files
- **Background processing** for file uploads
- **Memory management** with proper cleanup

### 3. Security Considerations
- **Secure token storage** using Keychain Services
- **Input validation** for all user data
- **HTTPS/WSS** for all network communications
- **Regular token refresh** to minimize exposure

### 4. User Experience
- **Responsive design** for different screen sizes
- **Smooth animations** for state transitions
- **Offline support** with message queuing
- **Accessibility** features for inclusive design

## Conclusion

Building a real-time chat application with SwiftUI and WebSocket technology requires careful attention to several key areas:

1. **Robust WebSocket management** with automatic reconnection
2. **Secure authentication** with token refresh mechanisms
3. **Efficient media handling** with upload progress tracking
4. **Modern UI design** with SwiftUI best practices
5. **Comprehensive error handling** for production readiness

This implementation provides a solid foundation for building scalable, real-time communication features in iOS applications. The modular architecture makes it easy to extend with additional features like video calling, file sharing, or advanced message formatting.

### Key Takeaways
- **WebSocket connections** provide real-time communication with automatic reconnection
- **JWT tokens** offer secure authentication with automatic refresh
- **SwiftUI** enables rapid UI development with reactive programming
- **Modular architecture** supports easy testing and maintenance
- **Comprehensive error handling** ensures production-ready quality

### Next Steps
- Add **push notifications** for offline message delivery
- Implement **message encryption** for enhanced security
- Add **video calling** capabilities using WebRTC
- Create **admin panels** for user and room management
- Add **message reactions** and **threading** features

This chat application demonstrates the power of modern iOS development tools and provides a comprehensive example of real-time communication implementation.

---

*This documentation covers the complete implementation of a production-ready chat application. The code examples are taken from a working project and can be adapted for your specific requirements.*

