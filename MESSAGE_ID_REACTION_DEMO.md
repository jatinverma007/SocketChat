# Message ID and Reaction Integration Demo

## Overview
This document demonstrates how the message IDs from your server response are now properly integrated with the reaction system.

## Your Server Data
Your server is sending messages with the following structure:
```json
{
  "message_id": 1,
  "room_id": 1,
  "sender": "admin",
  "message": "Test",
  "message_type": "text",
  "file_url": null,
  "file_name": null,
  "file_size": null,
  "mime_type": null,
  "timestamp": "2025-10-03T07:04:01"
}
```

## Integration Points

### 1. ChatMessage Model
The `ChatMessage` model now includes:
- `serverMessageId: Int?` - Stores the server's message ID (e.g., 1, 2, 3, etc.)
- `reactions: [ReactionSummary]` - Stores reaction data for the message
- `userReaction: ReactionType?` - Stores the current user's reaction

### 2. Message Loading
When messages are loaded from the server:
- `ServerMessage.toChatMessage()` maps `id` field to `serverMessageId`
- Messages are initialized with empty reactions arrays
- Server message IDs are preserved for reaction operations

### 3. WebSocket Messages
When messages arrive via WebSocket:
- `webSocketMessage.message_id` is stored in `serverMessageId`
- Real-time messages maintain their server IDs for reactions

### 4. Reaction Operations
When adding/removing reactions:
- `addReaction(to messageId: String, reactionType: ReactionType)` finds the message by local UUID
- Extracts the `serverMessageId` for API calls
- Uses server message ID for WebSocket reaction events

### 5. Reaction Events
When reaction events arrive via WebSocket:
- `handleReactionEvent(_ reactionEvent: ReactionEvent)` finds messages by `serverMessageId`
- Updates the message with new reaction data
- Determines current user's reaction status

## Example Flow

### Adding a Reaction
1. User taps reaction button on message with local UUID "abc-123"
2. System finds message: `ChatMessage(id: "abc-123", serverMessageId: 14, ...)`
3. API call: `POST /api/reactions/add` with `message_id: 14`
4. WebSocket event: `{"type": "reaction_added", "message_id": 14, ...}`
5. UI updates with new reaction data

### Receiving Reaction Events
1. WebSocket receives: `{"type": "reaction_added", "message_id": 14, "reaction_summary": [...]}`
2. System finds message with `serverMessageId == 14`
3. Updates message with new reaction data
4. UI reflects the changes

## Key Benefits

1. **Server Message IDs Preserved**: Your message IDs (1, 2, 3, etc.) are maintained throughout the app
2. **Real-time Updates**: WebSocket reaction events update the correct messages
3. **API Integration**: Reaction API calls use the correct server message IDs
4. **User Experience**: Reactions appear instantly and stay synchronized

## Testing with Your Data

To test with your provided message data:

1. **Message ID 1**: "Test" message from admin
2. **Message ID 14**: Image message with file URL
3. **Message ID 87**: Latest image message

Each of these messages can now receive reactions using their server message IDs, and the reactions will be properly synchronized across all connected clients.

## WebSocket URL
Your WebSocket connection: `ws://172.20.10.2:8000/ws/chat/1?token=...`

The system will now properly handle reaction events for all messages in room 1, using the message IDs from your server response.
