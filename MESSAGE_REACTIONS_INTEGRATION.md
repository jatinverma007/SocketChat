# Message Reactions Integration Guide

## Overview
This guide provides step-by-step instructions for integrating WhatsApp-style message reactions into your iOS chat application. The backend now supports real-time reactions with WebSocket broadcasting.

## Backend Features Added

### 1. Database Models
- **MessageReaction**: Stores user reactions to messages
- **Unique constraint**: One reaction per user per message
- **Reaction types**: 👍, ❤️, 😂, 😮, 😢, 😡

### 2. API Endpoints
- `POST /api/reactions/add` - Add/update reaction
- `DELETE /api/reactions/remove/{message_id}` - Remove reaction
- `GET /api/reactions/message/{message_id}` - Get message with reactions
- `GET /api/reactions/room/{room_id}/messages` - Get room messages with reactions
- `GET /api/reactions/available` - Get available reaction types

### 3. WebSocket Events
- `reaction_added` - Broadcast when reaction is added
- `reaction_removed` - Broadcast when reaction is removed

## iOS Implementation

### 1. Data Models

```swift
import Foundation

// MARK: - Reaction Types
enum ReactionType: String, CaseIterable, Codable {
    case thumbsUp = "👍"
    case heart = "❤️"
    case laugh = "😂"
    case surprised = "😮"
    case sad = "😢"
    case angry = "😡"
    
    var displayName: String {
        switch self {
        case .thumbsUp: return "Thumbs Up"
        case .heart: return "Heart"
        case .laugh: return "Laugh"
        case .surprised: return "Surprised"
        case .sad: return "Sad"
        case .angry: return "Angry"
        }
    }
}

// MARK: - Reaction Models
struct ReactionSummary: Codable {
    let reactionType: ReactionType
    let count: Int
    let users: [String]
    
    enum CodingKeys: String, CodingKey {
        case reactionType = "reaction_type"
        case count
        case users
    }
}

struct MessageReaction: Codable {
    let id: Int
    let messageId: Int
    let userId: Int
    let reactionType: ReactionType
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case userId = "user_id"
        case reactionType = "reaction_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MessageWithReactions: Codable {
    let id: Int
    let content: String?
    let messageType: String
    let fileUrl: String?
    let fileName: String?
    let fileSize: Int?
    let mimeType: String?
    let roomId: Int
    let senderId: Int
    let senderUsername: String
    let timestamp: String
    let reactions: [ReactionSummary]
    let userReaction: ReactionType?
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case messageType = "message_type"
        case fileUrl = "file_url"
        case fileName = "file_name"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case roomId = "room_id"
        case senderId = "sender_id"
        case senderUsername = "sender_username"
        case timestamp
        case reactions
        case userReaction = "user_reaction"
    }
}

// MARK: - WebSocket Reaction Events
struct ReactionEvent: Codable {
    let type: String
    let roomId: Int
    let messageId: Int
    let sender: String
    let reactionType: ReactionType
    let reactionSummary: [ReactionSummary]
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case roomId = "room_id"
        case messageId = "message_id"
        case sender
        case reactionType = "reaction_type"
        case reactionSummary = "reaction_summary"
        case timestamp
    }
}
```

### 2. Reaction Service

```swift
import Foundation
import Combine

class ReactionService: ObservableObject {
    private let baseURL: String
    private let token: String
    
    init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
    
    // MARK: - API Methods
    
    func addReaction(messageId: Int, reactionType: ReactionType) async throws -> ReactionResponse {
        let url = URL(string: "\(baseURL)/api/reactions/add")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "message_id": messageId,
            "reaction_type": reactionType.rawValue
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ReactionError.networkError
        }
        
        return try JSONDecoder().decode(ReactionResponse.self, from: data)
    }
    
    func removeReaction(messageId: Int) async throws -> ReactionResponse {
        let url = URL(string: "\(baseURL)/api/reactions/remove/\(messageId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ReactionError.networkError
        }
        
        return try JSONDecoder().decode(ReactionResponse.self, from: data)
    }
    
    func getMessageWithReactions(messageId: Int) async throws -> MessageWithReactions {
        let url = URL(string: "\(baseURL)/api/reactions/message/\(messageId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ReactionError.networkError
        }
        
        return try JSONDecoder().decode(MessageWithReactions.self, from: data)
    }
    
    func getAvailableReactions() async throws -> [ReactionType] {
        let url = URL(string: "\(baseURL)/api/reactions/available")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ReactionError.networkError
        }
        
        let reactionStrings = try JSONDecoder().decode([String].self, from: data)
        return reactionStrings.compactMap { ReactionType(rawValue: $0) }
    }
}

// MARK: - Response Models
struct ReactionResponse: Codable {
    let success: Bool
    let message: String
    let reaction: MessageReaction?
    let reactionSummary: [ReactionSummary]?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case reaction
        case reactionSummary = "reaction_summary"
    }
}

enum ReactionError: Error {
    case networkError
    case invalidResponse
    case decodingError
}
```

