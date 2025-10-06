//
//  AuthService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

class AuthService: ObservableObject {
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
    
    // MARK: - Signup
    func signup(username: String, password: String) async throws -> AuthResponse {
        let url = URL(string: ServerConfig.authSignup)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let signupRequest = UserCreate(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(signupRequest)
        
        let (data, response) = try await session.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("Signup Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid HTTP response")
            throw AuthError.signupFailed
        }
        
        print("Signup Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("Signup failed with status code: \(httpResponse.statusCode)")
            throw AuthError.signupFailed
        }
        
        do {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            print("JSON Decoding Error: \(error)")
            print("Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
            throw error
        }
    }
    
    // MARK: - Login
    func login(username: String, password: String) async throws -> AuthResponse {
        let url = URL(string: ServerConfig.authLogin)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let loginRequest = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(loginRequest)
        
        print("🔐 Login Request to: \(url)")
        print("🔐 Login Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to encode")")
        print("🔐 Server IP: \(ServerConfig.serverIP)")
        print("🔐 Server Port: \(ServerConfig.serverPort)")
        print("🔐 Full URL: \(url.absoluteString)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Debug: Print the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔐 Login Response: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw AuthError.loginFailed
            }
            
            print("🔐 Login Status Code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ Login failed with status code: \(httpResponse.statusCode)")
                throw AuthError.loginFailed
            }
            
            do {
                return try JSONDecoder().decode(AuthResponse.self, from: data)
            } catch {
                print("❌ JSON Decoding Error: \(error)")
                print("❌ Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
                throw error
            }
            
        } catch let error as NSError {
            // Handle specific timeout errors
            if error.domain == "NSURLErrorDomain" && error.code == -1001 {
                print("❌ Login request timed out - server may be unreachable")
                print("❌ Server URL: \(url)")
                print("❌ Check if server is running at \(ServerConfig.serverIP):\(ServerConfig.serverPort)")
                throw AuthError.networkError
            } else if error.domain == "NSURLErrorDomain" && error.code == -1004 {
                print("❌ Could not connect to server - server may be down")
                print("❌ Server URL: \(url)")
                throw AuthError.networkError
            } else {
                print("❌ Login request failed: \(error)")
                throw AuthError.loginFailed
            }
        }
    }
    
    // MARK: - Get Current User
    func getCurrentUser(token: String) async throws -> User {
        let url = URL(string: ServerConfig.authMe)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("👤 Get Current User Request to: \(url)")
        print("👤 Authorization Header: Bearer \(token.prefix(20))...")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("👤 Get Current User Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw AuthError.networkError
        }
        
        print("👤 Get Current User Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ Get Current User failed with status code: \(httpResponse.statusCode)")
            throw AuthError.networkError
        }
        
        do {
            return try JSONDecoder().decode(User.self, from: data)
        } catch {
            print("❌ JSON Decoding Error: \(error)")
            print("❌ Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
            throw error
        }
    }
    
    // MARK: - Refresh Token
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        let url = URL(string: ServerConfig.authRefresh)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let refreshRequest = RefreshTokenRequest(refresh_token: refreshToken)
        request.httpBody = try JSONEncoder().encode(refreshRequest)
        
        print("🔄 Refresh Token Request to: \(url)")
        print("🔄 Refresh Token Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to encode")")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔄 Refresh Token Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw AuthError.networkError
        }
        
        print("🔄 Refresh Token Status Code: \(httpResponse.statusCode)")
        
        // Handle different status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - decode the response
            do {
                return try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
            } catch {
                print("❌ JSON Decoding Error: \(error)")
                print("❌ Raw data: \(String(data: data, encoding: .utf8) ?? "Unable to convert to string")")
                throw AuthError.refreshTokenFailed
            }
            
        case 400:
            print("❌ Bad Request - validation errors")
            throw AuthError.refreshTokenFailed
            
        case 401:
            print("❌ Unauthorized - invalid/expired refresh token")
            throw AuthError.refreshTokenExpired
            
        case 404:
            print("❌ Not Found - refresh endpoint not found")
            throw AuthError.refreshTokenFailed
            
        case 422:
            print("❌ Validation Error")
            throw AuthError.refreshTokenFailed
            
        default:
            print("❌ Refresh token failed with status code: \(httpResponse.statusCode)")
            throw AuthError.refreshTokenFailed
        }
    }
}

// MARK: - Auth Errors
enum AuthError: Error, LocalizedError {
    case signupFailed
    case loginFailed
    case invalidCredentials
    case networkError
    case refreshTokenFailed
    case refreshTokenExpired
    
    var errorDescription: String? {
        switch self {
        case .signupFailed:
            return "Signup failed. Please try again."
        case .loginFailed:
            return "Login failed. Please check your credentials."
        case .invalidCredentials:
            return "Invalid username or password."
        case .networkError:
            return "Network error. Please check your connection."
        case .refreshTokenFailed:
            return "Token refresh failed. Please login again."
        case .refreshTokenExpired:
            return "Refresh token expired. Please login again."
        }
    }
}
