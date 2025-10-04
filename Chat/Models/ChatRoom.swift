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
    
    init(id: String = UUID().uuidString, name: String) {
        self.id = id
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
