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
struct ReactionSummary: Codable, Equatable {
    let reactionType: ReactionType
    var count: Int
    var users: [String]
    
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

// MARK: - API Response Models
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

// MARK: - API Request Models
struct AddReactionRequest: Codable {
    let messageId: Int
    let reactionType: String
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case reactionType = "reaction_type"
    }
}

// MARK: - Message with Reactions Model
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

// MARK: - Error Types
enum ReactionError: Error, LocalizedError {
    case networkError
    case invalidResponse
    case decodingError
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error occurred while handling reaction"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response"
        case .unauthorized:
            return "Unauthorized to perform this action"
        }
    }
}

// MARK: - Reaction Action Types
enum ReactionAction: String {
    case add = "add"
    case remove = "remove"
}
