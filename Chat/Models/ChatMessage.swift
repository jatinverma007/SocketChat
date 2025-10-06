//
//  ChatMessage.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

// MARK: - WebSocket Message Models
struct WebSocketMessage: Codable {
    let type: String
    let room_id: Int?
    let message_id: Int? // Server's message ID for reactions
    let sender: String?
    let content: String?  // Make optional since image messages might not have content
    let message: String?  // Server sends "message" instead of "content"
    let timestamp: String?
    let attachment: WebSocketAttachment?
    let message_type: String?
    
    // Direct file fields (server sends these directly in the message)
    let file_url: String?
    let file_name: String?
    let file_size: Int?
    let mime_type: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case room_id
        case message_id
        case sender
        case content
        case message
        case timestamp
        case attachment
        case message_type
        case file_url
        case file_name
        case file_size
        case mime_type
    }
    
    // Computed property to get the actual message content
    var messageContent: String {
        if let content = content, !content.isEmpty {
            return content
        } else {
            return message ?? ""
        }
    }
}

struct WebSocketAttachment: Codable {
    let type: String?
    let filename: String?
    let url: String?
    let size: Int?
    let mime_type: String?
}

struct WebSocketConnectionMessage: Codable {
    let type: String
    let room_id: Int?
    let room_name: String?
    let message: String
    let timestamp: String?
}

struct WebSocketErrorMessage: Codable {
    let type: String
    let message: String
}

struct ChatMessage: Codable, Identifiable {
    let id: String
    var serverMessageId: Int? // Server's message ID for reactions (mutable to allow updates)
    let roomId: String
    let sender: String
    let message: String
    let timestamp: Date
    let attachment: Attachment?
    let messageType: MessageType
    var reactions: [ReactionSummary] // Store reaction data
    var userReaction: ReactionType? // Current user's reaction to this message
    
    init(id: String = UUID().uuidString, serverMessageId: Int? = nil, roomId: String, sender: String, message: String, timestamp: Date = Date(), attachment: Attachment? = nil, messageType: MessageType = .text, reactions: [ReactionSummary] = [], userReaction: ReactionType? = nil) {
        self.id = id
        self.serverMessageId = serverMessageId
        self.roomId = roomId
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
        self.attachment = attachment
        self.messageType = messageType
        self.reactions = reactions
        self.userReaction = userReaction
    }
}

// MARK: - Message Type Enum
enum MessageType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case document = "document"
    case textWithImage = "text_with_image"
    case textWithVideo = "text_with_video"
    case textWithAudio = "text_with_audio"
    case textWithDocument = "text_with_document"
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .textWithImage: return "Text + Image"
        case .textWithVideo: return "Text + Video"
        case .textWithAudio: return "Text + Audio"
        case .textWithDocument: return "Text + Document"
        }
    }
    
    static func fromAttachment(_ attachment: Attachment?, hasText: Bool) -> MessageType {
        guard let attachment = attachment else {
            return .text
        }
        
        if hasText {
            switch attachment.type {
            case .image: return .textWithImage
            case .video: return .textWithVideo
            case .audio: return .textWithAudio
            case .document, .file: return .textWithDocument
            }
        } else {
            switch attachment.type {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            case .document, .file: return .document
            }
        }
    }
}

// MARK: - Attachment Model
struct Attachment: Codable {
    let type: AttachmentType
    let filename: String
    let url: String?
    let size: Int?
    let mimeType: String?
    
    enum AttachmentType: String, Codable {
        case image = "image"
        case video = "video"
        case audio = "audio"
        case document = "document"
        case file = "file"
    }
}

struct SendMessageRequest: Codable {
    let roomId: String
    let message: String
}

// MARK: - Server Message Model (for API responses)
struct ServerMessage: Codable {
    let message_id: Int // Server's message ID (matches actual server response)
    let room_id: Int
    let sender: String
    let message: String
    let timestamp: String
    let message_type: String?
    let file_url: String?
    let file_name: String?
    let file_size: Int?
    let mime_type: String?
    
    // Reaction data (optional for backward compatibility)
    let reactions: [ReactionSummary]?
    let user_reaction: String?
    
