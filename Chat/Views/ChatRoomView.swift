//
//  ChatRoomView.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI
import Combine

struct ChatRoomView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var roomService = RoomService()
    @State private var availableRooms: [ChatRoom] = []
    @State private var isLoadingRooms = false
    @State private var roomError: String?
    @State private var showingCreateRoom = false
    @State private var newRoomName = ""
    @State private var cancellables = Set<AnyCancellable>()
    @State private var refreshTimer: Timer?
    @State private var lastRefreshTime = Date()
    
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
                                // Mark messages as read when entering the room
                                Task {
                                    await markRoomAsRead(roomId: room.id)
                                }
                            }
                            .onDisappear {
                                // Refresh room list when returning from chat
                                Task {
                                    await refreshRooms()
                                }
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
                        // Setup Encryption Button
                        Button(action: {
                            Task {
                                await chatViewModel.initializeEncryption()
                            }
                        }) {
                            Image(systemName: "lock.shield")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        
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
            setupMessageListener()
            setupForegroundListener()
            startPeriodicRefresh()
            // Initialize encryption if not already done
            Task {
                await chatViewModel.initializeEncryption()
            }
        }
        .onDisappear {
            stopPeriodicRefresh()
        }
        .refreshable {
            await refreshRooms()
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
                    // Sort rooms by last message timestamp (most recent first)
                    self.availableRooms = rooms.sorted { room1, room2 in
                        guard let timestamp1 = room1.lastMessage?.parsedTimestamp else {
                            return false // Rooms without messages go to the end
                        }
                        guard let timestamp2 = room2.lastMessage?.parsedTimestamp else {
                            return true // Rooms with messages come before those without
                        }
                        return timestamp1 > timestamp2 // Most recent first
                    }
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
    
    // MARK: - Listeners Setup
    private func setupMessageListener() {
        // Subscribe to incoming messages from any room
        // This will trigger immediate room list refresh when any message arrives
        NotificationCenter.default
            .publisher(for: NSNotification.Name("NewMessageReceived"))
            .sink { notification in
                print("📬 Room Listing: ✨ New message notification received!")
                if let userInfo = notification.userInfo,
                   let message = userInfo["message"] as? ChatMessage {
                    print("📬 Room Listing: Message from room: \(message.roomId), sender: \(message.sender)")
                }
                // Refresh immediately without throttle for instant updates
                Task {
                    await self.refreshRooms()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupForegroundListener() {
        // Refresh when app comes to foreground
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                print("📬 Room Listing: App entering foreground - refreshing room list")
                Task {
                    await self.refreshRooms()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Periodic Refresh
    private func startPeriodicRefresh() {
        // Refresh every 3 seconds for near-instant updates
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await self.refreshRooms()
            }
        }
    }
    
    private func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Smart Refresh
    private func refreshRoomsIfNeeded() async {
        // Only refresh if last refresh was more than 0.5 seconds ago
        // This prevents excessive API calls while still being responsive
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) > 0.5 else {
            print("📬 Room Listing: Skipping refresh - too recent")
            return
        }
        await refreshRooms()
    }
    
    private func refreshRooms() async {
        guard let token = KeychainService.shared.getToken() else {
            return
        }
        
        lastRefreshTime = Date()
        
        do {
            let rooms = try await roomService.getRooms(token: token)
            await MainActor.run {
                // Sort rooms by last message timestamp (most recent first)
                self.availableRooms = rooms.sorted { room1, room2 in
                    guard let timestamp1 = room1.lastMessage?.parsedTimestamp else {
                        return false
                    }
                    guard let timestamp2 = room2.lastMessage?.parsedTimestamp else {
                        return true
                    }
                    return timestamp1 > timestamp2
                }
                print("✅ Room list refreshed successfully - \(rooms.count) rooms")
            }
        } catch {
            // Silently fail on refresh to avoid disrupting user experience
            print("❌ Failed to refresh rooms: \(error)")
        }
    }
    
    // MARK: - Mark Room as Read
    private func markRoomAsRead(roomId: String) async {
        guard let token = KeychainService.shared.getToken() else {
            return
        }
        
        do {
            try await roomService.markMessagesAsRead(roomId: roomId, token: token)
            
            // Update the unread count locally to 0 for immediate UI feedback
            await MainActor.run {
                if let index = availableRooms.firstIndex(where: { $0.id == roomId }) {
                    var updatedRoom = availableRooms[index]
                    updatedRoom.unreadCount = 0
                    availableRooms[index] = updatedRoom
                    print("✅ Updated unread count to 0 for room: \(roomId)")
                }
            }
        } catch {
            print("❌ Failed to mark messages as read: \(error)")
            // Silently fail - user can still use the app
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
                    // Re-sort rooms after adding a new one
                    self.availableRooms = self.availableRooms.sorted { room1, room2 in
                        guard let timestamp1 = room1.lastMessage?.parsedTimestamp else {
                            return false
                        }
                        guard let timestamp2 = room2.lastMessage?.parsedTimestamp else {
                            return true
                        }
                        return timestamp1 > timestamp2
                    }
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
                
                if let lastMessage = room.lastMessage, !lastMessage.message.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(lastMessage.sender):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        Text(lastMessage.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No messages yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let lastMessage = room.lastMessage, let timestamp = lastMessage.parsedTimestamp {
                    Text(formatTimestamp(timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Unread count badge (WhatsApp style)
                if room.unreadCount > 0 {
                    Text("\(room.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
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
