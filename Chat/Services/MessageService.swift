//
//  MessageService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

class MessageService: ObservableObject {
    private let baseURL = "http://localhost:8080"
    private let session = URLSession.shared
    
    // MARK: - Fetch Messages
    func fetchMessages(for roomId: String, token: String) async throws -> [ChatMessage] {
        let url = URL(string: "\(baseURL)/api/messages/\(roomId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MessageError.fetchFailed
        }
        
        // Parse messages with custom date decoder
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        return try decoder.decode([ChatMessage].self, from: data)
    }
}

// MARK: - Message Errors
enum MessageError: Error, LocalizedError {
    case fetchFailed
    case sendFailed
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch messages."
        case .sendFailed:
            return "Failed to send message."
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}
