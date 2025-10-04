//
//  ChatMessage.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

struct ChatMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let sender: String
    let message: String
    let timestamp: Date
    
    init(id: String = UUID().uuidString, roomId: String, sender: String, message: String, timestamp: Date = Date()) {
        self.id = id
        self.roomId = roomId
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - WebSocket Message Models
struct WebSocketMessage: Codable {
    let type: String
    let roomId: String
    let sender: String
    let message: String
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case roomId
        case sender
        case message
        case timestamp
    }
}

struct SendMessageRequest: Codable {
    let roomId: String
    let message: String
}
