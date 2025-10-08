//
//  RoomService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

class RoomService: ObservableObject {
    private let session: URLSession
    
    init() {
        // Create URLSession with extended timeout configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // 60 seconds for individual requests
        config.timeoutIntervalForResource = 120 // 2 minutes for entire resource
        config.waitsForConnectivity = true      // Wait for network connectivity
        config.allowsCellularAccess = true      // Allow cellular connections
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Get All Rooms
    func getRooms(token: String) async throws -> [ChatRoom] {
        let url = URL(string: ServerConfig.rooms)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🏠 Get Rooms Request to: \(url)")
        print("🏠 Authorization Header: Bearer \(token.prefix(20))...")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🏠 Get Rooms Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw RoomError.fetchFailed
        }
        
        print("🏠 Get Rooms Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ Get Rooms failed with status code: \(httpResponse.statusCode)")
            
            // Handle 401 Unauthorized - try to refresh token
            if httpResponse.statusCode == 401 {
                print("🔄 Token expired, attempting to refresh...")
                if let newToken = await attemptTokenRefresh() {
                    print("🔄 Token refreshed successfully, retrying request...")
                    return try await getRooms(token: newToken)
                } else {
                    print("❌ Token refresh failed, user needs to login again")
                    throw RoomError.unauthorized
                }
            }
            
            throw RoomError.fetchFailed
        }
        
        do {
            return try JSONDecoder().decode([ChatRoom].self, from: data)
        } catch {
            print("❌ JSON Decoding Error: \(error)")
            print("❌ Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
            throw error
        }
    }
    
    // MARK: - Create Room
    func createRoom(name: String, token: String) async throws -> ChatRoom {
        let url = URL(string: ServerConfig.rooms)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let roomRequest = ChatRoomCreate(name: name)
        request.httpBody = try JSONEncoder().encode(roomRequest)
        
        print("🏠 Create Room Request to: \(url)")
        print("🏠 Create Room Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to encode")")
        print("🏠 Authorization Header: Bearer \(token.prefix(20))...")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🏠 Create Room Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw RoomError.createFailed
        }
        
        print("🏠 Create Room Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ Create Room failed with status code: \(httpResponse.statusCode)")
            throw RoomError.createFailed
        }
        
        do {
            return try JSONDecoder().decode(ChatRoom.self, from: data)
        } catch {
            print("❌ JSON Decoding Error: \(error)")
            print("❌ Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
            throw error
        }
    }
    
    // MARK: - Get Room by ID
    func getRoom(roomId: String, token: String) async throws -> ChatRoom {
        let url = URL(string: "\(ServerConfig.rooms)/\(roomId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RoomError.fetchFailed
        }
        
        return try JSONDecoder().decode(ChatRoom.self, from: data)
    }
    
    // MARK: - Mark Messages as Read
    func markMessagesAsRead(roomId: String, token: String) async throws {
        let url = URL(string: "\(ServerConfig.rooms)/\(roomId)/mark-read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("📖 Marking messages as read for room: \(roomId)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response for mark as read")
            throw RoomError.networkError
        }
        
        print("📖 Mark as read status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Mark as read failed - Response: \(responseString)")
            }
            throw RoomError.fetchFailed
        }
        
        print("✅ Messages marked as read successfully for room: \(roomId)")
    }
    
    // MARK: - Token Refresh Helper
    private func attemptTokenRefresh() async -> String? {
        let keychainService = KeychainService.shared
        let authService = AuthService()
        
        guard let refreshToken = keychainService.getRefreshToken() else {
            print("❌ No refresh token available")
            return nil
        }
        
        do {
            let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken)
            
            // Update tokens in keychain
            keychainService.saveToken(refreshResponse.access_token)
            if let newRefreshToken = refreshResponse.refresh_token {
                keychainService.saveRefreshToken(newRefreshToken)
            }
            
            print("✅ Token refreshed successfully")
            return refreshResponse.access_token
            
        } catch {
            print("❌ Token refresh failed: \(error)")
            return nil
        }
    }
}

// MARK: - Room Errors
enum RoomError: Error, LocalizedError {
    case fetchFailed
    case createFailed
    case networkError
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch rooms."
        case .createFailed:
            return "Failed to create room."
        case .networkError:
            return "Network error. Please check your connection."
        case .unauthorized:
            return "Session expired. Please login again."
        }
    }
}
