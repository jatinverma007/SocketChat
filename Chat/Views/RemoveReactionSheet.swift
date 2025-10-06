//
//  RemoveReactionSheet.swift
//  ChatApp
//
//  Created by Developer on 2024
//

import SwiftUI

// MARK: - Remove Reaction Sheet
struct RemoveReactionSheet: View {
    let reactionType: ReactionType?
    let onRemove: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Large reaction emoji
                Text(reactionType?.rawValue ?? "")
                    .font(.system(size: 60))
                    .padding(.top, 40)
                
                Text("Remove Reaction")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Tap to remove this reaction")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                // Remove button
                Button(action: onRemove) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Reaction")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}