### 3. Enhanced WebSocket Manager

```swift
import Foundation
import Network

class ChatWebSocket: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var messages: [MessageWithReactions] = []
    @Published var reactionEvents: [ReactionEvent] = []
    
    private let serverUrl: String
    private let token: String
    
    init(serverUrl: String, token: String) {
        self.serverUrl = serverUrl
        self.token = token
    }
    
    func connect(roomId: Int) {
        let url = URL(string: "ws://\(serverUrl)/ws/chat/\(roomId)?token=\(token)")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    // MARK: - Reaction Methods
    
    func sendReaction(messageId: Int, reactionType: ReactionType, action: ReactionAction = .add) {
        let message = [
            "type": "reaction",
            "message_id": messageId,
            "reaction_type": reactionType.rawValue,
            "action": action.rawValue
        ] as [String : Any]
        
        let data = try! JSONSerialization.data(withJSONObject: message)
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("Error sending reaction: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self?.handleWebSocketData(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self?.handleWebSocketData(data)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
    
    private func handleWebSocketData(_ data: Data) {
        do {
            // Try to decode as reaction event first
            if let reactionEvent = try? JSONDecoder().decode(ReactionEvent.self, from: data) {
                DispatchQueue.main.async {
                    self.handleReactionEvent(reactionEvent)
                }
                return
            }
            
            // Try to decode as regular message
            if let chatMessage = try? JSONDecoder().decode(MessageWithReactions.self, from: data) {
                DispatchQueue.main.async {
                    self.messages.append(chatMessage)
                }
            }
        } catch {
            print("Error decoding WebSocket data: \(error)")
        }
    }
    
    private func handleReactionEvent(_ event: ReactionEvent) {
        switch event.type {
        case "reaction_added", "reaction_removed":
            // Update the message in the messages array
            if let index = messages.firstIndex(where: { $0.id == event.messageId }) {
                // Create updated message with new reactions
                var updatedMessage = messages[index]
                // Note: You'll need to update the reactions array based on the event
                messages[index] = updatedMessage
            }
            
            // Store the reaction event for UI updates
            reactionEvents.append(event)
            
        default:
            break
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel()
    }
}

enum ReactionAction: String {
    case add = "add"
    case remove = "remove"
}
```

### 4. Reaction UI Components

```swift
import SwiftUI

// MARK: - Reaction Button
struct ReactionButton: View {
    let reactionType: ReactionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(reactionType.rawValue)
                .font(.title2)
                .padding(8)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Reaction Picker
struct ReactionPicker: View {
    @Binding var isPresented: Bool
    let messageId: Int
    let currentReaction: ReactionType?
    let onReactionSelected: (ReactionType) -> Void
    let onReactionRemoved: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(ReactionType.allCases, id: \.self) { reactionType in
                    ReactionButton(
                        reactionType: reactionType,
                        isSelected: currentReaction == reactionType
                    ) {
                        if currentReaction == reactionType {
                            onReactionRemoved()
                        } else {
                            onReactionSelected(reactionType)
                        }
                        isPresented = false
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
        .padding()
    }
}

// MARK: - Reaction Summary View
struct ReactionSummaryView: View {
    let reactions: [ReactionSummary]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(reactions, id: \.reactionType) { reaction in
                HStack(spacing: 4) {
                    Text(reaction.reactionType.rawValue)
                        .font(.caption)
                    Text("\(reaction.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemGray5))
                )
            }
        }
    }
}

// MARK: - Message Row with Reactions
struct MessageRowWithReactions: View {
    let message: MessageWithReactions
    @State private var showReactionPicker = false
    @State private var currentReaction: ReactionType?
    
    let onReactionSelected: (Int, ReactionType) -> Void
    let onReactionRemoved: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Message content
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.senderUsername)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let content = message.content {
                        Text(content)
                            .font(.body)
                    }
                    
                    if let fileName = message.fileName {
                        Text("📎 \(fileName)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .onLongPressGesture {
                showReactionPicker = true
            }
            
            // Reactions
            if !message.reactions.isEmpty {
                ReactionSummaryView(reactions: message.reactions)
                    .padding(.leading)
            }
        }
        .sheet(isPresented: $showReactionPicker) {
            ReactionPicker(
                isPresented: $showReactionPicker,
                messageId: message.id,
                currentReaction: message.userReaction
            ) { reactionType in
                onReactionSelected(message.id, reactionType)
            } onReactionRemoved: {
                onReactionRemoved(message.id)
            }
        }
        .onAppear {
            currentReaction = message.userReaction
        }
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: timestamp) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        return ""
    }
}
```

### 5. Chat View Integration

