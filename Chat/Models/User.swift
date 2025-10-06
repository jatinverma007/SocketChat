//
//  User.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let token: String?
    
    init(id: String, username: String, token: String? = nil) {
        self.id = id
        self.username = username
        self.token = token
    }
}

// MARK: - User Creation Request
struct UserCreate: Codable {
    let username: String
    let password: String
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

// MARK: - Auth Response Models
struct AuthResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let token_type: String
    let user: User?
    
    // Computed property for backward compatibility
    var token: String {
        return access_token
    }
}

// MARK: - Refresh Token Request
struct RefreshTokenRequest: Codable {
    let refresh_token: String
}

// MARK: - Refresh Token Response
struct RefreshTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let token_type: String
}

struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct SignupRequest: Codable {
    let username: String
    let password: String
}
