//
//  KeychainService.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    private init() {}
    
    private let service = "ChatApp"
    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"
    private let usernameKey = "username"
    
    // MARK: - Save Token
    func saveToken(_ token: String) {
        saveToKeychain(key: tokenKey, value: token)
    }
    
    // MARK: - Get Token
    func getToken() -> String? {
        return getFromKeychain(key: tokenKey)
    }
    
    // MARK: - Save Refresh Token
    func saveRefreshToken(_ refreshToken: String) {
        saveToKeychain(key: refreshTokenKey, value: refreshToken)
    }
    
    // MARK: - Get Refresh Token
    func getRefreshToken() -> String? {
        return getFromKeychain(key: refreshTokenKey)
    }
    
    // MARK: - Save Username
    func saveUsername(_ username: String) {
        saveToKeychain(key: usernameKey, value: username)
    }
    
    // MARK: - Get Username
    func getUsername() -> String? {
        return getFromKeychain(key: usernameKey)
    }
    
    // MARK: - Clear All
    func clearAll() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: usernameKey)
    }
    
    // MARK: - Private Keychain Methods
    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save to keychain: \(status)")
        }
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