    // Convert to ChatMessage
    func toChatMessage() -> ChatMessage {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let date = dateFormatter.date(from: timestamp) ?? Date()
        
        // Create attachment from direct fields if file data is available
        let attachment: Attachment?
        
        print("📎 ServerMessage.toChatMessage(): Processing message")
        print("📎   - message_type: \(message_type ?? "nil")")
        print("📎   - file_url: \(file_url ?? "nil")")
        print("📎   - file_name: \(file_name ?? "nil")")
        print("📎   - file_size: \(file_size ?? 0)")
        print("📎   - mime_type: \(mime_type ?? "nil")")
        
        if let fileUrl = file_url, let fileName = file_name, !fileUrl.isEmpty, !fileName.isEmpty {
            print("📎 ServerMessage.toChatMessage(): Creating attachment - file_url=\(fileUrl), file_name=\(fileName)")
            
            let attachmentType: Attachment.AttachmentType
            if let mimeType = mime_type {
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
                // Fallback to message_type if mime_type is not available
                switch message_type {
                case "image": attachmentType = .image
                case "video": attachmentType = .video
                case "audio": attachmentType = .audio
                case "document": attachmentType = .document
                default: attachmentType = .file
                }
            }
            
            attachment = Attachment(
                type: attachmentType,
                filename: fileName,
                url: fileUrl,
                size: file_size,
                mimeType: mime_type
            )
        } else {
            print("📎 ServerMessage.toChatMessage(): No file data available")
            
            // Workaround: If message_type indicates media but server didn't provide file data,
            // create a placeholder attachment to maintain UI consistency
            if let msgType = message_type, 
               ["image", "video", "audio", "document"].contains(msgType) {
                print("📎 ServerMessage.toChatMessage(): Creating placeholder attachment for \(msgType)")
                
                let attachmentType: Attachment.AttachmentType
                switch msgType {
                case "image": attachmentType = .image
                case "video": attachmentType = .video
                case "audio": attachmentType = .audio
                case "document": attachmentType = .document
                default: attachmentType = .file
                }
                
                attachment = Attachment(
                    type: attachmentType,
                    filename: "placeholder_\(msgType)",
                    url: nil, // No URL available
                    size: nil,
                    mimeType: nil
                )
            } else {
                attachment = nil
            }
        }
        
        // Determine message type
        let hasText = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let messageType: MessageType
        
        if let serverMessageType = message_type, let type = MessageType(rawValue: serverMessageType) {
            messageType = type
        } else {
            messageType = MessageType.fromAttachment(attachment, hasText: hasText)
        }
        
        // Parse user reaction from server response
        let userReaction: ReactionType?
        if let userReactionString = user_reaction {
            userReaction = ReactionType(rawValue: userReactionString)
            print("🔖 ServerMessage.toChatMessage(): User reaction: \(userReactionString)")
        } else {
            userReaction = nil
        }
        
        // Debug reactions
        if let reactions = reactions {
            print("🔖 ServerMessage.toChatMessage(): Found \(reactions.count) reaction types")
            for reaction in reactions {
                print("🔖   - \(reaction.reactionType.rawValue): \(reaction.count) users")
            }
        } else {
            print("🔖 ServerMessage.toChatMessage(): No reactions in server response")
        }
        
        return ChatMessage(
            id: "server_\(message_id)", // Use server message ID as local ID for consistency
            serverMessageId: message_id, // Use server's message ID for reactions
            roomId: String(room_id),
            sender: sender,
            message: message,
            timestamp: date,
            attachment: attachment,
            messageType: messageType,
            reactions: reactions ?? [], // Use reactions from server or empty array
            userReaction: userReaction // Use user reaction from server
        )
    }
}

// MARK: - Server Attachment Model
struct ServerAttachment: Codable {
    let type: String
    let filename: String
    let url: String?
    let size: Int?
    let mime_type: String?
    
    func toAttachment() -> Attachment {
        let attachmentType: Attachment.AttachmentType
        
        switch type.lowercased() {
        case "image": attachmentType = .image
        case "video": attachmentType = .video
        case "audio": attachmentType = .audio
        case "document": attachmentType = .document
        default: attachmentType = .file
        }
        
        print("📎 ServerAttachment.toAttachment(): type=\(type), filename=\(filename), url=\(url ?? "nil")")
        
        return Attachment(
            type: attachmentType,
            filename: filename,
            url: url,
            size: size,
            mimeType: mime_type
        )
    }
}
