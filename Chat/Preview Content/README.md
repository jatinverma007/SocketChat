# SwiftUI Chat App

A real-time chat application built with SwiftUI that integrates with a local Spring Boot backend using WebSocket connections.

## Features

- **Authentication**: Sign up and login with JWT token storage in Keychain
- **Real-time Messaging**: WebSocket-based chat with instant message delivery
- **Multiple Chat Rooms**: Join different chat rooms (General, Random, Tech Talk, Gaming)
- **Message History**: Load previous messages when joining a room
- **Modern UI**: Clean SwiftUI interface with message bubbles and smooth animations
- **Auto-scroll**: Automatically scroll to latest messages
- **Connection Status**: Visual indicators for WebSocket connection status
- **Error Handling**: Comprehensive error handling for network issues

## Architecture

- **MVVM Pattern**: Clean separation of concerns with ViewModels
- **Combine Framework**: Reactive programming for data flow
- **URLSession**: REST API calls for authentication and message fetching
- **URLSessionWebSocketTask**: WebSocket connections for real-time messaging
- **Keychain Services**: Secure token storage

## Project Structure

```
ChatApp/
├── Models/
│   ├── User.swift              # User model and auth request/response
│   ├── ChatMessage.swift       # Message model and WebSocket message types
│   └── ChatRoom.swift          # Chat room model with default rooms
├── Services/
│   ├── AuthService.swift       # Authentication API calls
│   ├── MessageService.swift    # Message fetching API calls
│   ├── ChatWebSocketManager.swift # WebSocket connection management
│   └── KeychainService.swift   # Secure token storage
├── ViewModels/
│   ├── AuthViewModel.swift     # Authentication state management
│   └── ChatViewModel.swift     # Chat functionality and WebSocket handling
├── Views/
│   ├── LoginView.swift         # Login/signup interface
│   ├── ChatRoomView.swift      # Room selection interface
│   └── ChatView.swift          # Chat interface with message bubbles
├── ChatApp.swift               # Main app entry point
└── ContentView.swift           # Root view with authentication routing
```

## Backend Requirements

This app expects a Spring Boot backend running locally with the following endpoints:

### REST Endpoints
- `POST /signup` - User registration
- `POST /login` - User authentication (returns JWT)
- `GET /api/messages/{roomId}` - Fetch message history

### WebSocket Endpoint
- `ws://localhost:8080/ws/chat?token={jwt}` - WebSocket connection with JWT authentication

### Expected Message Format
```json
{
  "type": "MESSAGE",
  "roomId": "general",
  "sender": "username",
  "message": "Hello world!",
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

## Setup Instructions

### 1. Backend Setup
First, ensure your Spring Boot backend is running locally:

```bash
# Start your Spring Boot application
./mvnw spring-boot:run
# or
java -jar your-app.jar
```

The backend should be accessible at:
- REST API: `http://localhost:8080`
- WebSocket: `ws://localhost:8080/ws/chat`

### 2. iOS App Setup

1. **Open in Xcode**: Open the project in Xcode 15+ with iOS 17+ deployment target

2. **Configure Network Security**: Add network security settings to `Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

3. **Build and Run**: Select your target device/simulator and run the app

### 3. Testing the App

1. **Sign Up**: Create a new account with username and password
2. **Login**: Use your credentials to sign in
3. **Join Room**: Select a chat room from the list
4. **Send Messages**: Type and send messages in real-time
5. **Test Multiple Users**: Open the app on multiple devices/simulators to test multi-user chat

## Key Features Implementation

### Authentication Flow
1. User enters credentials in `LoginView`
2. `AuthViewModel` calls `AuthService` for login/signup
3. JWT token is stored securely in Keychain
4. User is redirected to `ChatRoomView`

### Real-time Messaging
1. `ChatViewModel` connects to WebSocket via `ChatWebSocketManager`
2. User joins a room, subscribes to room-specific messages
3. Messages are sent via WebSocket and received in real-time
4. UI updates automatically using Combine publishers

### Message Display
- **Message Bubbles**: Different styling for sent vs received messages
- **Auto-scroll**: Automatically scrolls to latest message
- **Timestamps**: Shows time for each message
- **Sender Names**: Displays sender name for received messages

### Error Handling
- **Network Errors**: Graceful handling of connection failures
- **Authentication Errors**: Clear error messages for login issues
- **WebSocket Errors**: Automatic reconnection attempts with exponential backoff

## Customization

### Adding New Chat Rooms
Edit `ChatRoom.defaultRooms` in `Models/ChatRoom.swift`:

```swift
static let defaultRooms: [ChatRoom] = [
    ChatRoom(id: "general", name: "General"),
    ChatRoom(id: "random", name: "Random"),
    ChatRoom(id: "tech", name: "Tech Talk"),
    ChatRoom(id: "gaming", name: "Gaming"),
    ChatRoom(id: "newroom", name: "New Room") // Add your room here
]
```

### Styling Customization
- **Colors**: Modify bubble colors in `MessageBubbleView`
- **Fonts**: Update font styles in the view files
- **Layout**: Adjust spacing and padding in SwiftUI views

### Backend Integration
- **API Endpoints**: Update base URLs in service files
- **Message Format**: Modify WebSocket message parsing in `ChatWebSocketManager`
- **Authentication**: Adjust JWT handling in `AuthService`

## Troubleshooting

### Common Issues

1. **Connection Refused**: Ensure Spring Boot backend is running on localhost:8080
2. **WebSocket Connection Failed**: Check JWT token format and WebSocket URL
3. **Messages Not Loading**: Verify REST API endpoints are working
4. **Authentication Issues**: Check username/password requirements

### Debug Tips

1. **Enable Logging**: Add print statements in service files for debugging
2. **Check Network**: Use network debugging tools to inspect API calls
3. **WebSocket Testing**: Use WebSocket testing tools to verify backend connection
4. **Simulator vs Device**: Test on both simulator and physical device

## Requirements

- **iOS**: 17.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Backend**: Spring Boot with WebSocket support
- **Network**: Local network access for backend communication

## License

This project is for educational purposes. Feel free to use and modify as needed.