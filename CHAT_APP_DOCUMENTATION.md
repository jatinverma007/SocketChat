# Chat App Documentation

## Overview
This is a real-time chat application built with SwiftUI that supports multiple chat rooms, user authentication, and WebSocket-based real-time messaging.

## Architecture

### Key Components
- **Models**: Data structures for messages, rooms, and users
- **Services**: API and WebSocket communication
- **ViewModels**: Business logic and state management
- **Views**: SwiftUI user interface components

---

## 1. Fetching Chat Messages

### MessageService.swift
The `MessageService` handles all message-related API operations.

#### Key Methods:

```swift
// Fetch all messages for a specific room
func fetchMessages(roomId: String, token: String) async throws -> [ChatMessage]

// Fetch recent messages (with pagination)
func fetchRecentMessages(roomId: String, limit: Int = 50, token: String) async throws -> [ChatMessage]
```

#### Implementation Details:

```swift
func fetchMessages(roomId: String, token: String) async throws -> [ChatMessage] {
    guard let url = URL(string: "\(ServerConfig.baseURL)/api/messages/\(roomId)") else {
        throw MessageServiceError.invalidURL
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw MessageServiceError.requestFailed
    }
    
    // Parse server response to ChatMessage objects
    let serverMessages = try JSONDecoder().decode([ServerMessage].self, from: data)
    return serverMessages.map { $0.toChatMessage() }
}
```

#### Usage in ChatViewModel:
```swift
func loadMessages() {
    Task {
        do {
            let messages = try await messageService.fetchMessages(
                roomId: currentRoomId, 
                token: getCurrentToken()
            )
            await MainActor.run {
                self.messages = messages
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
            }
        }
    }
}
```

---

## 2. Fetching Chat Rooms

### RoomService.swift
The `RoomService` handles all room-related API operations.

#### Key Methods:

```swift
// Fetch all available chat rooms
func fetchRooms(token: String) async throws -> [ChatRoom]

// Create a new chat room
func createRoom(name: String, token: String) async throws -> ChatRoom

// Join a specific room
func joinRoom(roomId: String, token: String) async throws -> Bool
```

#### Implementation Details:

```swift
func fetchRooms(token: String) async throws -> [ChatRoom] {
    guard let url = URL(string: "\(ServerConfig.baseURL)/api/rooms") else {
        throw RoomServiceError.invalidURL
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw RoomServiceError.requestFailed
    }
    
    return try JSONDecoder().decode([ChatRoom].self, from: data)
}
```

#### Usage in ChatRoomView:
```swift
func loadRooms() {
    Task {
        await MainActor.run { isLoadingRooms = true }
        
        do {
            let rooms = try await roomService.fetchRooms(token: getCurrentToken())
            await MainActor.run {
                self.availableRooms = rooms
                self.isLoadingRooms = false
            }
        } catch {
            await MainActor.run {
                self.roomError = "Failed to load rooms: \(error.localizedDescription)"
                self.isLoadingRooms = false
            }
        }
    }
}
```

---

## 3. WebSocket Connection

### ChatWebSocketManager.swift
The `ChatWebSocketManager` handles real-time WebSocket communication.

#### Key Properties:
```swift
@Published var isConnected = false
@Published var connectionError: String?
private var webSocketTask: URLSessionWebSocketTask?
private var messagePublisher = PassthroughSubject<ChatMessage, Never>()
```

#### Connection Process:

```swift
func connect(token: String, roomId: String = "general") {
    // 1. Disconnect existing connection
    disconnect()
    
    // 2. Construct WebSocket URL
    let urlString = "\(ServerConfig.wsBaseURL)/ws/chat/\(roomId)?token=\(token)"
    guard let url = URL(string: urlString) else {
        connectionError = "Invalid WebSocket URL"
        return
    }
    
    // 3. Create WebSocket task
    webSocketTask = URLSession.shared.webSocketTask(with: url)
    
    // 4. Start connection
    webSocketTask?.resume()
    
    // 5. Start receiving messages
    receiveMessage()
    
    // 6. Start ping timer for keep-alive
    startPingTimer()
}
```

#### Message Handling:

```swift
private func receiveMessage() {
    webSocketTask?.receive { [weak self] result in
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                self?.handleMessage(text)
            case .data(let data):
                // Handle binary data if needed
                break
            @unknown default:
                break
            }
            // Continue receiving messages
            self?.receiveMessage()
            
        case .failure(let error):
            self?.handleConnectionError(error)
        }
    }
}
```

#### Message Parsing:

```swift
private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    
    do {
        let decoder = JSONDecoder()
        
        // Try to parse as WebSocketMessage
        if let webSocketMessage = try? decoder.decode(WebSocketMessage.self, from: data) {
            switch webSocketMessage.type {
            case "message":
                let chatMessage = ChatMessage(
                    id: UUID().uuidString,
                    roomId: String(webSocketMessage.room_id ?? 0),
                    sender: webSocketMessage.sender ?? "",
                    message: webSocketMessage.content,
                    timestamp: Date()
                )
                messagePublisher.send(chatMessage)
                
            case "user_joined":
                // Handle user join notifications (filtered out from UI)
                print("User joined: \(webSocketMessage.sender ?? "Unknown")")
                
            default:
                print("Unknown message type: \(webSocketMessage.type)")
            }
        }
    } catch {
        print("Failed to parse WebSocket message: \(error)")
    }
}
```

