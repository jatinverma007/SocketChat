//
//  ContentView.swift
//  Chat
//
//  Created by Eroute-Admin on 30/09/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ChatRoomView()
            } else {
                LoginView()
            }
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
