//
//  ChatApp.swift
//  Chat
//
//  Created by Eroute-Admin on 30/09/25.
//

import SwiftUI

@main
struct ChatApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(chatViewModel)
                .background(Color(.systemBackground))
        }
    }
}
