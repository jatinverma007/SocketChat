import Foundation
import Combine

class ReactionService: ObservableObject {
    static let shared = ReactionService()
    
    private let session: URLSession
    private let keychainService = KeychainService.shared
    
    private init() {
        // Create URLSession with extended timeout configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // 60 seconds for individual requests
        config.timeoutIntervalForResource = 120 // 2 minutes for entire resource
        config.waitsForConnectivity = true      // Wait for network connectivity
        config.allowsCellularAccess = true      // Allow cellular connections
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - API Methods
    
    func addReaction(messageId: Int, reactionType: ReactionType) async throws -> ReactionResponse {
        guard let token = keychainService.getToken() else {
            throw ReactionError.unauthorized
        }
        
        let url = URL(string: ServerConfig.reactionsAdd)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = AddReactionRequest(messageId: messageId, reactionType: reactionType.rawValue)
        request.httpBody = try JSONEncoder().encode(body)
        
        print("🔖 ReactionService: Adding reaction \(reactionType.rawValue) to message \(messageId)")
        print("🔖 ReactionService: URL: \(url.absoluteString)")
        print("🔖 ReactionService: Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ReactionService: Invalid HTTP response")
                throw ReactionError.networkError
            }
            
            print("🔖 ReactionService: Add reaction status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ ReactionService: Add reaction failed with status code: \(httpResponse.statusCode)")
                
                // Handle 401 Unauthorized - try to refresh token
                if httpResponse.statusCode == 401 {
                    print("🔄 ReactionService: Token expired, attempting to refresh...")
                    if let newToken = await attemptTokenRefresh() {
                        print("🔄 ReactionService: Token refreshed successfully, retrying request...")
                        return try await addReaction(messageId: messageId, reactionType: reactionType)
                    } else {
                        print("❌ ReactionService: Token refresh failed, user needs to login again")
                        throw ReactionError.unauthorized
                    }
                }
                
                throw ReactionError.networkError
            }
            
