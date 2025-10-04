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

// MARK: - Auth Response Models
struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct SignupRequest: Codable {
    let username: String
    let password: String
}
