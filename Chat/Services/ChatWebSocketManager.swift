//
//  ChatWebSocketManager.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import Foundation
import Combine

class ChatWebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let baseURL = "ws://localhost:8080"
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var messageSubject = PassthroughSubject<ChatMessage, Never>()
    var messagePublisher: AnyPublisher<ChatMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    private var reconnectTimer: Timer?
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    // MARK: - Connection Management
    func connect(token: String) {
        guard let url = URL(string: "\(baseURL)/ws/chat?token=\(token)") else {
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: url)
        
        webSocketTask?.resume()
        isConnected = true
        connectionError = nil
        reconnectAttempts = 0
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - Message Handling
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.handleConnectionError(error)
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            
            let webSocketMessage = try decoder.decode(WebSocketMessage.self, from: data)
            
            let chatMessage = ChatMessage(
                id: UUID().uuidString,
                roomId: webSocketMessage.roomId,
                sender: webSocketMessage.sender,
                message: webSocketMessage.message,
                timestamp: Date() // Use current time if parsing fails
            )
            
            DispatchQueue.main.async {
                self.messageSubject.send(chatMessage)
            }
        } catch {
            print("Failed to parse WebSocket message: \(error)")
        }
    }
    
    // MARK: - Send Message
    func sendMessage(roomId: String, message: String) {
        let messageData = [
            "type": "MESSAGE",
            "roomId": roomId,
            "message": message
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            webSocketTask?.send(message) { [weak self] error in
                if let error = error {
                    print("Failed to send message: \(error)")
                    DispatchQueue.main.async {
                        self?.connectionError = "Failed to send message"
                    }
                }
            }
        } catch {
            print("Failed to encode message: \(error)")
            DispatchQueue.main.async {
                self?.connectionError = "Failed to encode message"
            }
        }
    }
    
    // MARK: - Subscribe to Room
    func subscribeToRoom(_ roomId: String) {
        let subscriptionData = [
            "type": "SUBSCRIBE",
            "roomId": roomId
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: subscriptionData)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            webSocketTask?.send(message) { [weak self] error in
                if let error = error {
                    print("Failed to subscribe to room: \(error)")
                    DispatchQueue.main.async {
                        self?.connectionError = "Failed to subscribe to room"
                    }
                }
            }
        } catch {
            print("Failed to encode subscription: \(error)")
            DispatchQueue.main.async {
                self?.connectionError = "Failed to encode subscription"
            }
        }
    }
    
    // MARK: - Error Handling & Reconnection
    private func handleConnectionError(_ error: Error) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionError = error.localizedDescription
        }
        
        if reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect()
        }
    }
    
    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30 seconds
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            // Note: In a real app, you'd need to store the token to reconnect
            print("Attempting to reconnect... (attempt \(self?.reconnectAttempts ?? 0))")
        }
    }
}
