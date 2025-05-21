// First, create an AppStyles.swift file for consistent styling:

import SwiftUI

extension Font {
    static let appTitle = Font.system(size: 18, weight: .bold)
    static let appHeadline = Font.system(size: 16, weight: .semibold)
    static let appBody = Font.system(size: 14, weight: .regular)
    static let appCaption = Font.system(size: 12, weight: .regular)
    static let appTiny = Font.system(size: 10, weight: .regular)
}

extension Color {
    static let appBackground = Color.black
    static let appForeground = Color.white
    static let appAccent = Color.blue
    static let appSecondary = Color.gray
}

// Custom loading indicator with pulsing disabled
struct PulsingLoaderView: View {
    // ‑‑ No @State, no animation ‑‑
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 60, height: 60)

            Circle()
                .fill(Color.blue.opacity(0.5))
                .frame(width: 40, height: 40)

            Circle()
                .fill(Color.blue)
                .frame(width: 20, height: 20)
        }
    }
}

// Update the existing ChatMessage model to fix the errors
// In AppStyles.swift, update ChatMessage struct:
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let message: String
    let timestamp = Date()
    let isSystem: Bool
    
    init(sender: String, message: String, isSystem: Bool = false) {
        self.sender = sender
        self.message = message
        self.isSystem = isSystem
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id && lhs.sender == rhs.sender && lhs.message == rhs.message
    }
}
