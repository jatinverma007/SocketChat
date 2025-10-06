# Typing Indicator Debugging Guide

## Changes Made

### 1. Added Debug Logging
- **ChatView.swift**: Added extensive logging to track typing events
- **ChatViewModel.swift**: Added logging for typing indicator handling
- **ChatWebSocketManager.swift**: Added typing support to generic JSON parser

### 2. Fixed Generic JSON Parser
The WebSocket manager now handles typing events in both the structured parser and the generic JSON fallback parser.

## How to Test

### Step 1: Run the App on Two Devices/Simulators
1. Login with `admin` / `admin123` on first device
2. Login with `testuser2` / `password` on second device
3. Join the same chat room on both devices

### Step 2: Test Typing Indicator
1. On **Device 1 (admin)**: Start typing in the text field
2. On **Device 2 (testuser2)**: You should see "admin is typing..." appear below the messages
3. Wait 2 seconds without typing on Device 1
4. The indicator should disappear on Device 2

### Step 3: Check Console Logs
Look for these log messages:

#### When User Types:
```
⌨️ UI: Text changed, length: 1, isTyping: false
⌨️ UI: Sending typing START
⌨️ WebSocket: Sending typing indicator: started
✅ WebSocket: Typing indicator sent successfully
```

#### When Other User Receives:
```
⌨️ WebSocket: admin started typing
⌨️ ChatViewModel: Typing indicator - username: admin, isTyping: true
⌨️ ViewModel: Current user: testuser2
⌨️ ViewModel: Adding admin to typing users
⌨️ ViewModel: Current typing users: ["admin"]
👀 UI: Typing indicator showing: ["admin"]
```

#### When Typing Stops (after 2 seconds):
```
⌨️ UI: Timer expired, sending typing STOP
⌨️ WebSocket: Sending typing indicator: stopped
✅ WebSocket: Typing indicator sent successfully
```

#### When Other User Receives Stop:
```
⌨️ WebSocket: admin stopped typing
⌨️ ChatViewModel: Typing indicator - username: admin, isTyping: false
⌨️ ViewModel: Removing admin from typing users
⌨️ ViewModel: Current typing users: []
```

## Expected Behavior

### Visual Indicator
- Appears below messages list, above input bar
- Gray background with italic text
- Shows: "username is typing..."
- Smooth fade in/out animation

### Timing
- Starts when user types first character
- Continues as long as user is typing
- Stops after 2 seconds of inactivity
- Stops immediately when message is sent

### Multiple Users
- 1 user: "John is typing..."
- 2 users: "John and Mary are typing..."
- 3+ users: "John, Mary and 2 others are typing..."

## Troubleshooting

### Issue: Typing indicator not showing

**Check 1: WebSocket Connection**
- Ensure both devices are connected (green status or no error message)
- Check console for WebSocket connection messages

**Check 2: Server Support**
- Server must support `typing_start` and `typing_stop` message types
- Server must broadcast these events to all users in the room

**Check 3: Username Filtering**
- Typing indicator doesn't show for your own typing (by design)
- Must use different users on different devices

**Check 4: Room Matching**
- Both users must be in the same room
- Check `room_id` in WebSocket messages

### Issue: Typing indicator stuck

**Cause**: Network issue or app backgrounded during typing

**Solution**: 
- Indicator auto-clears after 2 seconds
- Sending a message also clears it
- Reconnecting to WebSocket clears all typing states

## Server Requirements

Your server must handle these WebSocket message types:

### Client to Server:
```json
{
  "type": "typing_start",
  "room_id": 1,
  "sender": "username"
}
```

```json
{
  "type": "typing_stop",
  "room_id": 1,
  "sender": "username"
}
```

### Server to Clients (broadcast to room):
```json
{
  "type": "typing_start",
  "room_id": 1,
  "sender": "username",
  "timestamp": "2025-10-01T12:00:00"
}
```

```json
{
  "type": "typing_stop",
  "room_id": 1,
  "sender": "username",
  "timestamp": "2025-10-01T12:00:05"
}
```

## Code Locations

- **UI**: `Chat/Views/ChatView.swift` (lines 84-101, 164-192)
- **ViewModel**: `Chat/ViewModels/ChatViewModel.swift` (lines 19, 51-58, 151-179)
- **WebSocket**: `Chat/Services/ChatWebSocketManager.swift` (lines 23-26, 299-315, 357-369, 451-480)
- **Models**: `Chat/Models/ChatMessage.swift` (lines 58-64)


