import SwiftUI
import CloudKit

struct NavigationBar: View {
    @Binding var selectedTab: TabItem
    let userIdentifier: String
    @State private var profileImage: UIImage?
    @State private var inboxBadgeCount: Int = 0
    
    var body: some View {
        HStack(spacing: 0) {
            // LIVE button
            Button(action: {
                selectedTab = .live
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundColor(selectedTab == .live ? .white : .gray.opacity(0.6))
                    
                    Text("LIVE")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == .live ? .white : .gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            
            // Videos button
            Button(action: {
                selectedTab = .videos
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedTab == .videos ? .white : .gray.opacity(0.6))
                    
                    Text("Videos")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == .videos ? .white : .gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            
            // Upload button
            Button(action: {
                selectedTab = .upload
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Inbox button
            Button(action: {
                selectedTab = .inbox
            }) {
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message")
                            .font(.system(size: 22))
                            .foregroundColor(selectedTab == .inbox ? .white : .gray.opacity(0.6))
                        
                        if inboxBadgeCount > 0 {
                            Text("\(min(inboxBadgeCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                                .frame(width: inboxBadgeCount < 10 ? 16 : 20, height: 16)
                        }
                    }
                    
                    Text("Inbox")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == .inbox ? .white : .gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            
            // Profile button
            Button(action: {
                selectedTab = .profile
            }) {
                VStack(spacing: 3) {
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(selectedTab == .profile ? Color.white : Color.clear, lineWidth: 2)
                            )
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(String(userIdentifier.prefix(1).uppercased()))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            )
                            .overlay(
                                Circle()
                                    .stroke(selectedTab == .profile ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                    
                    Text("Profile")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == .profile ? .white : .gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(Color.black)
                .edgesIgnoringSafeArea(.bottom)
        )
        .onAppear {
            loadProfileImage()
            checkInboxBadges()
        }
    }
    
    private func loadProfileImage() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first,
               let imageAsset = record["profileImage"] as? CKAsset,
               let imageUrl = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageUrl),
               let image = UIImage(data: imageData) {
                
                DispatchQueue.main.async {
                    self.profileImage = image
                }
            }
        }
    }
    
    private func checkInboxBadges() {
        // Create a consistent room ID format
        let database = CKContainer.default().publicCloudDatabase
        
        // Check for unread messages
        let userPredicate = NSPredicate(format: "receiverID == %@ AND isRead == %@", userIdentifier, NSNumber(value: false))
        let query = CKQuery(recordType: "ChatMessage", predicate: userPredicate)
        
        let operation = CKQueryOperation(query: query)
        var unreadCount = 0
        
        operation.recordMatchedBlock = { (_, _) in
            unreadCount += 1
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.inboxBadgeCount = unreadCount
                }
            case .failure(let error):
                print("Error fetching unread messages: \(error.localizedDescription)")
            }
        }
        
        database.add(operation)
    }
}
