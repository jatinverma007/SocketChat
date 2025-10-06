# Building a Real-Time Chat App with SwiftUI and WebSocket: A Complete Guide

*Create a production-ready messaging application with media sharing, typing indicators, and secure authentication*

---

## Introduction

Real-time communication is at the heart of modern mobile applications. Whether it's messaging, collaboration, or customer support, users expect instant, reliable communication. In this comprehensive guide, we'll build a full-featured chat application using SwiftUI and WebSocket technology.

## What We're Building

Our chat app will include:
- ✅ Real-time messaging with instant delivery
- ✅ Media sharing (images, videos, audio, documents)
- ✅ WhatsApp-style message reactions (👍❤️😂😮😢😡)
- ✅ Typing indicators and message status
- ✅ Secure JWT authentication with auto-refresh
- ✅ Modern SwiftUI interface
- ✅ File upload with progress tracking

## Architecture Overview

```
iOS Client (SwiftUI) ←→ WebSocket ←→ Backend API
       ↓                                    ↓
   Keychain Storage                    File Storage
```

The app follows MVVM architecture with reactive programming using Combine framework.

## 1. Project Setup

Start by creating a new SwiftUI project in Xcode and add these frameworks:
- `Combine` for reactive programming
- `AVFoundation` for audio recording
- `PhotosUI` for media selection

## 2. Core Data Models

First, let's define our data models:

```swift
struct ChatMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let sender: String
    let message: String
    let timestamp: Date
    let attachment: Attachment?
    let messageType: MessageType
}

struct Attachment: Codable {
    let type: AttachmentType
    let filename: String
    let url: String?
    let size: Int?
    let mimeType: String?
}

enum AttachmentType: String, Codable {
    case image, video, audio, document, file
}
```

## 3. WebSocket Manager

The heart of our real-time communication:

```swift
class ChatWebSocketManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var messageSubject = PassthroughSubject<ChatMessage, Never>()
    
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
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
    }
}
```

## 4. Authentication with Auto-Refresh

Secure authentication with automatic token refresh:

```swift
class AuthService: ObservableObject {
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
    
    // Automatic token refresh when API calls fail with 401
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        // Implementation handles token refresh automatically
    }
}
```

## 5. Real-Time Message Handling

Process incoming WebSocket messages:

```swift
private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    
    do {
        let decoder = JSONDecoder()
        
        if let webSocketMessage = try? decoder.decode(WebSocketMessage.self, from: data) {
            switch webSocketMessage.type {
            case "message":
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
                // Handle typing indicators
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

## 6. Modern SwiftUI Interface

Clean, responsive chat interface:

```swift
struct ChatView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var mediaCaptureService = MediaCaptureService.shared
    
    let room: ChatRoom
    @State private var messageText = ""
    
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
                .background(Color(.systemGray6))
            }
            
            // Message Input
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
}
```

## 7. Media Upload & Display

Handle file uploads with progress tracking:

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
        
        // Parse response and return filename
        return try parseUploadResponse(responseData)
    }
}
```

## 8. Automatic Token Refresh

Handle expired tokens seamlessly:

```swift
// Enhanced service with automatic token refresh
func getRooms(token: String) async throws -> [ChatRoom] {
    // ... make request ...
    
    guard httpResponse.statusCode == 200 else {
        // Handle 401 Unauthorized - try to refresh token
        if httpResponse.statusCode == 401 {
            if let newToken = await attemptTokenRefresh() {
                print("🔄 Token refreshed successfully, retrying request...")
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

## Key Features Implemented

### 🔄 Real-Time Communication
- **WebSocket connections** with automatic reconnection
- **Ping/pong mechanism** for connection health monitoring
- **Exponential backoff** for failed reconnection attempts

### 📱 Media Sharing
- **Image sharing** with full-screen preview
- **Video sharing** with thumbnail generation
- **Audio recording** with playback controls
- **Document sharing** with file type detection

### 😊 Message Reactions
- **WhatsApp-style reactions** with 6 emoji options (👍❤️😂😮😢😡)
- **Real-time reaction updates** via WebSocket
- **Long-press gesture** to show reaction picker
- **Reaction summaries** showing counts and users
- **Persistent reaction data** with database storage

### 🔐 Security
- **JWT token authentication** with automatic refresh
- **Secure keychain storage** for sensitive data
- **Input validation** and sanitization

### 🎨 User Experience
- **Typing indicators** for real-time feedback
- **Message status** tracking (sent, delivered)
- **Smooth animations** and transitions
- **Responsive design** for all screen sizes

## Best Practices

1. **Error Handling**: Comprehensive error types with user-friendly messages
2. **Performance**: Lazy loading and efficient memory management
3. **Security**: Secure token storage and HTTPS/WSS communications
4. **Accessibility**: VoiceOver support and inclusive design

## Message Reactions Implementation

### Reaction Models
```swift
enum ReactionType: String, CaseIterable, Codable {
    case thumbsUp = "👍"
    case heart = "❤️"
    case laugh = "😂"
    case surprised = "😮"
    case sad = "😢"
    case angry = "😡"
}

struct ReactionSummary: Codable {
    let reactionType: ReactionType
    let count: Int
    let users: [String]
}
```

### WebSocket Reaction Events
```swift
struct ReactionEvent: Codable {
    let type: String
    let roomId: Int
    let messageId: Int
    let sender: String
    let reactionType: ReactionType
    let reactionSummary: [ReactionSummary]
    let timestamp: String
}
```

### Reaction UI Components
```swift
struct ReactionPicker: View {
    @Binding var isPresented: Bool
    let messageId: Int
    let currentReaction: ReactionType?
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(ReactionType.allCases, id: \.self) { reactionType in
                Button(action: { handleReaction(reactionType) }) {
                    Text(reactionType.rawValue)
                        .font(.title2)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(currentReaction == reactionType ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color(.systemBackground))
                .shadow(radius: 10)
        )
    }
}
```

### Integration Steps
1. **Add reaction models** to your existing data structures
2. **Update WebSocket manager** to handle reaction events
3. **Create reaction UI components** for the picker and summaries
4. **Implement long-press gesture** on message bubbles
5. **Add reaction API endpoints** to your services
6. **Test real-time updates** across multiple devices

## Production Considerations

- **Push notifications** for offline message delivery
- **Message encryption** for enhanced security
- **Rate limiting** to prevent spam
- **Message persistence** with server-side storage
- **Analytics** for usage insights

## Conclusion

Building a real-time chat application with SwiftUI and WebSocket technology provides a solid foundation for modern communication features. The key components include:

- **Robust WebSocket management** with automatic reconnection
- **Secure authentication** with token refresh mechanisms
- **Efficient media handling** with upload progress tracking
- **Modern UI design** following SwiftUI best practices

This implementation demonstrates how to create production-ready real-time communication features that users expect in modern mobile applications.

---

**Want to see the complete implementation?** Check out the full codebase with all features, error handling, and production optimizations. The modular architecture makes it easy to extend with additional features like video calling, message encryption, or advanced formatting.

*What features would you like to add to your chat application? Let me know in the comments below!*

---

**Tags**: #SwiftUI #iOS #WebSocket #RealTime #Chat #MobileDevelopment #Swift