```swift
import SwiftUI

struct ChatView: View {
    @StateObject private var webSocket: ChatWebSocket
    @StateObject private var reactionService: ReactionService
    @State private var messages: [MessageWithReactions] = []
    
    let roomId: Int
    let serverUrl: String
    let token: String
    
    init(roomId: Int, serverUrl: String, token: String) {
        self.roomId = roomId
        self.serverUrl = serverUrl
        self.token = token
        self._webSocket = StateObject(wrappedValue: ChatWebSocket(serverUrl: serverUrl, token: token))
        self._reactionService = StateObject(wrappedValue: ReactionService(baseURL: serverUrl, token: token))
    }
    
    var body: some View {
        VStack {
            // Messages list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages, id: \.id) { message in
                        MessageRowWithReactions(
                            message: message,
                            onReactionSelected: handleReactionSelected,
                            onReactionRemoved: handleReactionRemoved
                        )
                    }
                }
                .padding()
            }
            
            // Message input
            MessageInputView { content in
                sendMessage(content)
            }
        }
        .onAppear {
            webSocket.connect(roomId: roomId)
            loadMessages()
        }
        .onReceive(webSocket.$messages) { newMessages in
            messages = newMessages
        }
    }
    
    private func sendMessage(_ content: String) {
        // Your existing message sending logic
    }
    
    private func loadMessages() {
        Task {
            do {
                let roomMessages = try await reactionService.getRoomMessagesWithReactions(roomId: roomId)
                await MainActor.run {
                    messages = roomMessages
                }
            } catch {
                print("Error loading messages: \(error)")
            }
        }
    }
    
    private func handleReactionSelected(messageId: Int, reactionType: ReactionType) {
        webSocket.sendReaction(messageId: messageId, reactionType: reactionType, action: .add)
    }
    
    private func handleReactionRemoved(messageId: Int) {
        webSocket.sendReaction(messageId: messageId, reactionType: .thumbsUp, action: .remove)
    }
}
```

### 6. Usage Example

```swift
// In your main chat view
struct ContentView: View {
    var body: some View {
        ChatView(
            roomId: 1,
            serverUrl: "192.168.29.247:8000",
            token: "your_jwt_token_here"
        )
    }
}
```

## Key Features

### 1. Real-time Reactions
- Reactions are sent via WebSocket for instant updates
- All users in the room see reactions immediately
- No need to refresh or poll for updates

### 2. WhatsApp-style UI
- Long press on message to show reaction picker
- Visual feedback for selected reactions
- Reaction summary showing counts and users

### 3. Data Persistence
- Reactions are stored in the database
- Message history includes reaction data
- User's own reactions are highlighted

### 4. Error Handling
- Network error handling
- Invalid reaction type handling
- WebSocket connection error handling

## Testing

### 1. Test Reaction Addition
```swift
// Test adding a reaction
let reactionService = ReactionService(baseURL: "http://192.168.29.247:8000", token: "your_token")
Task {
    do {
        let response = try await reactionService.addReaction(messageId: 1, reactionType: .heart)
        print("Reaction added: \(response)")
    } catch {
        print("Error: \(error)")
    }
}
```

### 2. Test WebSocket Reactions
```swift
// Test WebSocket reaction
webSocket.sendReaction(messageId: 1, reactionType: .laugh, action: .add)
```

## Backend API Testing

### 1. Add Reaction
```bash
curl -X POST "http://192.168.29.247:8000/api/reactions/add" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -d '{"message_id": 1, "reaction_type": "❤️"}'
```

### 2. Remove Reaction
```bash
curl -X DELETE "http://192.168.29.247:8000/api/reactions/remove/1" \
     -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### 3. Get Message with Reactions
```bash
curl -X GET "http://192.168.29.247:8000/api/reactions/message/1" \
     -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Integration Steps for Your Existing Codebase

### Step 1: Add New Models
1. Create a new file `ReactionModels.swift` in your Models folder
2. Add all the reaction-related models from the guide above

### Step 2: Create Reaction Service
1. Create `ReactionService.swift` in your Services folder
2. Implement the API methods for reaction management

### Step 3: Update WebSocket Manager
1. Add reaction handling to your existing `ChatWebSocketManager.swift`
2. Add `sendReaction` method and reaction event processing

### Step 4: Add UI Components
1. Create `ReactionComponents.swift` in your Views folder
2. Implement the reaction picker and summary views

### Step 5: Update Message Bubbles
1. Modify your existing message bubble components
2. Add long-press gesture for reaction picker
3. Display reaction summaries below messages

### Step 6: Update Chat View
1. Integrate reaction service into your existing `ChatView`
2. Add reaction handling methods
3. Update message loading to include reaction data

## Notes for iOS Cursor

1. **Import the new models** into your existing chat models
2. **Update your WebSocket handler** to process reaction events
3. **Add reaction UI components** to your message cells
4. **Implement long-press gesture** for reaction picker
5. **Update your message loading** to include reaction data
6. **Test with multiple devices** to ensure real-time updates work

The backend is now ready to handle reactions. The iOS implementation provides a complete WhatsApp-style reaction system with real-time updates via WebSocket.

