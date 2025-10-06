//
//  ServerConfig.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation

struct ServerConfig {
    // MARK: - Server Configuration
    // Use localhost for iOS Simulator
    // For physical device, change to your computer's IP address
    // You can find your IP address by running: ifconfig | grep "inet " | grep -v 127.0.0.1
    static let serverIP = "172.20.10.2"
    static let serverPort = "8000"
    
    // MARK: - Base URLs
    static let httpBaseURL = "http://\(serverIP):\(serverPort)"
    static let wsBaseURL = "ws://\(serverIP):\(serverPort)"
    
    // MARK: - API Endpoints
    static let authSignup = "\(httpBaseURL)/api/auth/signup"
    static let authLogin = "\(httpBaseURL)/api/auth/login"
    static let authRefresh = "\(httpBaseURL)/api/auth/refresh"
    static let authMe = "\(httpBaseURL)/api/auth/me"
    static let rooms = "\(httpBaseURL)/api/rooms"
    static let messages = "\(httpBaseURL)/api/messages"
    static let wsChat = "\(wsBaseURL)/ws/chat"
    
    // MARK: - File Upload Endpoints
    static let uploadFile = "\(httpBaseURL)/api/upload-file"
    static let fileServing = "\(httpBaseURL)/api/files"
    
    // MARK: - Reaction Endpoints
    static let reactionsAdd = "\(httpBaseURL)/api/reactions/add"
    static let reactionsRemove = "\(httpBaseURL)/api/reactions/remove"
    static let reactionsMessage = "\(httpBaseURL)/api/reactions/message"
    static let reactionsRoom = "\(httpBaseURL)/api/reactions/room"
    static let reactionsAvailable = "\(httpBaseURL)/api/reactions/available"
    
    // MARK: - File Configuration
    static let maxFileSize = 10 * 1024 * 1024 // 10MB in bytes
    
    // MARK: - Supported File Types
    static let supportedImageTypes = ["jpeg", "jpg", "png", "gif", "webp"]
    static let supportedVideoTypes = ["mp4", "mov", "avi"]
    static let supportedAudioTypes = ["mp3", "wav", "m4a"]
    static let supportedDocumentTypes = ["pdf", "doc", "docx", "txt"]
    
    static func getFileURL(for filename: String) -> String {
        return "\(fileServing)/\(filename)"
    }
}
