//
//  EncryptedMessageService.swift
//  Chat
//
//  Service for sending encrypted messages
//

import Foundation

class EncryptedMessageService {
    static let shared = EncryptedMessageService()
    
    private init() {}
    
    /// Send an encrypted message to a room
    func sendEncryptedMessage(
        roomId: String,
        encryptedContent: String,
        token: String
    ) async throws -> EncryptedMessageResponse {
        let url = URL(string: ServerConfig.encryptionSendMessage)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "room_id": Int(roomId) ?? 0,
            "encrypted_content": encryptedContent,
            "encryption_version": "AES-256-GCM",
            "message_type": "text"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🔐 Sending encrypted message to room: \(roomId)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EncryptedMessageError.sendFailed
        }
        
        print("🔐 Send encrypted message status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Send encrypted failed - Response: \(responseString)")
            }
            throw EncryptedMessageError.sendFailed
        }
        
        let messageResponse = try JSONDecoder().decode(EncryptedMessageResponse.self, from: data)
        
        print("✅ Encrypted message sent successfully - ID: \(messageResponse.message_id)")
        
        return messageResponse
    }
}

// MARK: - Response Models

struct EncryptedMessageResponse: Codable {
    let message_id: Int
    let room_id: Int
    let sender_id: Int
    let sender: String
    let encrypted_content: String
    let encryption_version: String
    let message_type: String
    let timestamp: String
    let is_encrypted: Bool
}

// MARK: - Errors

enum EncryptedMessageError: Error, LocalizedError {
    case sendFailed
    
    var errorDescription: String? {
        switch self {
        case .sendFailed:
            return "Failed to send encrypted message"
        }
    }
}