            let responseData = try JSONDecoder().decode(ReactionResponse.self, from: data)
            print("✅ ReactionService: Reaction added successfully")
            return responseData
            
        } catch let error as NSError {
            if error.domain == "NSURLErrorDomain" && error.code == -1001 {
                print("❌ ReactionService: Request timed out")
                throw ReactionError.networkError
            } else {
                print("❌ ReactionService: Add reaction failed: \(error)")
                throw ReactionError.networkError
            }
        }
    }
    
    func removeReaction(messageId: Int) async throws -> ReactionResponse {
        guard let token = keychainService.getToken() else {
            throw ReactionError.unauthorized
        }
        
        let url = URL(string: "\(ServerConfig.reactionsRemove)/\(messageId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔖 ReactionService: Removing reaction from message \(messageId)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ReactionService: Invalid HTTP response")
                throw ReactionError.networkError
            }
            
            print("🔖 ReactionService: Remove reaction status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ ReactionService: Remove reaction failed with status code: \(httpResponse.statusCode)")
                
                // Handle 401 Unauthorized - try to refresh token
                if httpResponse.statusCode == 401 {
                    print("🔄 ReactionService: Token expired, attempting to refresh...")
                    if let newToken = await attemptTokenRefresh() {
                        print("🔄 ReactionService: Token refreshed successfully, retrying request...")
                        return try await removeReaction(messageId: messageId)
                    } else {
                        print("❌ ReactionService: Token refresh failed, user needs to login again")
                        throw ReactionError.unauthorized
                    }
                }
                
                throw ReactionError.networkError
            }
            
            let responseData = try JSONDecoder().decode(ReactionResponse.self, from: data)
            print("✅ ReactionService: Reaction removed successfully")
            return responseData
            
        } catch let error as NSError {
            if error.domain == "NSURLErrorDomain" && error.code == -1001 {
                print("❌ ReactionService: Request timed out")
                throw ReactionError.networkError
            } else {
                print("❌ ReactionService: Remove reaction failed: \(error)")
                throw ReactionError.networkError
            }
        }
    }
    
    func getMessageWithReactions(messageId: Int) async throws -> MessageWithReactions {
        guard let token = keychainService.getToken() else {
            throw ReactionError.unauthorized
        }
        
        let url = URL(string: "\(ServerConfig.reactionsMessage)/\(messageId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔖 ReactionService: Getting message \(messageId) with reactions")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ReactionService: Invalid HTTP response")
                throw ReactionError.networkError
            }
            
            print("🔖 ReactionService: Get message with reactions status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ ReactionService: Get message with reactions failed with status code: \(httpResponse.statusCode)")
                
                // Handle 401 Unauthorized - try to refresh token
                if httpResponse.statusCode == 401 {
                    print("🔄 ReactionService: Token expired, attempting to refresh...")
                    if let newToken = await attemptTokenRefresh() {
                        print("🔄 ReactionService: Token refreshed successfully, retrying request...")
                        return try await getMessageWithReactions(messageId: messageId)
                    } else {
                        print("❌ ReactionService: Token refresh failed, user needs to login again")
                        throw ReactionError.unauthorized
                    }
                }
                
                throw ReactionError.networkError
            }
            
            let message = try JSONDecoder().decode(MessageWithReactions.self, from: data)
            print("✅ ReactionService: Message with reactions retrieved successfully")
            return message
            
        } catch let error as NSError {
            if error.domain == "NSURLErrorDomain" && error.code == -1001 {
                print("❌ ReactionService: Request timed out")
                throw ReactionError.networkError
            } else {
                print("❌ ReactionService: Get message with reactions failed: \(error)")
                throw ReactionError.networkError
            }
        }
    }
    
    func getAvailableReactions() async throws -> [ReactionType] {
        guard let token = keychainService.getToken() else {
            throw ReactionError.unauthorized
        }
        
        let url = URL(string: ServerConfig.reactionsAvailable)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔖 ReactionService: Getting available reactions")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ReactionService: Invalid HTTP response")
                throw ReactionError.networkError
            }
            
            print("🔖 ReactionService: Get available reactions status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ ReactionService: Get available reactions failed with status code: \(httpResponse.statusCode)")
                
                // Handle 401 Unauthorized - try to refresh token
                if httpResponse.statusCode == 401 {
                    print("🔄 ReactionService: Token expired, attempting to refresh...")
                    if let newToken = await attemptTokenRefresh() {
                        print("🔄 ReactionService: Token refreshed successfully, retrying request...")
                        return try await getAvailableReactions()
                    } else {
                        print("❌ ReactionService: Token refresh failed, user needs to login again")
                        throw ReactionError.unauthorized
                    }
                }
                
                throw ReactionError.networkError
            }
            
            let reactionStrings = try JSONDecoder().decode([String].self, from: data)
            let reactions = reactionStrings.compactMap { ReactionType(rawValue: $0) }
            print("✅ ReactionService: Available reactions retrieved successfully: \(reactions.map { $0.rawValue })")
            return reactions
            
        } catch let error as NSError {
            if error.domain == "NSURLErrorDomain" && error.code == -1001 {
                print("❌ ReactionService: Request timed out")
                throw ReactionError.networkError
            } else {
                print("❌ ReactionService: Get available reactions failed: \(error)")
                throw ReactionError.networkError
            }
        }
    }
    
    // MARK: - Token Refresh Helper
    private func attemptTokenRefresh() async -> String? {
        let authService = AuthService()
        
        guard let refreshToken = keychainService.getRefreshToken() else {
            print("❌ ReactionService: No refresh token available")
            return nil
        }
        
        do {
            let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken)
            
            // Update tokens in keychain
            keychainService.saveToken(refreshResponse.access_token)
            if let newRefreshToken = refreshResponse.refresh_token {
                keychainService.saveRefreshToken(newRefreshToken)
            }
            
            print("✅ ReactionService: Token refreshed successfully")
            return refreshResponse.access_token
            
        } catch {
            print("❌ ReactionService: Token refresh failed: \(error)")
            return nil
        }
    }
}

