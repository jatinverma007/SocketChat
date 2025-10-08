//
//  AuthViewModel.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let authService = AuthService()
    private let keychainService = KeychainService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        checkAuthenticationStatus()
    }
    
    // MARK: - Authentication Status
    private func checkAuthenticationStatus() {
        if let token = keychainService.getToken(),
           let username = keychainService.getUsername() {
            // Create a user object with stored data
            currentUser = User(id: UUID().uuidString, username: username, token: token)
            isAuthenticated = true
            
            // Setup encryption for existing session
            Task {
                await setupEncryption(authToken: token)
            }
        }
    }
    
    // MARK: - Login
    func login(username: String, password: String) {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both username and password"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let authResponse = try await authService.login(username: username, password: password)
                
                // Save tokens to keychain
                keychainService.saveToken(authResponse.token)
                if let refreshToken = authResponse.refresh_token {
                    keychainService.saveRefreshToken(refreshToken)
                }
                
                // Create user object from login request since server doesn't return user
                let user = User(id: UUID().uuidString, username: username, token: authResponse.token)
                keychainService.saveUsername(username)
                
                // Update state
                currentUser = user
                isAuthenticated = true
                isLoading = false
                
                // Upload public key for end-to-end encryption
                Task {
                    await setupEncryption(authToken: authResponse.token)
                }
                
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Signup
    func signup(username: String, password: String) {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both username and password"
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters long"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let authResponse = try await authService.signup(username: username, password: password)
                
                // Save tokens to keychain
                keychainService.saveToken(authResponse.token)
                if let refreshToken = authResponse.refresh_token {
                    keychainService.saveRefreshToken(refreshToken)
                }
                
                // Create user object from signup request since server doesn't return user
                let user = User(id: UUID().uuidString, username: username, token: authResponse.token)
                keychainService.saveUsername(username)
                
                // Update state
                currentUser = user
                isAuthenticated = true
                isLoading = false
                
                // Upload public key for end-to-end encryption
                Task {
                    await setupEncryption(authToken: authResponse.token)
                }
                
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Setup Encryption
    private func setupEncryption(authToken: String) async {
        do {
            print("🔐 Setting up end-to-end encryption...")
            try await EncryptionManager.shared.uploadPublicKeyToServer(authToken: authToken)
            print("✅ Encryption setup complete")
        } catch {
            print("⚠️ Encryption setup failed: \(error.localizedDescription)")
            // Don't block login if encryption setup fails
        }
    }
    
    // MARK: - Refresh Token
    func refreshToken() async throws {
        guard let refreshToken = keychainService.getRefreshToken() else {
            throw AuthError.refreshTokenFailed
        }
        
        do {
            let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken)
            
            // Update tokens in keychain
            keychainService.saveToken(refreshResponse.access_token)
            if let newRefreshToken = refreshResponse.refresh_token {
                keychainService.saveRefreshToken(newRefreshToken)
            }
            
            // Update current user token
            if let user = currentUser {
                let updatedUser = User(id: user.id, username: user.username, token: refreshResponse.access_token)
                currentUser = updatedUser
            }
            
            print("🔄 Token refreshed successfully")
            
        } catch AuthError.refreshTokenExpired {
            // Refresh token expired, need to login again
            logout()
            throw AuthError.refreshTokenExpired
        } catch {
            print("🔄 Token refresh failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Logout
    func logout() {
        keychainService.clearAll()
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
    }
    
    // MARK: - Clear Error
    func clearError() {
        errorMessage = nil
    }
}