#### Sending Messages:

```swift
func sendMessage(_ message: String) {
    guard isConnected, let task = webSocketTask else {
        print("❌ WebSocket: Cannot send message - not connected")
        return
    }
    
    let messageData = [
        "type": "message",
        "room_id": currentRoomId,
        "sender": getCurrentUsername(),
        "content": message
    ]
    
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: messageData)
        let message = URLSessionWebSocketTask.Message.data(jsonData)
        
        task.send(message) { [weak self] error in
            if let error = error {
                print("❌ WebSocket: Failed to send message: \(error)")
            } else {
                print("✅ WebSocket: Message sent successfully")
            }
        }
    } catch {
        print("❌ WebSocket: Failed to encode message: \(error)")
    }
}
```

---

## 4. Data Models

### ChatMessage.swift
```swift
struct ChatMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let sender: String
    let message: String
    let timestamp: Date
}

struct WebSocketMessage: Codable {
    let type: String
    let room_id: Int?
    let sender: String?
    let content: String
    let timestamp: String?
}

struct ServerMessage: Codable {
    let room_id: Int
    let sender: String
    let message: String
    let timestamp: String
    
    func toChatMessage() -> ChatMessage {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let date = dateFormatter.date(from: timestamp) ?? Date()
        
        return ChatMessage(
            id: UUID().uuidString,
            roomId: String(room_id),
            sender: sender,
            message: message,
            timestamp: date
        )
    }
}
```

### ChatRoom.swift
```swift
struct ChatRoom: Codable, Identifiable {
    let id: String
    let name: String
    let created_at: String?
    
    // Custom decoder to handle both string and numeric IDs from server
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let stringId = try? container.decode(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int for id"))
        }
        
        self.name = try container.decode(String.self, forKey: .name)
        self.created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
    }
}
```

---

## 5. Server Configuration

### ServerConfig.swift
```swift
struct ServerConfig {
    // Use localhost for iOS Simulator
    // For physical device, change to your computer's IP address
    static let serverIP = "localhost"
    static let serverPort = "8000"
    
    static var httpBaseURL: String {
        return "http://\(serverIP):\(serverPort)"
    }
    
    static var wsBaseURL: String {
        return "ws://\(serverIP):\(serverPort)"
    }
}
```

**Note**: 
- Use `localhost` when testing in the iOS Simulator
- Use your computer's IP address (e.g., `192.168.x.x`) when testing on a physical device
- Find your IP: `ifconfig | grep "inet " | grep -v 127.0.0.1`

---

## 6. Authentication Flow

### AuthService.swift
```swift
// Login
func login(username: String, password: String) async throws -> AuthResponse

// Signup
func signup(username: String, password: String) async throws -> AuthResponse

// Store token in Keychain
func storeToken(_ token: String, for username: String)

// Retrieve token from Keychain
func getToken(for username: String) -> String?
```

---

## 7. Usage Flow

### Complete Chat Flow:

1. **Authentication**:
   ```swift
   let authResponse = try await authService.login(username: "user", password: "pass")
   authService.storeToken(authResponse.access_token, for: "user")
   ```

2. **Load Rooms**:
   ```swift
   let rooms = try await roomService.fetchRooms(token: token)
   ```

3. **Join Room & Connect WebSocket**:
   ```swift
   chatViewModel.joinRoom(selectedRoom)
   // This triggers WebSocket connection and loads messages
   ```

4. **Send Message**:
   ```swift
   chatViewModel.sendMessage("Hello World!")
   // Message is sent via WebSocket and appears in real-time
   ```

5. **Receive Messages**:
   ```swift
   // WebSocket automatically receives and publishes new messages
   // ChatViewModel subscribes to messagePublisher and updates UI
   ```

---

## 8. Error Handling

### Common Error Types:
- **Network Errors**: Connection timeouts, server unavailable
- **Authentication Errors**: Invalid credentials, expired tokens
- **WebSocket Errors**: Connection drops, message parsing failures
- **JSON Decoding Errors**: Malformed server responses

### Error Recovery:
- **Auto-reconnection**: WebSocket automatically reconnects on connection drops
- **Retry Logic**: Failed API calls can be retried with exponential backoff
- **User Feedback**: Error messages displayed to users with retry options

---

## 9. Key Features

### Real-time Messaging:
- WebSocket-based instant message delivery
- Automatic reconnection on connection drops
- Ping/pong keep-alive mechanism

### Multi-room Support:
- Fetch and display multiple chat rooms
- Create new rooms
- Join/leave rooms dynamically

### User Authentication:
- Secure token-based authentication
- Keychain storage for tokens
- Automatic token refresh

### Message History:
- Fetch historical messages when joining rooms
- Pagination support for large message histories
- Proper timestamp handling

---

## 10. Testing

### Test Credentials:
```
Username: admin
Password: admin123

Username: testuser2
Password: password
```

### Server Endpoints:
- **Login**: `POST /api/auth/login`
- **Signup**: `POST /api/auth/signup`
- **Get Rooms**: `GET /api/rooms`
- **Get Messages**: `GET /api/messages/{room_id}`
- **WebSocket**: `ws://{server}/ws/chat/{room_id}?token={token}`

This documentation covers the core functionality of the chat application. The code is structured to be modular, testable, and maintainable with clear separation of concerns between data, business logic, and presentation layers.
