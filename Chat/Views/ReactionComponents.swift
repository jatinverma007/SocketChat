import SwiftUI

// MARK: - Reaction Button
struct ReactionButton: View {
    let reactionType: ReactionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(reactionType.rawValue)
                .font(.title2)
                .padding(8)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Reaction Picker
struct ReactionPicker: View {
    @Binding var isPresented: Bool
    let messageId: Int
    let currentReaction: ReactionType?
    let onReactionSelected: (ReactionType) -> Void
    let onReactionRemoved: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(ReactionType.allCases, id: \.self) { reactionType in
                    ReactionButton(
                        reactionType: reactionType,
                        isSelected: currentReaction == reactionType
                    ) {
                        if currentReaction == reactionType {
                            onReactionRemoved()
                        } else {
                            onReactionSelected(reactionType)
                        }
                        isPresented = false
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 10)
            )
        }
        .padding()
    }
}

// MARK: - Reaction Summary View
struct ReactionSummaryView: View {
    let reactions: [ReactionSummary]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(reactions, id: \.reactionType) { reaction in
                HStack(spacing: 4) {
                    Text(reaction.reactionType.rawValue)
                        .font(.caption)
                    Text("\(reaction.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemGray5))
                )
            }
        }
    }
}

// MARK: - Reaction Summary with User Names (for detailed view)
struct DetailedReactionSummaryView: View {
    let reactions: [ReactionSummary]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reactions, id: \.reactionType) { reaction in
                HStack {
                    Text(reaction.reactionType.rawValue)
                        .font(.title3)
                    
                    Text("\(reaction.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !reaction.users.isEmpty {
                        Text(reaction.users.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Reaction Overlay (for message bubbles)
struct ReactionOverlay: View {
    let reactions: [ReactionSummary]
    let userReaction: ReactionType?
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions, id: \.reactionType) { reaction in
                HStack(spacing: 2) {
                    Text(reaction.reactionType.rawValue)
                        .font(.caption)
                    
                    if reaction.count > 1 {
                        Text("\(reaction.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(reaction.users.contains(where: { _ in userReaction == reaction.reactionType }) 
                              ? Color.blue.opacity(0.2) 
                              : Color(.systemGray5))
                )
                .overlay(
                    Capsule()
                        .stroke(reaction.users.contains(where: { _ in userReaction == reaction.reactionType }) 
                                ? Color.blue 
                                : Color.clear, lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Reaction Preview (for showing what reaction will be added)
struct ReactionPreview: View {
    let reactionType: ReactionType
    
    var body: some View {
        Text(reactionType.rawValue)
            .font(.title2)
            .padding(8)
            .background(
                Circle()
                    .fill(Color.blue.opacity(0.2))
            )
            .overlay(
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
            )
            .scaleEffect(1.2)
            .animation(.easeInOut(duration: 0.2), value: reactionType)
    }
}

// MARK: - Reaction Tooltip (for showing reaction details)
struct ReactionTooltip: View {
    let reaction: ReactionSummary
    @State private var isVisible = false
    
    var body: some View {
        Text(reaction.reactionType.rawValue)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(.systemGray5))
            )
            .onTapGesture {
                isVisible.toggle()
            }
            .overlay(
                // Tooltip content
                Group {
                    if isVisible {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reaction.reactionType.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            if !reaction.users.isEmpty {
                                Text(reaction.users.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemBackground))
                                .shadow(radius: 4)
                        )
                        .offset(y: -40)
                        .transition(.opacity.combined(with: .scale))
                    }
                },
                alignment: .top
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible.toggle()
                }
            }
    }
}

