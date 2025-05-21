import SwiftUI
import CloudKit

struct InboxView: View {
    let userIdentifier: String
    let firstName: String
    @State private var matches: [InboxUserMatch] = []
    @State private var selectedMatch: InboxUserMatch?
    @State private var isRefreshing = false
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Messages")
                        .font(.appTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                if isLoading {
                    Spacer()
                    PulsingLoaderView()
                    Spacer()
                } else if matches.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("No conversations yet")
                            .font(.appHeadline)
                            .foregroundColor(.white)
                        
                        Text("Your matches will appear here")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            isRefreshing = true
                            loadMatches()
                        }) {
                            Text("Refresh")
                                .font(.appBody)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(20)
                        }
                        .padding(.top, 20)
                    }
                    Spacer()
                } else {
                    // List of matches
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(matches) { match in
                                Button(action: {
                                    selectedMatch = match
                                }) {
                                    HStack(spacing: 12) {
                                        // Profile image
                                        if let profileImage = match.profileImage {
                                            Image(uiImage: profileImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 56, height: 56)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.5))
                                                .frame(width: 56, height: 56)
                                                .overlay(
                                                    Text(match.name.prefix(1))
                                                        .foregroundColor(.white)
                                                        .font(.appHeadline)
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(match.name)
                                                    .font(.appHeadline)
                                                    .foregroundColor(.white)
                                                
                                                Spacer()
                                                
                                                if let lastTime = match.lastMessageTime {
                                                    Text(timeAgoString(from: lastTime))
                                                        .font(.appCaption)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            
                                            if let lastMessage = match.lastMessage {
                                                Text(lastMessage)
                                                    .font(.appCaption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            } else {
                                                Text("Tap to start conversation")
                                                    .font(.appCaption)
                                                    .foregroundColor(.gray)
                                                    .italic()
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        VStack {
                                            if match.isOnline {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 10, height: 10)
                                            }
                                            
                                            if match.unreadCount > 0 {
                                                Text("\(match.unreadCount)")
                                                    .font(.appTiny)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal)
                                    .background(Color.black)
                                }
                                
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
            
            if isRefreshing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PulsingLoaderView()
                            .frame(width: 50, height: 50)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            loadMatches()
        }
        .fullScreenCover(item: $selectedMatch) { match in
            NavigationView {
                ChatView(
                    userIdentifier: userIdentifier,
                    userName: firstName,
                    matchId: match.id,
                    matchName: match.name,
                    onClose: {
                        selectedMatch = nil          // dismiss
                        loadMatches()                // refresh list
                    }
                )
                .navigationBarHidden(true)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .edgesIgnoringSafeArea(.all)
        }

    }
    
    private func loadMatches() {
        isLoading = true
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first, let matchIds = record["matches"] as? [String] {
                
                // If no matches, return early
                if matchIds.isEmpty {
                    DispatchQueue.main.async {
                        self.matches = []
                        self.isLoading = false
                        self.isRefreshing = false
                    }
                    return
                }
                
                var loadedMatches: [InboxUserMatch] = []
                let group = DispatchGroup()
                
                for matchId in matchIds {
                    group.enter()
                    
                    // Fetch match details
                    self.fetchUserDetails(userId: matchId) { name, image, isOnline, lastMessage, lastTime, unreadCount in
                        let match = InboxUserMatch(
                            id: matchId,
                            name: name ?? "User",
                            profileImage: image,
                            isOnline: isOnline,
                            lastMessage: lastMessage,
                            lastMessageTime: lastTime,
                            unreadCount: unreadCount
                        )
                        loadedMatches.append(match)
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    // Sort matches by last message time (most recent first)
                    self.matches = loadedMatches.sorted { match1, match2 in
                        let time1 = match1.lastMessageTime ?? Date.distantPast
                        let time2 = match2.lastMessageTime ?? Date.distantPast
                        return time1 > time2
                    }
                    self.isLoading = false
                    self.isRefreshing = false
                }
            } else {
                DispatchQueue.main.async {
                    self.matches = []
                    self.isLoading = false
                    self.isRefreshing = false
                }
                
                if let error = error {
                    print("Error loading matches: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func fetchUserDetails(
        userId: String,
        completion: @escaping (String?, UIImage?, Bool, String?, Date?, Int) -> Void
    ) {
        let database = CKContainer.default().publicCloudDatabase
        
        // First fetch the user profile
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                let name = record["firstName"] as? String
                var profileImage: UIImage? = nil
                var isOnline = false
                
                // Check if online (active in last 2 minutes)
                if let lastActive = record["lastActiveTime"] as? Date {
                    let twoMinutesAgo = Date().addingTimeInterval(-120)
                    isOnline = lastActive > twoMinutesAgo
                }
                
                // Load profile image if available
                if let imageAsset = record["profileImage"] as? CKAsset,
                   let imageUrl = imageAsset.fileURL {
                    do {
                        let imageData = try Data(contentsOf: imageUrl)
                        profileImage = UIImage(data: imageData)
                    } catch {
                        print("Error loading profile image: \(error.localizedDescription)")
                    }
                }
                
                // Now fetch the most recent message and unread count
                self.fetchLastMessage(userIdentifier: self.userIdentifier, otherUserId: userId) { lastMessage, lastTime, unreadCount in
                    completion(name, profileImage, isOnline, lastMessage, lastTime, unreadCount)
                }
            } else {
                completion(nil, nil, false, nil, nil, 0)
                
                if let error = error {
                    print("Error fetching user details: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func fetchLastMessage(
        userIdentifier: String,
        otherUserId: String,
        completion: @escaping (String?, Date?, Int) -> Void
    ) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Create a consistent room ID
        let roomId = [userIdentifier, otherUserId].sorted().joined(separator: "-")
        
        // Query for the most recent message
        let predicate = NSPredicate(format: "roomID == %@", roomId)
        let query = CKQuery(recordType: "ChatMessage", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1
        
        var lastMessage: String?
        var lastTime: Date?
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                lastMessage = record["message"] as? String
                lastTime = record["timestamp"] as? Date
            case .failure(let error):
                print("Error fetching last message: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { result in
            // Count unread messages
            let unreadPredicate = NSPredicate(format: "roomID == %@ AND senderID == %@ AND receiverID == %@ AND isRead == %@",
                                            roomId, otherUserId, userIdentifier, NSNumber(value: false))
            let unreadQuery = CKQuery(recordType: "ChatMessage", predicate: unreadPredicate)
            
            let unreadOperation = CKQueryOperation(query: unreadQuery)
            var unreadCount = 0
            
            unreadOperation.recordMatchedBlock = { (_, _) in
                unreadCount += 1
            }
            
            unreadOperation.queryResultBlock = { _ in
                completion(lastMessage, lastTime, unreadCount)
            }
            
            database.add(unreadOperation)
        }
        
        database.add(operation)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            if day == 1 {
                return "Yesterday"
            } else if day < 7 {
                return "\(day)d ago"
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yy"
                return dateFormatter.string(from: date)
            }
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m ago"
        } else {
            return "Just now"
        }
    }
}

// In InboxView.swift, rename the UserMatch struct at line 380:
struct InboxUserMatch: Identifiable {
    let id: String
    let name: String
    let profileImage: UIImage?
    var isOnline: Bool = false
    var lastMessage: String?
    var lastMessageTime: Date?
    var unreadCount: Int = 0
}
