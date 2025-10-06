//
//  ChatRoomView.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI

struct ChatRoomView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var roomService = RoomService()
    @State private var availableRooms: [ChatRoom] = []
    @State private var isLoadingRooms = false
    @State private var roomError: String?
    @State private var showingCreateRoom = false
    @State private var newRoomName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Welcome Section
                VStack(alignment: .leading, spacing: 8) {
                    if let user = authViewModel.currentUser {
                        Text("Welcome, \(user.username)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Rooms List
                if isLoadingRooms {
                    VStack {
                        ProgressView()
                        Text("Loading rooms...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let roomError = roomError {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to load rooms")
                            .font(.headline)
                        Text(roomError)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            loadRooms()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    List(availableRooms) { room in
                        NavigationLink(destination: ChatView(room: room)
                            .environmentObject(chatViewModel)
                            .onAppear {
                                chatViewModel.joinRoom(room)
                            }
                        ) {
                            RoomRowView(room: room)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                // Connection Status
                if chatViewModel.isConnected {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.bottom, 8)
                } else if let connectionError = chatViewModel.connectionError {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Connection Error: \(connectionError)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Chat Rooms")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // Create Room Button
                        Button(action: {
                            showingCreateRoom = true
                        }) {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        // Logout Button
                        Button(action: {
                            authViewModel.logout()
                            chatViewModel.disconnectFromWebSocket()
                        }) {
                            Image(systemName: "power")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateRoom) {
                CreateRoomView(
                    roomName: $newRoomName,
                    isPresented: $showingCreateRoom,
                    onCreateRoom: createRoom
                )
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            loadRooms()
        }
        .onDisappear {
            chatViewModel.disconnectFromWebSocket()
        }
    }
    
    // MARK: - Load Rooms
    private func loadRooms() {
        guard let token = KeychainService.shared.getToken() else {
            roomError = "No authentication token found"
            return
        }
        
        isLoadingRooms = true
        roomError = nil
        
        Task {
            do {
                let rooms = try await roomService.getRooms(token: token)
                
                await MainActor.run {
                    self.availableRooms = rooms
                    self.isLoadingRooms = false
                }
                
            } catch {
                await MainActor.run {
                    self.isLoadingRooms = false
                    self.roomError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Create Room
    private func createRoom(name: String) {
        guard let token = KeychainService.shared.getToken() else {
            roomError = "No authentication token found"
            return
        }
        
        Task {
            do {
                let newRoom = try await roomService.createRoom(name: name, token: token)
                
                await MainActor.run {
                    self.availableRooms.append(newRoom)
                    self.newRoomName = ""
                }
                
            } catch {
                await MainActor.run {
                    self.roomError = error.localizedDescription
                }
            }
        }
    }
}

struct RoomRowView: View {
    let room: ChatRoom
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Tap to join")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct CreateRoomView: View {
    @Binding var roomName: String
    @Binding var isPresented: Bool
    let onCreateRoom: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Room Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter room name", text: $roomName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.words)
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Create Room")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        roomName = ""
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onCreateRoom(roomName)
                        isPresented = false
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    let authViewModel = AuthViewModel()
    authViewModel.currentUser = User(id: "1", username: "testuser")
    authViewModel.isAuthenticated = true
    
    return ChatRoomView()
        .environmentObject(authViewModel)
}
