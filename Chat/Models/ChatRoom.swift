//
//  ChatRoom.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

struct ChatRoom: Codable, Identifiable {
    let id: String
    let name: String
    let created_at: String?
    
    init(id: String = UUID().uuidString, name: String, created_at: String? = nil) {
        self.id = id
        self.name = name
        self.created_at = created_at
    }
    
    // Custom decoder to handle numeric ID from server
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle both string and numeric IDs
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
    
    private enum CodingKeys: String, CodingKey {
        case id, name, created_at
    }
}

// MARK: - Room Creation Request
struct ChatRoomCreate: Codable {
    let name: String
    
    init(name: String) {
        self.name = name
    }
}

// MARK: - Default Rooms
extension ChatRoom {
    static let defaultRooms: [ChatRoom] = [
        ChatRoom(id: "general", name: "General"),
        ChatRoom(id: "random", name: "Random"),
        ChatRoom(id: "tech", name: "Tech Talk"),
        ChatRoom(id: "gaming", name: "Gaming")
    ]
}
