//
//  AuthService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

class AuthService: ObservableObject {
    private let baseURL = "http://localhost:8080"
    private let session = URLSession.shared
    
    // MARK: - Signup
    func signup(username: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let signupRequest = SignupRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(signupRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.signupFailed
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    // MARK: - Login
    func login(username: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let loginRequest = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(loginRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.loginFailed
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
}

// MARK: - Auth Errors
enum AuthError: Error, LocalizedError {
    case signupFailed
    case loginFailed
    case invalidCredentials
    case networkError
    
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
        }
    }
}
