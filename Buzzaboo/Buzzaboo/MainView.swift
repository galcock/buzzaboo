import SwiftUI
import CloudKit
import LiveKit
import AVFoundation
import Foundation
import CommonCrypto
import LiveKitWebRTC
import AVKit
import CoreLocation
import AuthenticationServices
import Security

// Add this struct outside other declarations
struct UnifiedProfileDetails {
    let id: String
    let name: String
    var image: UIImage?
    var gender: String = "Not specified"
    var stateOfMind: String = ""
    var religion: String = ""
    var showReligion: Bool = false
    var jobTitle: String = ""
    var showJobTitle: Bool = false
    var school: String = ""
    var showSchool: Bool = false
    var hometown: String = ""
    var showHometown: Bool = false
    var instagramHandle: String = ""
    var twitterHandle: String = ""
    var likeCount: Int = 0
    var distanceMiles: Double? = nil
    var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
}

struct MainView: View {
    @StateObject private var signalingClient: SignalingClient
    let userIdentifier: String
    let firstName: String
    @StateObject private var locationManager: LocationManager
    @State private var matchedUser: CKRecord?
    @State private var timer = 0
    @State private var lastMatchTime: Date = Date.distantPast
    @State private var showingVideoCall = false
    @State private var currentSwipeMode: SwipeMode = .oneToOne
    @State private var swipeCount: Int = 0
    @State private var popularVideos: [(userId: String, videoId: String, url: URL, title: String, views: Int)] = []
    @State private var currentPopularVideoIndex: Int = 0
    @State private var noMoreUsersAvailable = false
    @State private var previousMatches: [String] = []
    @State private var currentPopularVideo: (userId: String, videoId: String, url: URL, title: String, views: Int)? = nil
    @State private var showingVideoFeed = false
    @State private var activityTimer: Timer?
    @State private var callRequestTimer: Timer?
    
    let swipeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    enum SwipeMode {
        case oneToOne
        case viewer
        case popularVideos
    }
    
    // Add this to MainView's initialization
    init(userIdentifier: String, firstName: String) {
        self.userIdentifier = userIdentifier
        self.firstName = firstName
        _locationManager = StateObject(wrappedValue: LocationManager(userIdentifier: userIdentifier))
        _signalingClient = StateObject(wrappedValue: SignalingClient(userId: userIdentifier))
        
        // Set up autoreleasepool for better memory management on older devices
        autoreleasepool {
            // Pre-initialize any expensive resources here
        }
    }

    var body: some View {
        // Instead of a full-covering ZStack, use VStack without filling the entire screen
        VStack(spacing: 0) {
            ZStack {
                Color.appBackground  // Remove the .edgesIgnoringSafeArea(.all) to prevent it from covering the navigation bar
                
                VStack {
                    if let user = matchedUser, let name = user["firstName"] as? String {
                        // Go straight to video call
                        if !showingVideoCall {
                            Text("Connecting with \(name)...")
                                .font(.appHeadline)
                                .foregroundColor(.appForeground)
                            
                            PulsingLoaderView()
                                .padding()
                            
                            // Auto-start the call
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showingVideoCall = true
                                }
                            }
                        }
                    } else {
                        Text("Finding a match...")
                            .font(.appBody)
                            .foregroundColor(.appForeground)
                        PulsingLoaderView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    
        .overlay {
            if showingVideoCall, let user = matchedUser, let userId = user["identifier"] as? String {
                ZStack {
                    Color.black.opacity(0.9).edgesIgnoringSafeArea(.all)
                    
                    VideoCallWithFallbackView(
                        matchedUserId: userId,
                        matchedUserName: user["firstName"] as? String ?? "User",
                        userIdentifier: userIdentifier,
                        firstName: firstName,
                        onLike: {
                            if let matchedUser = matchedUser {
                                likeUser()
                            }
                        }
                    )
                    .padding(.bottom, 0) // Add padding to make room for the nav bar
                }
                .zIndex(100)
                .transition(.opacity)
                .animation(.easeInOut, value: showingVideoCall)
            }
        }
        .onAppear(perform: {
            
            // Add this new notification observer
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("CloseVideoCall"),
                    object: nil,
                    queue: .main
                ) { _ in
                    self.showingVideoCall = false
                }
            
            startCallRequestChecker()
            
            CallRequestObserver.shared.startObserving(for: userIdentifier)
            
            // Add observer for direct calls
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StartDirectCall"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let userId = userInfo["userId"] as? String,
                   let name = userInfo["name"] as? String {
                    
                    // Create a temporary match record to use with the video call system
                    let matchRecord = CKRecord(recordType: "UserProfile")
                    matchRecord["identifier"] = userId
                    matchRecord["firstName"] = name
                    
                    // Update state to trigger the video call view
                    self.matchedUser = matchRecord
                    self.showingVideoCall = true
                }
            }

            // Add observer for match list refresh
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ForceMatchListRefresh"),
                object: nil,
                queue: .main
            ) { _ in
                // For MainView, refresh by triggering a match search
                if let location = self.locationManager.location {
                    self.matchNextUser()
                }
            }
            
            // Add timer to keep updating activity status
            let activityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                self.updateUserActivity()
            }
            // Initial update
            updateUserActivity()

            // Store the timer so it can be invalidated in onDisappear
            self.activityTimer = activityTimer
            
            matchNextUser()
        })
        .onChange(of: locationManager.location) { newLocation in
            let now = Date()
            guard now.timeIntervalSince(lastMatchTime) >= 10.0 else { return }
            guard let oldLocation = locationManager.location, let newLoc = newLocation else { return }
            let distance = oldLocation.distance(from: newLoc) / 111000
            guard distance >= 0.001 else { return }
            Task { @MainActor in
                lastMatchTime = now
                matchNextUser()
            }
        }
        .onDisappear {
            print("MainView is disappearing - doing cleanup")
            
            CallRequestObserver.shared.stopObserving()
            
            // First properly disconnect any active connections
            signalingClient.disconnect()
            
            // Reset the matchedUser state to ensure we can make a new match
            DispatchQueue.main.async {
                self.matchedUser = nil
                self.showingVideoCall = false
            }
            
            // Invalidate timers
            activityTimer?.invalidate()
            activityTimer = nil
        }
    }
    
    // Also add this new function to MainView:
    private func sendMatchNotification() {
        // Only send if there's an active video call
        if showingVideoCall, let matchedUserId = matchedUser?["identifier"] as? String {
            let matchData = ["type": "match", "sender": userIdentifier, "name": firstName]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: matchData)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("Sending match notification via active call")
                    
                    // Use signalingClient to send data message
                    Task {
                        if let data = jsonString.data(using: .utf8) {
                            do {
                                try await signalingClient.room.localParticipant.publish(data: data)
                                print("Match notification sent successfully")
                            } catch {
                                print("Failed to send match notification: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            } catch {
                print("Failed to serialize match notification: \(error.localizedDescription)")
            }
        }
    }
    
    // Add this function to MainView:
    private func startCallRequestChecker() {
        print("Starting call request checker")
        
        // Cancel any existing timer
        callRequestTimer?.invalidate()
        
        // Create a timer that checks periodically for call requests
        callRequestTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkForCallRequests(userId: self.userIdentifier)
        }
        
        // Do an initial check
        checkForCallRequests(userId: userIdentifier)
    }
    
    // Add this method to the MainView struct
    private func tryToShowCallAlert(from senderName: String, senderId: String, requestId: String) {
        // Create and show a popup notification
        let alert = UIAlertController(
            title: "\(senderName) wants to video chat",
            message: "Would you like to accept their request?",
            preferredStyle: .alert
        )
        
        // Accept option
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            // Accept the call and start a video session
            CallRequestManager.shared.respondToCallRequest(requestId: requestId, accept: true)
            
            // Start a 1:1 call with this person
            NotificationCenter.default.post(
                name: NSNotification.Name("StartDirectCall"),
                object: nil,
                userInfo: [
                    "userId": senderId,
                    "name": senderName
                ]
            )
        })
        
        // Decline options
        alert.addAction(UIAlertAction(title: "Sorry, I'm busy", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Sorry, I'm busy right now :("
            )
        })
        
        alert.addAction(UIAlertAction(title: "Can't talk now", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Sorry, I can't talk right now :("
            )
        })
        
        alert.addAction(UIAlertAction(title: "Try me later", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Please try me later!"
            )
        })
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let controller = windowScene.windows.first?.rootViewController {
            controller.present(alert, animated: true)
        }
    }
    
    // Add to MainView for better call request handling
    // Add this method to the MainView struct
    private func refreshCallRequestCheck() {
        print("Performing forced check for call requests")
        
        CallRequestManager.shared.fetchCallRequests(forUser: userIdentifier) { records in
            if !records.isEmpty {
                DispatchQueue.main.async {
                    print("Found \(records.count) pending call requests during manual check")
                    // Process the most recent request
                    if let request = records.first,
                       let senderId = request["senderId"] as? String,
                       let senderName = request["senderName"] as? String {
                        
                        // Mark as processing to avoid duplicate alerts
                        let database = CKContainer.default().publicCloudDatabase
                        request["status"] = "processing"
                        database.save(request) { _, _ in }
                        
                        // Show the call request alert
                        self.showCallRequestAlert(from: senderName, senderId: senderId, requestId: request.recordID.recordName)
                    }
                }
            }
        }
    }

    func checkForCallRequests(userId: String) {
        print("Checking for call requests to \(userId)")
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Update the predicate to ONLY fetch requests that have status "pending"
        // AND have not been marked as "processing" or "processed"
        let predicate = NSPredicate(format: "receiverId == %@ AND status == %@ AND (processingTime == nil OR processingTime == %@)",
                                  userId, "pending", NSNull())
        let query = CKQuery(recordType: "CallRequest", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching call requests: \(error.localizedDescription)")
                return
            }
            
            if let records = records, !records.isEmpty {
                print("Found \(records.count) new pending call requests")
                
                DispatchQueue.main.async {
                    if let request = records.first,
                       let senderId = request["senderId"] as? String,
                       let senderName = request["senderName"] as? String {
                        
                        print("Processing call request from \(senderName)")
                        
                        // CRITICAL: Mark this request as processing IMMEDIATELY
                        // Add a timestamp to ensure we don't process it again
                        request["processingTime"] = Date()
                        request["status"] = "processing"
                        
                        database.save(request) { _, saveError in
                            if let saveError = saveError {
                                print("Error marking request as processing: \(saveError.localizedDescription)")
                            } else {
                                print("✅ Marked call request as processing to prevent duplicates")
                            }
                        }
                        
                        // Show call request alert
                        self.tryToShowCallAlert(from: senderName, senderId: senderId, requestId: request.recordID.recordName)
                    }
                }
            }
        }
    }

    // In CallRequestManager:
    func respondToCallRequest(requestId: String, accept: Bool, responseMessage: String = "") {
        print("Responding to call request: \(requestId), accept: \(accept)")
        
        let database = CKContainer.default().publicCloudDatabase
        let recordID = CKRecord.ID(recordName: requestId)
        
        database.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching call request: \(error.localizedDescription)")
                return
            }
            
            guard let record = record else {
                print("No call request found with ID: \(requestId)")
                return
            }
            
            // Update record with response
            record["status"] = accept ? "accepted" : "declined"
            record["responseMessage"] = responseMessage
            record["responseTime"] = Date()
            record["processed"] = true  // Add this boolean flag
            
            // Save with higher priority
            let saveOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            saveOperation.savePolicy = .changedKeys
            saveOperation.qualityOfService = .userInitiated
            
            saveOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("Successfully responded to call request: \(accept ? "accepted" : "declined")")
                    
                    // Post notification for accepted calls
                    if accept, let senderId = record["senderId"] as? String,
                            let senderName = record["senderName"] as? String {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("StartDirectCall"),
                                object: nil,
                                userInfo: [
                                    "userId": senderId,
                                    "name": senderName
                                ]
                            )
                        }
                    }
                case .failure(let error):
                    print("Error responding to call request: \(error.localizedDescription)")
                }
            }
            
            database.add(saveOperation)
        }
    }

    
    // Modify matchNextUser() in MainView
    func matchNextUser() {
        print("Starting matchNextUser with userIdentifier: \(userIdentifier)")
        
        // If no location available yet, try again after a short delay
        guard let userLocation = locationManager.location else {
            print("No location available for matching, waiting for location...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.matchNextUser()
            }
            return
        }
        
        // Always update activity status before matching
        updateUserActivity()
        
        // Always use 1:1 mode
        currentSwipeMode = .oneToOne
        print("Showing 1:1 mode")
        
        // Reset noMoreUsersAvailable for each new attempt
        noMoreUsersAvailable = false
        
        // Try 1:1 matching
        matchOneToOne(userLocation: userLocation)
    }
    
    // Add this method to handle incoming call requests:
    private func showCallRequestAlert(from senderName: String, senderId: String, requestId: String) {
        let alert = UIAlertController(
            title: "\(senderName) wants to video chat",
            message: "Would you like to accept their request?",
            preferredStyle: .alert
        )
        
        // Accept option
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            // Accept the call and start a video session
            CallRequestManager.shared.respondToCallRequest(requestId: requestId, accept: true)
            
            // Start a 1:1 call with this person
            self.startDirectCall(with: senderId, name: senderName)
        })
        
        // Decline options
        alert.addAction(UIAlertAction(title: "Sorry, I'm busy", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Sorry, I'm busy right now :("
            )
        })
        
        alert.addAction(UIAlertAction(title: "Can't talk now", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Sorry, I can't talk right now :("
            )
        })
        
        alert.addAction(UIAlertAction(title: "Try me later", style: .destructive) { _ in
            CallRequestManager.shared.respondToCallRequest(
                requestId: requestId,
                accept: false,
                responseMessage: "Please try me later!"
            )
        })
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let controller = windowScene.windows.first?.rootViewController {
            controller.present(alert, animated: true)
        }
    }

    // Add method to start a direct call:
    private func startDirectCall(with userId: String, name: String) {
        // Create a temporary match record to use with the video call system
        let matchRecord = CKRecord(recordType: "UserProfile")
        matchRecord["identifier"] = userId
        matchRecord["firstName"] = name
        
        // Update state to trigger the video call view
        self.matchedUser = matchRecord
        self.showingVideoCall = true
    }
    
    func updateUserActivity() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                // Update the activity timestamp
                userRecord["lastActiveTime"] = Date()
                
                // Save with proper error handling
                database.save(userRecord) { savedRecord, error in
                    if let error = error as? CKError {
                        if error.code == .serverRecordChanged {
                            // Handle conflict by refetching and retrying
                            self.refetchAndUpdateActivity()
                        } else {
                            print("Error updating activity status: \(error.localizedDescription)")
                        }
                    } else {
     //                   print("✅ User activity status updated successfully")
                    }
                }
            }
        }
    }

    func refetchAndUpdateActivity() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                userRecord["lastActiveTime"] = Date()
                database.save(userRecord) { _, _ in }
            }
        }
    }

    // Match for 1-to-1 video chat
    private func matchOneToOne(userLocation: CLLocation) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Simple predicate that just makes sure we're not matching with ourselves
        let predicate = NSPredicate(format: "identifier != %@", userIdentifier)
        
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error querying for users: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.noMoreUsersAvailable = true
                    self.currentSwipeMode = .popularVideos
         //           self.showPopularVideo()
                }
                return
            }
            
            if let userRecords = records, !userRecords.isEmpty {
                // Filter out previously matched users
                let availableUsers = userRecords.filter { record in
                    if let id = record["identifier"] as? String {
                        return !self.previousMatches.contains(id)
                    }
                    return true
                }
                
                if !availableUsers.isEmpty {
                    // Get the current timestamp for comparison
                    let thirtySecondsAgo = Date().addingTimeInterval(-30)
                    
                    // STRICT FILTER: Only include users with a recent lastActiveTime
                    let activeUsers = availableUsers.filter { record in
                        if let lastActive = record["lastActiveTime"] as? Date {
                            return lastActive > thirtySecondsAgo
                        }
                        // Exclude users without lastActiveTime - they aren't active
                        return false
                    }
                    
                    if !activeUsers.isEmpty {
                        // Sort by distance if location is available
                        let sortedUsers = activeUsers.sorted { (u1, u2) -> Bool in
                            let loc1 = u1["location"] as? CLLocation ?? CLLocation(latitude: 0, longitude: 0)
                            let loc2 = u2["location"] as? CLLocation ?? CLLocation(latitude: 0, longitude: 0)
                            return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
                        }
                        
                        DispatchQueue.main.async {
                            if let matchedUser = sortedUsers.first {
                                self.matchedUser = matchedUser
                                self.timer = 0
                                
                                // Add to previous matches
                                if let id = matchedUser["identifier"] as? String {
                                    self.previousMatches.append(id)
                                }
                                
                                print("Matched with active user: \(matchedUser["firstName"] ?? "Unknown") for 1-to-1")
                                
                                // Auto-start video call after a brief delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.showingVideoCall = true
                                }
                            } else {
                                print("No active users found for 1-to-1 matching, retrying soon")
                                // Try again after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    self.matchNextUser()
                                }
                            }
                        }
                    } else {
                        print("No active users available, retrying soon")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.matchNextUser()
                        }
                    }
                } else {
                    print("No unmatched users available")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.matchNextUser()
                    }
                }
            } else {
                print("No users found in database")
                DispatchQueue.main.async {
                    self.matchNextUser()
                }
            }
        }
    }
    
    // Add this new method
    func checkForMutualLike(otherUserId: String) {
        let database = CKContainer.default().publicCloudDatabase
        
        // First get our record to see if we have likes from this user
        let myPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { (records, error) in
            // Remove [weak self] since MainView is a struct
            guard let myRecord = records?.first else { return }
            
            // Check if the other user has liked us
            if let likedByUsers = myRecord["likedBy"] as? [String],
               likedByUsers.contains(otherUserId) {
                
                // It's a match!
                DispatchQueue.main.async {
                    print("MATCH DETECTED between \(self.userIdentifier) and \(otherUserId)")
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("UserMatchNotification"),
                        object: nil,
                        userInfo: ["matchedName": self.matchedUser?["firstName"] as? String ?? "User"]
                    )
                }
                
                // Update the database to record the match
                var matches = myRecord["matches"] as? [String] ?? []
                if !matches.contains(otherUserId) {
                    matches.append(otherUserId)
                    myRecord["matches"] = matches
                    database.save(myRecord) { _, _ in }
                }
            }
        }
    }
    
    // Add this function to MainView
    private func showMatchNotification(name: String) {
        // Create and show a popup notification
        withAnimation {
            NotificationCenter.default.post(
                name: Notification.Name("UserMatchNotification"),
                object: nil,
                userInfo: ["matchedName": name]
            )
        }
        
        // No need to play sound or show UI directly from MainView
        // Instead, we'll use the notification observer in LiveKitVideoCallView
        // which already handles showing the UI and playing sounds
    }
    
    private func checkForMatch(myRecord: CKRecord, otherUserId: String) {
        print("🔍 Checking for match with user: \(otherUserId)")
        let database = CKContainer.default().publicCloudDatabase
        let otherUserPredicate = NSPredicate(format: "identifier == %@", otherUserId)
        let otherUserQuery = CKQuery(recordType: "UserProfile", predicate: otherUserPredicate)
        
        database.perform(otherUserQuery, inZoneWith: nil) { otherRecords, error in
            if let error = error {
                print("❌ Error finding other user's record: \(error.localizedDescription)")
                return
            }
            
            guard let otherRecord = otherRecords?.first else {
                print("❌ Could not find other user's record")
                return
            }
            
            print("✅ Found other user's record")
            
            // Check if the other user has liked the current user
            if let otherLikedUsers = otherRecord["likedUsers"] as? [String],
               otherLikedUsers.contains(self.userIdentifier) {
                
                print("💘 MATCH DETECTED! Other user has also liked current user")
                
                // Update both users' matches arrays
                self.addMatchToRecords(
                    myRecord: myRecord,
                    otherRecord: otherRecord,
                    myId: self.userIdentifier,
                    otherId: otherUserId
                )
            } else {
                print("⚠️ No match yet - other user hasn't liked current user")
            }
        }
    }
    
    private func addMatchToRecords(myRecord: CKRecord, otherRecord: CKRecord, myId: String, otherId: String) {
        print("📝 Adding match relationship between \(myId) and \(otherId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // First add the match to my record
        var myMatches = myRecord["matches"] as? [String] ?? []
        let wasNewMatch = !myMatches.contains(otherId)
        
        if wasNewMatch {
            myMatches.append(otherId)
            myRecord["matches"] = myMatches
            
            // Save my updated record
            database.save(myRecord) { _, error in
                if let error = error {
                    print("❌ Error saving my matches: \(error.localizedDescription)")
                } else {
                    print("✅ Successfully added to my matches")
                    
                    // Now update the other user's record
                    var otherMatches = otherRecord["matches"] as? [String] ?? []
                    if !otherMatches.contains(myId) {
                        otherMatches.append(myId)
                        otherRecord["matches"] = otherMatches
                        
                        // Save the other user's record
                        database.save(otherRecord) { _, otherError in
                            if let otherError = otherError {
                                print("❌ Error saving other user's matches: \(otherError.localizedDescription)")
                            } else {
                                print("✅ Successfully added to other user's matches")
                                
                                // If this was a new match, create a match notification record
                                if wasNewMatch {
                                    // Create a match notification record in CloudKit
                                    let matchRecord = CKRecord(recordType: "MatchNotification")
                                    matchRecord["user1"] = myId
                                    matchRecord["user2"] = otherId
                                    matchRecord["timestamp"] = Date()
                                    matchRecord["processed"] = false
                                    
                                    // Save the match notification record
                                    database.save(matchRecord) { savedRecord, matchError in
                                        if let matchError = matchError {
                                            print("❌ Error saving match notification: \(matchError.localizedDescription)")
                                        } else {
                                            print("✅ Created match notification record for both users")
                                        }
                                    }
                                    
                                    // Also post the local notification for immediate feedback
                                    let otherName = otherRecord["firstName"] as? String ?? "User"
                                    print("🎉 Sending match notification for: \(otherName)")
                                    
                                    // Post the notification that LiveKitVideoCallView will observe
                                    NotificationCenter.default.post(
                                        name: Notification.Name("UserMatchNotification"),
                                        object: nil,
                                        userInfo: ["matchedName": otherName]
                                    )
                                    // Add this right after it to send the notification to the other user too:
                                    self.sendMatchNotification()

                                }
                            }
                        }
                    } else {
                        print("⚠️ Match already exists in other user's record")
                    }
                }
            }
        } else {
            print("⚠️ Match already exists in current user's record")
        }
    }
    
    func likeUser() {
        guard let user = matchedUser, let matchedId = user["identifier"] as? String else {
            print("⚠️ Cannot like - user record or ID missing")
            return
        }
        
        print("🧡 Starting like process for user ID: \(matchedId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // 1. Update the liked user's like count
        let likeCount = (user["likeCount"] as? Int ?? 0) + 1
        user["likeCount"] = likeCount
        
        // Save the like in the database
        database.save(user) { _, error in
            if let error = error {
                print("❌ Like save error: \(error.localizedDescription)")
            } else {
                print("✅ Like count saved successfully, new count: \(likeCount)")
            }
        }
        
        // 2. Store this like in the current user's record (who liked)
        let myPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate) // Changed predicate to myPredicate
        
        database.perform(myQuery, inZoneWith: nil) { myRecords, error in
            if let error = error {
                print("❌ Error finding current user record: \(error.localizedDescription)")
                return
            }
            
            guard let myRecord = myRecords?.first else {
                print("❌ Could not find current user record")
                return
            }
            
            // Add to likedUsers array
            var likedUsers = myRecord["likedUsers"] as? [String] ?? []
            if !likedUsers.contains(matchedId) {
                likedUsers.append(matchedId)
                myRecord["likedUsers"] = likedUsers
                print("➕ Adding \(matchedId) to likedUsers array")
                
                // Save the updated record
                database.save(myRecord) { _, likedError in
                    if let likedError = likedError {
                        print("❌ Error saving likedUsers: \(likedError.localizedDescription)")
                    } else {
                        print("✅ Successfully updated likedUsers array")
                        
                        // Now check if this creates a match
                        self.checkForMatch(myRecord: myRecord, otherUserId: matchedId)
                    }
                }
            } else {
                print("⚠️ User already liked, skipping save")
                // Still check for match in case it wasn't processed before
                self.checkForMatch(myRecord: myRecord, otherUserId: matchedId)
            }
        }
    }

    // Helper function to show match notification
   
}

// Update VideoCallWithFallbackView to handle being used as an overlay
struct VideoCallWithFallbackView: View {
    let matchedUserId: String
    let matchedUserName: String
    let userIdentifier: String
    let firstName: String
    let onLike: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var showLocalCamera = true
    @State private var connectionFailed = false
    
    var body: some View {
        ZStack {
            if connectionFailed {
                // Fallback to local video only
                LocalOnlyVideoView(
                    matchedUserName: matchedUserName,
                    onClose: {
                        // Don't use presentation mode dismiss since we're no longer using fullScreenCover
                        NotificationCenter.default.post(name: NSNotification.Name("CloseVideoCall"), object: nil)
                    },
                    onLike: onLike
                )
            } else {
                // Try LiveKit connection
                LiveKitVideoCallView(
                    matchedUserId: matchedUserId,
                    matchedUserName: matchedUserName,
                    userIdentifier: userIdentifier,
                    firstName: firstName,
                    onFailure: {
                        connectionFailed = true
                    },
                    onClose: {
                        // Don't use presentation mode dismiss since we're no longer using fullScreenCover
                        NotificationCenter.default.post(name: NSNotification.Name("CloseVideoCall"), object: nil)
                    },
                    onLike: onLike,
                    onMatch: { matchedName in
                        // Just show the match notification
                    }
                )
            }
        }
    }
}

struct LiveKitVideoCallView: View {
    let matchedUserId: String
    let matchedUserName: String
    let userIdentifier: String
    let firstName: String
    @State private var activeRoom: Room? = nil
    let onFailure: () -> Void
    let onClose: () -> Void
    let onLike: () -> Void
    let onMatch: (_ matchedName: String) -> Void
 //   private var chatDataDelegate: ChatDataDelegate?
 //   private let delegateHolder = DelegateHolder()

    
    // Add an explicit initializer
       init(matchedUserId: String,
            matchedUserName: String,
            userIdentifier: String,
            firstName: String,
            onFailure: @escaping () -> Void,
            onClose: @escaping () -> Void,
            onLike: @escaping () -> Void,
            onMatch: @escaping (_ matchedName: String) -> Void) {
           
           self.matchedUserId = matchedUserId
           self.matchedUserName = matchedUserName
           self.userIdentifier = userIdentifier
           self.firstName = firstName
           self.onFailure = onFailure
           self.onClose = onClose
           self.onLike = onLike
           self.onMatch = onMatch
       }
    
    // State variables
    // Add these state variables to LiveKitVideoCallView
    @State private var profileImage: UIImage? = nil
    @State private var matchedUserInstagramHandle: String? = nil
    @State private var matchedUserTwitterHandle: String? = nil
    @State private var lastQueryTime: Date = Date().addingTimeInterval(-60) // Start by fetching last minute of messages
    @State private var cloudKitChatTimer: Timer? = nil
    @State private var locationManager: LocationManager? = nil
    @State private var matchedUserGender: String = "Prefer not to say"
    @State private var matchedUserShowJobTitle: Bool = false
    @State private var matchedUserJobTitle: String = ""
    @State private var matchedUserShowSchool: Bool = false
    @State private var matchedUserSchool: String = ""
    @State private var matchedUserShowReligion: Bool = false
    @State private var matchedUserReligion: String = ""
    @State private var matchedUserShowHometown: Bool = false
    @State private var matchedUserHometown: String = ""
    @State private var matchedUserVideos: [(id: UUID, title: String, url: URL?, views: Int)] = []
    @State private var matchedUserLocation: CLLocation?
    @State private var matchedUserDistanceMiles: Double?
    @State private var otherUserHasLiked = false
    @State private var userAcceptedPrivate = false
    @State private var otherUserAcceptedPrivate = false
    @State private var isPrivateMode = false
    @State private var showPrivateConfirmation = false
    @State private var showMatchMessage = false
    @State private var showSwipeHint = false
    @State private var swipeProgress: CGFloat = 0
    @State private var isConnected = false
    @State private var errorMessage: String?
    @State private var showDebugInfo = false
    @State private var connectionAttempts = 0
    @State private var debugLogs: String = ""
    @State private var showDebugLogs = false
    @State private var timer = 0
    @State private var hasLiked = false
    @State private var isLikeAnimating = false
    @State private var userLikes = 0
    @State var stateOfMind = ""
    @State private var showFullStateOfMind = false
    @State private var showProfileOverlay = false
    @State private var showLikeMessage = false
    @State private var showLikedByMessage = false
    @State private var hasReported = false
    @State private var showReportConfirmation = false
    @State private var showConnectionMessage = false
    @State private var showMyProfileEditor = false
    @State private var showJobTitle = false
    @State private var jobTitle = ""
    @State private var showSchool = false
    @State private var school = ""
    @State private var showReligion = false
    @State private var religion = ""
    @State private var showHometown = false
    @State private var hometown = ""
    @State private var matchedUserStateOfMind = ""  // Start empty until we fetch it
    @State private var showMatchedUserStateOfMind = false
    @State private var isCameraSwitching = false
    @State private var cameraPosition: AVCaptureDevice.Position = .front
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Chat related states
    @State private var chatMessage = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var showChat = false
    
    private let swipeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let maxConnectionAttempts = 3
    
    // Modify the body of LiveKitVideoCallView to hide chat UI
    var body: some View {
        ZStack {
            Color.appBackground.edgesIgnoringSafeArea(.all)
            
            // Video container - keep this unchanged
            if let room = activeRoom {
                LiveKitVideoUIView(room: room, parentView: self)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Spacer()
                        }
                        .allowsHitTesting(true)
                    )
            } else {
                // Show loading placeholder
                Color.appBackground.edgesIgnoringSafeArea(.all)
                PulsingLoaderView()
            }
            
            // Overlay UI - keep but remove chat components
            VStack(spacing: 0) {
                // Top bar with user info - keep this
                HStack {
                    Button(action: {
                        ProfileViewHelper.shared.showUserProfile(userId: matchedUserId)
                    }) {
                        HStack(spacing: 8) {
                                   // Small profile image
                                   if let profileImage = profileImage {
                                       Image(uiImage: profileImage)
                                           .resizable()
                                           .scaledToFill()
                                           .frame(width: 30, height: 30)
                                           .clipShape(Circle())
                                   } else {
                                       Circle()
                                           .fill(Color.gray.opacity(0.5))
                                           .frame(width: 30, height: 30)
                                           .overlay(
                                               Text(matchedUserName.prefix(1))
                                                   .foregroundColor(.white)
                                                   .font(.system(size: 16))
                                           )
                                   }
                                   
                            VStack(alignment: .leading, spacing: 4) {
                                // Name with distance
                                HStack(spacing: 4) {
                                    Text(matchedUserName)
                                        .font(.appHeadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appForeground)
                                    
                                    Text("(\(formatDistance()) mi away)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                
                                // State of Mind as quote under name
                                HStack {
                                    StateOfMindView(stateOfMind: matchedUserStateOfMind, showFullStateOfMind: $showMatchedUserStateOfMind)
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                               }
                               .padding()
                           }
                    
                    Spacer()

                    // LIVE indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isPrivateMode ? Color.purple : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(isPrivateMode ? "PRIVATE" : "LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isPrivateMode ? Color.purple.opacity(0.7) : Color.red.opacity(0.7))
                    )
                    
                    // Display like count
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.appCaption)
                        
                        Text("\(userLikes)")
                            .font(.appCaption)
                            .foregroundColor(.appForeground)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(12)
                }
                .padding(.top, 15)
                .padding(.horizontal)
                
                // Controls for remote video
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: UIScreen.main.bounds.height * 0.50)
                    
                    VStack {
                        Spacer()
                            .frame(height: UIScreen.main.bounds.height * 0.27)
                        
                        // MODIFIED: Move the buttons down with more spacing
                       // Spacer() // Add this to push buttons down
                        
                        // Buttons
                                    HStack(spacing: 20) {
                                        // Like button
                                        Button(action: {
                                            hasLiked.toggle()
                                            isLikeAnimating = true
                                            
                                            if hasLiked {
                                                onLike()
                                                sendLikeNotification()
                                                playSound("like")
                                            } else {
                                                unlikeUser()
                                                playSound("unlike")
                                            }
                                            
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                isLikeAnimating = false
                                            }
                                        }) {
                                            Image(systemName: hasLiked ? "heart.fill" : "heart")
                                                .font(.system(size: 22))
                                                .foregroundColor(hasLiked ? .red : .white)
                                                .padding(12)
                                                .background(Circle().fill(Color.black.opacity(0.3)))
                                                .scaleEffect(isLikeAnimating ? 1.3 : 1.0)
                                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLikeAnimating)
                                                .shadow(radius: 5)
                                        }
                                        
                                        // Report button
                                        Button(action: {
                                            if !hasReported {
                                                withAnimation {
                                                    showReportConfirmation = true
                                                }
                                            }
                                        }) {
                                            Image(systemName: "flag.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.gray.opacity(0.8))
                                                .padding(12)
                                                .background(Circle().fill(Color.black.opacity(0.3)))
                                        }
                                        .disabled(hasReported)
                                    }
                                    .offset(y: -40)
                                    Spacer() // Fill the rest of the space
                    }
                }
                
                if !isConnected {
                    Spacer()
                    Text("Connecting...")
                        .font(.appBody)
                        .foregroundColor(.appForeground)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    Spacer()
                } else {
                    Spacer()
                }

                
                // Swipe hint
                if showSwipeHint {
                    HStack {
                        Image(systemName: "hand.draw")
                            .font(.appCaption)
                            .foregroundColor(.appForeground)
                        Text("Swipe up for next match")
                            .font(.appCaption)
                            .foregroundColor(.appForeground)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                    .transition(.opacity)
                }
            }
            
            // Keep all the other overlays
            // Match message
            if showMatchMessage {
                VStack {
                    Text("You matched with \(matchedUserName)!")
                        .font(.appHeadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.8))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(100) // Make sure it appears on top
            }
            
            // Like messages
            if showLikedByMessage {
                VStack {
                    Text("\(matchedUserName) liked you!")
                        .font(.appHeadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.pink.opacity(0.8))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            
            // Connection success message
            if showConnectionMessage {
                VStack {
                    Text("Connected with \(matchedUserName)!")
                        .font(.appHeadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.8))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            
            // Debug log overlay
            if showDebugLogs {
                ScrollView {
                    Text(debugLogs)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.9))
                .onAppear {
                    
                    // Fix local preview with additional retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.fixLocalPreview()
                        
                        // Add extra retry for reliability
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.fixLocalPreview()
                        }
                    }
                    
                    // Add to your onAppear block
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ConnectLocalVideoTrack"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let trackId = notification.userInfo?["trackId"] as? String {
                            print("Received notification to connect local track: \(trackId)")
                            
                            // Force a UI update if needed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.fixLocalPreview()
                            }
                        }
                    }
                    
                    // Add in onAppear
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("CameraChangeInProgress"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Show a loading indicator if desired
                        // This is optional but would show the user something is happening
                    }

                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("CameraChangeCompleted"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Update UI if needed
                    }

                    // Add this notification to signal camera switching started
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("CameraSwitchingStarted"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Handle camera switching started
                        self.isCameraSwitching = true
                    }

                    // Add this notification to signal camera switching completed
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("CameraSwitchingCompleted"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Handle camera switching completed
                        self.isCameraSwitching = false
                    }
                    
                    // Also check for match notifications in CloudKit
                    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                        self.checkForMatchNotifications()
                    }
                    // Initial check
                    checkForMatchNotifications()
                    
                    fetchProfileData(userId: matchedUserId)
                    
                    // Load state of mind from CloudKit
                       loadUserStateOfMind()
                    
                    // Add this into your onAppear block
                    cloudKitChatTimer?.invalidate() // Cancel any existing timer
                    cloudKitChatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    //                    self.fetchRecentChatMessages()
                    }

                    // Initial fetch
    //                fetchRecentChatMessages()
                    
                    // Setup CloudKit chat polling here (ONCE)
                    lastQueryTime = Date().addingTimeInterval(-300) // Look back 5 minutes initially
    //                fetchRecentChatMessages() // Initial fetch
                    
                    // Create a SINGLE timer for CloudKit polling
                    cloudKitChatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
    //                    fetchRecentChatMessages()
                    }
                    
                    // Existing code...
                    fetchUserLikes()
    //                setupChatObserver()
                    playSound("connect")
                    
                    // Add notification observer for matches
                    NotificationCenter.default.addObserver(
                        forName: Notification.Name("UserMatchNotification"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let matchedName = notification.userInfo?["matchedName"] as? String {
                            withAnimation {
                                showMatchMessage = true
                            }
                            playSound("match")
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation {
                                    showMatchMessage = false
                                }
                            }
                        }
                    }
                    
                    // Add observer for profile updates
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("UserProfileUpdated"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        
                        // Update state variables with new profile data
                        if let stateOfMind = notification.userInfo?["stateOfMind"] as? String {
                            self.stateOfMind = stateOfMind
                        }
                        
                        if let showReligion = notification.userInfo?["showReligion"] as? Bool {
                            self.showReligion = showReligion
                        }
                        
                        if let religion = notification.userInfo?["religion"] as? String {
                            self.religion = religion
                        }
                        
                        if let showJobTitle = notification.userInfo?["showJobTitle"] as? Bool {
                            self.showJobTitle = showJobTitle
                        }
                        
                        if let showSchool = notification.userInfo?["showSchool"] as? Bool {
                            self.showSchool = showSchool
                        }
                        
                        if let showHometown = notification.userInfo?["showHometown"] as? Bool {
                            self.showHometown = showHometown
                        }
                        
                        // Update name label in local view if needed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Look for the local video container
                            if let uiView = self.activeRoom?.localParticipant as? UIView,
                               let container = uiView.viewWithTag(776),
                               let stateLabel = container.viewWithTag(778) as? UILabel {
                                stateLabel.text = self.stateOfMind.isEmpty ? "" : "\"\(self.stateOfMind)\""
                            }
                        }
                    }
                    
                    // Add observer for opening profile editor
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("OpenMyProfileEditor"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        showMyProfileEditor = true
                    }
                    
                

                    // Show and hide swipe hint periodically
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showSwipeHint = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showSwipeHint = false
                                }
                            }
                        }
                    }
                    
                    connectToRoom()
                    
                    // Fix local preview
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        fixLocalPreview()
                    }
                    
                    // Refresh logs when view appears
                    debugLogs = VideoDebugger.shared.dumpLogs()
                    
                    // Make sure any lingering swipe hint is hidden after some time
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if showSwipeHint {
                            withAnimation {
                                showSwipeHint = false
                            }
                        }
                    }
                }
                .onTapGesture {
                    showDebugLogs = false
                }
            }
            
            // Profile Overlay
            if showProfileOverlay {
                profileOverlayView()
                    .transition(.opacity)
                    .animation(.easeInOut, value: showProfileOverlay)
            }
            
            // Report confirmation dialog
            if showReportConfirmation {
                VStack(spacing: 16) {
                    Text("Report inappropriate behavior?")
                        .font(.appHeadline)
                        .foregroundColor(.appForeground)
                    
                    Text("This will increase the user's report count and notify moderation.")
                        .font(.appCaption)
                        .foregroundColor(.appForeground.opacity(0.8))
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            withAnimation {
                                showReportConfirmation = false
                            }
                        }
                        .font(.appBody)
                        .padding()
                        .background(Color.gray.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Report User") {
                            reportUser()
                            hasReported = true
                            withAnimation {
                                showReportConfirmation = false
                            }
                        }
                        .font(.appBody)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(24)
                .background(Color.black.opacity(0.9))
                .cornerRadius(16)
                .shadow(radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
                .edgesIgnoringSafeArea(.all)
            }
            
            // Error message overlay
            if let error = errorMessage {
                VStack {
                    Text("Connection Error")
                        .font(.appHeadline)
                        .foregroundColor(.appForeground)
                        .padding()
                    
                    Text(error)
                        .font(.appBody)
                        .foregroundColor(.appForeground)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    HStack {
                        Button("Try Again") {
                            errorMessage = nil
                            connectionAttempts = 0
                            connectToRoom()
                        }
                        .font(.appBody)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Use Fallback") {
                            onFailure()
                        }
                        .font(.appBody)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                .padding()
            }
            // Private mode confirmation - ADD THIS AT THE SAME LEVEL AS OTHER OVERLAY CONDITIONS
            // In your main ZStack, add this alongside other overlays
            // Add to main ZStack with other overlays
            if showPrivateConfirmation {
                VStack(spacing: 16) {
                    Text("You liked each other!")
                        .font(.appHeadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    
                    Text("Go private?")
                        .font(.appBody)
                        .foregroundColor(.white)
                        .padding(.bottom, 12)
                    
                    HStack(spacing: 20) {
                        Button("No") {
                            withAnimation {
                                showPrivateConfirmation = false
            //                    sendPrivateResponse(accept: false)
                            }
                        }
                        .font(.appBody)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Yes") {
            //                sendPrivateResponse(accept: true)
                            withAnimation {
                                showPrivateConfirmation = false
                            }
                        }
                        .font(.appBody)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(24)
                .background(Color.black.opacity(0.9))
                .cornerRadius(16)
                .shadow(radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
                .edgesIgnoringSafeArea(.all)
            }
          
            // Add this simpler camera flip button implementation to your view:
            VStack {
                Spacer()
                
                Button(action: {
                    // Prevent multiple simultaneous operations
                    guard !isCameraSwitching else { return }
                    isCameraSwitching = true
                    
                    // Toggle the camera preference in UserDefaults
                    let currentPosition = UserDefaults.standard.bool(forKey: "useBackCamera")
                    UserDefaults.standard.set(!currentPosition, forKey: "useBackCamera")
                    
                    print("Camera preference toggled from \(currentPosition ? "back" : "front") to \(!currentPosition ? "back" : "front")")
                    
                    // Disconnect the current room completely
                    if let currentRoom = activeRoom {
                        Task {
                            // Post notification that camera is switching
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: NSNotification.Name("CameraSwitchingStarted"), object: nil)
                            }
                            
                            // First disconnect completely
                            await currentRoom.disconnect()
                            
                            // Set activeRoom to nil to ensure clean slate
                            DispatchQueue.main.async {
                                self.activeRoom = nil
                            }
                            
                            // Create a completely fresh client
                            let signalingClient = SignalingClient(userId: self.userIdentifier)
                            
                            // Connect with new camera settings
                            signalingClient.connectToLiveKit { success in
                                if success {
                                    DispatchQueue.main.async {
                                        // Set the new room
                                        self.activeRoom = signalingClient.room
                                        
                                        // Reset switching state
                                        self.isCameraSwitching = false
                                        
                                        // Force refresh preview after a short delay
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            self.fixLocalPreview()
                                            
                                            // Notify that camera switch is complete
                                            NotificationCenter.default.post(name: NSNotification.Name("CameraSwitchingCompleted"), object: nil)
                                        }
                                    }
                                } else {
                                    print("Failed to reconnect with new camera position")
                                    DispatchQueue.main.async {
                                        self.isCameraSwitching = false
                                    }
                                }
                            }
                        }
                    } else {
                        print("No active room to disconnect")
                        DispatchQueue.main.async {
                            self.isCameraSwitching = false
                        }
                    }
                }) {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 22))
                        .foregroundColor(isCameraSwitching ? .gray : .white)
                        .padding(15)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                        .shadow(radius: 3)
                        .opacity(isCameraSwitching ? 0.5 : 1.0)
                }
                .disabled(isCameraSwitching)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: 10)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Show swipe hint on initial movement
                    if !showSwipeHint && abs(value.translation.height) > 10 {
                        withAnimation {
                            showSwipeHint = true
                        }
                    }
                    
                    // Calculate swipe progress for upward swipes only
                    if value.translation.height < 0 {
                        swipeProgress = min(1.0, abs(value.translation.height) / 150)
                    }
                }
                .onEnded { value in
                    // Reset swipe progress immediately regardless of swipe direction
                    swipeProgress = 0
                    
                    // If significant upward swipe, end call and return to matching
                    if value.translation.height < -100 && timer >= 10 {
                        // Hide the hint first to avoid it persisting
                        if showSwipeHint {
                            withAnimation {
                                showSwipeHint = false
                            }
                        }
                        
                        Task {
                            if let room = activeRoom {
                                await room.disconnect()
                            }
                            onClose()
                        }
                    } else {
                        // Explicitly hide the hint after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation {
                                showSwipeHint = false
                            }
                        }
                    }
                }
        )
        .onReceive(swipeTimer) { _ in
            if timer < 10 { timer += 1 }
        }
        .onAppear {
            
            // Add to onAppear
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ConnectLocalVideoTrack"),
                object: nil,
                queue: .main
            ) { notification in
                print("🎥 Received notification to connect new local track")
                
                if let trackId = notification.userInfo?["trackId"] as? String {
                    // Find the track by ID in the local participant's tracks
                    if let room = self.activeRoom {
                        for publication in room.localParticipant.trackPublications.values {
                            if publication.sid.stringValue == trackId {
                                print("🎥 Found matching track, connecting to view")
                                // Connect the track to the local video view
                                if let videoTrack = publication.track as? VideoTrack {
                                    self.connectLocalVideoTrackToView(videoTrack)
                                }
                                break
                            }
                        }
                    }
                }
            }
            
            fetchProfileData(userId: matchedUserId)
            // Load cached state of mind first
                let cachedStateOfMind = UserDefaults.standard.string(forKey: "userStateOfMind_\(userIdentifier)")
                if let cachedStateOfMind = cachedStateOfMind, !cachedStateOfMind.isEmpty {
                    stateOfMind = cachedStateOfMind
                    print("Initialized state of mind from cache: \(cachedStateOfMind)")
                }
            
            // Fetch user's like count from CloudKit
            fetchUserLikes()
            
   //         setupChatObserver()
            
            // Play connection sound
            playSound("connect")
            
            // Load state of mind from CloudKit
            loadUserStateOfMind()
            
            // Add notification observer for matches
            NotificationCenter.default.addObserver(
                forName: Notification.Name("UserMatchNotification"),
                object: nil,
                queue: .main
            ) { notification in
                if let matchedName = notification.userInfo?["matchedName"] as? String {
                    withAnimation {
                        showMatchMessage = true
                    }
                    playSound("match")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            showMatchMessage = false
                        }
                    }
                }
            }
            
            // Add observer for profile updates
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UserProfileUpdated"),
                object: nil,
                queue: .main
            ) { notification in
                
                // Update state variables with new profile data
                if let stateOfMind = notification.userInfo?["stateOfMind"] as? String {
                    self.stateOfMind = stateOfMind
                }
                
                if let showReligion = notification.userInfo?["showReligion"] as? Bool {
                    self.showReligion = showReligion
                }
                
                if let religion = notification.userInfo?["religion"] as? String {
                    self.religion = religion
                }
                
                if let showJobTitle = notification.userInfo?["showJobTitle"] as? Bool {
                    self.showJobTitle = showJobTitle
                }
                
                if let showSchool = notification.userInfo?["showSchool"] as? Bool {
                    self.showSchool = showSchool
                }
                
                if let showHometown = notification.userInfo?["showHometown"] as? Bool {
                    self.showHometown = showHometown
                }
                
                // Update name label in local view if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Look for the local video container
                    if let uiView = self.activeRoom?.localParticipant as? UIView,
                       let container = uiView.viewWithTag(776),
                       let stateLabel = container.viewWithTag(778) as? UILabel {
                        stateLabel.text = self.stateOfMind.isEmpty ? "" : "\"\(self.stateOfMind)\""
                    }
                }
            }
            
            // Add observer for opening profile editor
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OpenMyProfileEditor"),
                object: nil,
                queue: .main
            ) { _ in
                showMyProfileEditor = true
            }
            
            // Show and hide swipe hint periodically
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    showSwipeHint = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showSwipeHint = false
                        }
                    }
                }
            }
            
            connectToRoom()
            
            // Fix local preview
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                fixLocalPreview()
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            // Refresh debug logs periodically
            if showDebugLogs {
                debugLogs = VideoDebugger.shared.dumpLogs()
            }
        }
        .onDisappear {
            print("LiveKitVideoCallView disappearing - cleaning up resources")
                
                // Add to onDisappear
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ConnectLocalVideoTrack"), object: nil)
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("CameraSwitchingStarted"), object: nil)
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("CameraSwitchingCompleted"), object: nil)
                
                // Reset room to nil after disconnecting
                if let room = activeRoom {
                    Task {
                        print("Disconnecting from active room")
                        await room.disconnect()
                        
                        DispatchQueue.main.async {
                            self.activeRoom = nil
                            print("Set activeRoom to nil after disconnection")
                        }
                    }
                }
            
            // End the active session
            SignalingClient.sharedInstance.endActiveSession()
            print("Ended active session in SignalingClient")
            
            // Clean up CloudKit chat
   //         cleanupCloudKitChat()
            
            // Reset state
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionAttempts = 0
            }
            
            // Remove notification observers
            NotificationCenter.default.removeObserver(self, name: Notification.Name("UserMatchNotification"), object: nil)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("UserProfileUpdated"), object: nil)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("OpenMyProfileEditor"), object: nil)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ReceivedChatMessage"), object: nil)
        }
        
        // Add the fullScreenCover here, at the same level as the other view modifiers
        // Find this code in LiveKitVideoCallView:
        .fullScreenCover(isPresented: $showMyProfileEditor) {
            ProfileEditorView(
                firstName: firstName,
                userIdentifier: userIdentifier,
                stateOfMind: $stateOfMind,
                onSave: { newStateOfMind, religion, showJobTitle, showSchool, showReligion, showHometown, gender, jobTitle, school, hometown in
                    // Call the function that saves to CloudKit
                    saveProfileChanges(
                        newStateOfMind: newStateOfMind,
                        religion: religion,
                        showJobTitle: showJobTitle,
                        showSchool: showSchool,
                        showReligion: showReligion,
                        showHometown: showHometown,
                        gender: gender,
                        jobTitle: jobTitle,
                        school: school,
                        hometown: hometown
                    )
                    showMyProfileEditor = false
                },
                onCancel: {
                    showMyProfileEditor = false
                }
            )
            .interactiveDismissDisabled(true) // Add this line to prevent swipe dismissal
        }
        // Add this .onChange modifier at the bottom of your view:
        // Replace the existing onChange(of: scenePhase) modifier with this:
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // App came to foreground
                print("App became active, checking for camera position changes")
                if let room = activeRoom, room.connectionState == .connected {
                    Task {
                        do {
                            // Check if camera position has changed
                            let isBackCamera = UserDefaults.standard.bool(forKey: "useBackCamera")
                            print("Current camera position is: \(isBackCamera ? "back" : "front")")
                            
                            // Enable camera which will use the current preference
                            try await room.localParticipant.setCamera(enabled: true)
                            
                            // Also enable microphone
                            try await room.localParticipant.setMicrophone(enabled: true)
                        } catch {
                            print("Error enabling media: \(error)")
                        }
                    }
                }
            case .background, .inactive:
                // App went to background
                if let room = activeRoom {
                    Task {
                        do {
                            // Disable camera but keep microphone
                            try await room.localParticipant.setCamera(enabled: false)
                        } catch {
                            print("Error disabling camera: \(error)")
                        }
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    // 3. Add this helper method to connect the track to the view:
    private func connectLocalVideoTrackToView(_ videoTrack: VideoTrack) {
        print("🎥 Connecting local video track to view")
        
        // In SwiftUI we need to use UIApplication to find views
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            // Find the view controller that contains our video view
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            // Try to find the local preview view with tag 200
            if let previewView = topVC.view.viewWithTag(200) as? VideoView {
                // Remove any existing track
                if let currentTrack = previewView.track as? VideoTrack {
                    currentTrack.remove(videoRenderer: previewView)
                }
                
                // Set the new track
                previewView.track = videoTrack
                previewView.isEnabled = true
                
                print("🎥 Successfully connected track to view")
            } else {
                print("⚠️ Could not find local video view with tag 200")
            }
        }
    }
    
    // Add this function to LiveKitVideoCallView:
    private func sendMatchNotification(name: String) {
        let matchData = ["type": "match", "sender": userIdentifier, "name": firstName]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: matchData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Sending match notification")
                
                Task {
                    if let data = jsonString.data(using: .utf8) {
                        do {
                            try await activeRoom?.localParticipant.publish(data: data)
                            print("Match notification sent successfully")
                        } catch {
                            print("Failed to send match notification: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to serialize match notification: \(error.localizedDescription)")
        }
    }
    
    // Add this method to LiveKitVideoCallView
    private func checkForMatchNotifications() {
        let database = CKContainer.default().publicCloudDatabase
        
        // Look for match notifications where the current user is either user1 or user2
        let predicate = NSPredicate(format: "(user1 == %@ OR user2 == %@) AND processed == %@",
                                   userIdentifier, userIdentifier, false)
        let query = CKQuery(recordType: "MatchNotification", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error checking for match notifications: \(error.localizedDescription)")
                return
            }
            
            if let matchRecords = records, !matchRecords.isEmpty {
                DispatchQueue.main.async {
                    for matchRecord in matchRecords {
                        if let user1 = matchRecord["user1"] as? String,
                           let user2 = matchRecord["user2"] as? String {
                            
                            // Find the other user's ID
                            let otherUserId = (user1 == self.userIdentifier) ? user2 : user1
                            
                            // Get their name
                            self.fetchUserNameById(otherUserId) { userName in
                                if let name = userName {
                                    print("🎉 Received match notification with: \(name)")
                                    
                                    // Display the match notification
                                    withAnimation {
                                        self.showMatchMessage = true
                                    }
                                    self.playSound("match")
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        withAnimation {
                                            self.showMatchMessage = false
                                        }
                                    }
                                }
                                
                                // Mark notification as processed
                                matchRecord["processed"] = true
                                database.save(matchRecord) { _, _ in
                                    print("✅ Marked match notification as processed")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Helper method to fetch user name by ID
    private func fetchUserNameById(_ userId: String, completion: @escaping (String?) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first, let name = record["firstName"] as? String {
                completion(name)
            } else {
                completion(nil)
            }
        }
    }
    
    func unlikeUser() {
        // No need to unwrap matchedUserId since it's already a non-optional String
        print("💔 Starting unlike process for user ID: \(matchedUserId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // 1. First get the matched user's record to update like count
        let predicate = NSPredicate(format: "identifier == %@", matchedUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error finding matched user record: \(error.localizedDescription)")
                return
            }
            
            guard let userRecord = records?.first else {
                print("❌ Could not find matched user record")
                return
            }
            
            // Update the liked user's like count
            let likeCount = max(0, (userRecord["likeCount"] as? Int ?? 0) - 1)
            userRecord["likeCount"] = likeCount
            
            // Save the like count update in the database
            database.save(userRecord) { _, error in
                if let error = error {
                    print("❌ Unlike save error: \(error.localizedDescription)")
                } else {
                    print("✅ Like count saved successfully, new count: \(likeCount)")
                }
            }
        }
        
        // 2. Remove this like from the current user's record (who unliked)
        let myPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { myRecords, error in
            if let error = error {
                print("❌ Error finding current user record: \(error.localizedDescription)")
                return
            }
            
            guard let myRecord = myRecords?.first else {
                print("❌ Could not find current user record")
                return
            }
            
            // Remove from likedUsers array
            if var likedUsers = myRecord["likedUsers"] as? [String] {
                likedUsers.removeAll(where: { $0 == matchedUserId })
                myRecord["likedUsers"] = likedUsers
                print("➖ Removing \(matchedUserId) from likedUsers array")
                
                // Save the updated record
                database.save(myRecord) { _, likedError in
                    if let likedError = likedError {
                        print("❌ Error saving likedUsers: \(likedError.localizedDescription)")
                    } else {
                        print("✅ Successfully updated likedUsers array")
                        
                        // Check if there was a match that now needs to be removed
                        self.removeMatchIfExists(myRecord: myRecord, otherUserId: matchedUserId)
                    }
                }
            } else {
                print("⚠️ No likedUsers array found, nothing to unlike")
            }
        }
    }
    
    private func removeMatchIfExists(myRecord: CKRecord, otherUserId: String) {
        print("🔍 Checking if match needs to be removed with user: \(otherUserId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // First check if we have a match with this user
        if var myMatches = myRecord["matches"] as? [String], myMatches.contains(otherUserId) {
            // Remove the match from my record
            myMatches.removeAll(where: { $0 == otherUserId })
            myRecord["matches"] = myMatches
            
            database.save(myRecord) { _, error in
                if let error = error {
                    print("❌ Error removing match from my record: \(error.localizedDescription)")
                } else {
                    print("✅ Successfully removed match from my record")
                }
            }
            
            // Now update the other user's record too
            let otherUserPredicate = NSPredicate(format: "identifier == %@", otherUserId)
            let otherUserQuery = CKQuery(recordType: "UserProfile", predicate: otherUserPredicate)
            
            database.perform(otherUserQuery, inZoneWith: nil) { otherRecords, error in
                if let error = error {
                    print("❌ Error finding other user's record: \(error.localizedDescription)")
                    return
                }
                
                guard let otherRecord = otherRecords?.first else {
                    print("❌ Could not find other user's record")
                    return
                }
                
                // Remove match from other user's record too
                if var otherMatches = otherRecord["matches"] as? [String] {
                    otherMatches.removeAll(where: { $0 == self.userIdentifier })
                    otherRecord["matches"] = otherMatches
                    
                    database.save(otherRecord) { _, error in
                        if let error = error {
                            print("❌ Error removing match from other user's record: \(error.localizedDescription)")
                        } else {
                            print("✅ Successfully removed match from other user's record")
                        }
                    }
                }
            }
        } else {
            print("ℹ️ No match exists to remove")
        }
    }
    
    private func loadUserStateOfMind() {
        // First try to load from UserDefaults as a quick initialization
        let cachedStateOfMind = UserDefaults.standard.string(forKey: "userStateOfMind_\(userIdentifier)")
        if let cachedStateOfMind = cachedStateOfMind, !cachedStateOfMind.isEmpty {
            self.stateOfMind = cachedStateOfMind
            print("Loaded state of mind from cache: \(cachedStateOfMind)")
        }
        
        // Then fetch from CloudKit to get the latest
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                DispatchQueue.main.async {
                    if let stateOfMind = userRecord["stateOfMind"] as? String, !stateOfMind.isEmpty {
                        print("Loading state of mind from CloudKit: \(stateOfMind)")
                        self.stateOfMind = stateOfMind
                        
                        // Update the cache
                        UserDefaults.standard.set(stateOfMind, forKey: "userStateOfMind_\(self.userIdentifier)")
                    }
                }
            } else if let error = error {
                print("Error fetching state of mind: \(error.localizedDescription)")
            } else {
                print("No user record found for state of mind")
            }
        }
    }

    func checkCloudKitAvailability() {
        CKContainer.default().accountStatus { status, error in
            switch status {
            case .available:
                print("✅ iCloud account available for chat")
            case .restricted:
                print("⚠️ iCloud account restricted")
 //               self.showChatError("iCloud access is restricted")
            case .noAccount:
                print("⚠️ No iCloud account")
 //               self.showChatError("Please sign in to iCloud in Settings")
            case .couldNotDetermine:
                print("⚠️ iCloud status unknown")
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            @unknown default:
                print("⚠️ Unknown iCloud account status")
            }
        }
    }

    func findInsertionIndex(for message: ChatMessage) -> Int {
        // If empty array, insert at beginning
        guard !chatMessages.isEmpty else { return 0 }
        
        // Find position to insert based on timestamp (newest at end)
        return chatMessages.firstIndex(where: { $0.timestamp > message.timestamp }) ?? chatMessages.count
    }
    
    func formatDistance() -> String {
        // Since we don't have direct access to locationManager,
        // use the location from the matchedUser's record
        if let otherUserLoc = matchedUserLocation {
            // Try to get a fixed distance value from CloudKit
            if let distanceInMiles = matchedUserDistanceMiles {
                return String(format: "%.1f", distanceInMiles)
            }
            
            // Fallback to a placeholder
            return "nearby"
        }
        return "?"
    }

    func acceptPrivateMode() {
        // Send acceptance message
        let privateData = ["type": "private_request", "sender": userIdentifier, "name": firstName, "action": "accept"]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: privateData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Task {
                    if let data = jsonString.data(using: .utf8) {
                        do {
                            try await activeRoom?.localParticipant.publish(data: data)
                            print("Private mode request accepted")
                        } catch {
                            print("Failed to send private mode acceptance: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to serialize private mode acceptance: \(error.localizedDescription)")
        }
        
        // If other user already accepted, enable private mode
        if otherUserAcceptedPrivate {
 //           enablePrivateMode()
        }
    }
    
    // In saveProfileChanges method:
    func saveProfileChanges(
        newStateOfMind: String,
        religion: String,
        showJobTitle: Bool,
        showSchool: Bool,
        showReligion: Bool,
        showHometown: Bool,
        gender: String,
        jobTitle: String = "",
        school: String = "",
        hometown: String = ""
    ) {
        // Update local state
        self.stateOfMind = newStateOfMind
        self.religion = religion
        self.showJobTitle = showJobTitle
        self.showSchool = showSchool
        self.showReligion = showReligion
        self.showHometown = showHometown
        
        // Update CloudKit - your own profile
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier) // Your identifier
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error querying profile: \(error.localizedDescription)")
                return
            }
            
            guard let record = records?.first else {
                print("No profile record found")
                return
            }
            
            // Update the record with new values
            record["stateOfMind"] = newStateOfMind
            record["religion"] = religion
            record["showJobTitle"] = showJobTitle ? 1 : 0
            record["jobTitle"] = jobTitle
            record["showSchool"] = showSchool ? 1 : 0
            record["school"] = school
            record["showReligion"] = showReligion ? 1 : 0
            record["showHometown"] = showHometown ? 1 : 0
            record["hometown"] = hometown
            record["gender"] = gender
            
            // Save the updated record
            database.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving profile changes: \(error.localizedDescription)")
                } else {
                    print("✅ Profile updated successfully")
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        // Notify that profile was updated to update UI elements
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UserProfileUpdated"),
                            object: nil,
                            userInfo: [
                                "stateOfMind": newStateOfMind,
                                "religion": religion,
                                "showJobTitle": showJobTitle,
                                "jobTitle": jobTitle,
                                "showSchool": showSchool,
                                "school": school,
                                "showReligion": showReligion,
                                "showHometown": showHometown,
                                "hometown": hometown,
                                "gender": gender
                            ]
                        )
                    }
                }
            }
        }
    }
    
     
    private func checkExistingLike(forUserId userId: String) {
        print("🔍 Checking if user \(userId) was previously liked by \(userIdentifier)")
        let database = CKContainer.default().publicCloudDatabase
        let myPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { myRecords, error in
            if let error = error {
                print("🔍 Error checking for existing like: \(error.localizedDescription)")
                return
            }
            
            if let myRecord = myRecords?.first {
                if let likedUsers = myRecord["likedUsers"] as? [String] {
                    let hasLiked = likedUsers.contains(userId)
                    print("🔍 Found likedUsers array with \(likedUsers.count) entries. User liked: \(hasLiked)")
                    
                    DispatchQueue.main.async {
                        self.hasLiked = hasLiked
                        print("🔴 Setting hasLiked = \(hasLiked) for user \(userId)")
                    }
                } else {
                    print("🔍 No likedUsers array found in record")
                    
                    // Initialize the array if it doesn't exist
                    myRecord["likedUsers"] = [String]()
                    database.save(myRecord) { _, _ in
                        print("🔍 Created empty likedUsers array")
                    }
                }
                
                // Also check if there's already a match
                if let matches = myRecord["matches"] as? [String], matches.contains(userId) {
                    print("🔍 This user is already a match!")
                } else if myRecord["matches"] == nil {
                    // Initialize matches array if it doesn't exist
                    myRecord["matches"] = [String]()
                    database.save(myRecord) { _, _ in
                        print("🔍 Created empty matches array")
                    }
                }
            } else {
                print("🔍 Couldn't find user record for \(self.userIdentifier)")
            }
        }
    }

    // 2. Complete replacement for fetchProfileData function
    private func fetchProfileData(userId: String) {
        print("Fetching profile data for user: \(userId)")
        
        // Check if current user has already liked this user
        checkExistingLike(forUserId: userId)
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching profile: \(error.localizedDescription)")
                return
            }
            
            guard let record = records?.first else {
                print("Could not find profile for user: \(userId)")
                return
            }

            DispatchQueue.main.async {
                // Get matched user's state of mind
                if let stateOfMindValue = record["stateOfMind"] as? String {
                    self.matchedUserStateOfMind = stateOfMindValue
                    print("Loaded matched user's state of mind: \(stateOfMindValue)")
                } else {
                    self.matchedUserStateOfMind = "No state of mind set"
                    print("No state of mind found for matched user")
                }
                
                // Get matched user's gender
                if let gender = record["gender"] as? String {
                    self.matchedUserGender = gender
                }
                
                // Get social media handles
                self.matchedUserInstagramHandle = record["instagramHandle"] as? String
                self.matchedUserTwitterHandle = record["twitterHandle"] as? String
                
                // Load profile image if available
                if let imageAsset = record["profileImage"] as? CKAsset,
                   let imageUrl = imageAsset.fileURL,
                   FileManager.default.fileExists(atPath: imageUrl.path) {
                    
                    do {
                        let imageData = try Data(contentsOf: imageUrl)
                        if let image = UIImage(data: imageData) {
                            self.profileImage = image
                            print("✅ Profile image loaded from fetchProfileData")
                        }
                    } catch {
                        print("Error loading profile image: \(error)")
                    }
                }
                
                // Job title
                self.matchedUserShowJobTitle = record["showJobTitle"] as? Int == 1
                if self.matchedUserShowJobTitle {
                    self.matchedUserJobTitle = record["jobTitle"] as? String ?? ""
                }
                
                // School
                self.matchedUserShowSchool = record["showSchool"] as? Int == 1
                if self.matchedUserShowSchool {
                    self.matchedUserSchool = record["school"] as? String ?? ""
                }
                
                // Religion
                self.matchedUserShowReligion = record["showReligion"] as? Int == 1
                if self.matchedUserShowReligion {
                    self.matchedUserReligion = record["religion"] as? String ?? ""
                }
                
                // Hometown
                self.matchedUserShowHometown = record["showHometown"] as? Int == 1
                if self.matchedUserShowHometown {
                    self.matchedUserHometown = record["hometown"] as? String ?? ""
                }
                
                // Log the retrieved data for debugging
                print("Profile data loaded for \(userId):")
                print("- Show job title: \(self.matchedUserShowJobTitle), value: \(self.matchedUserJobTitle)")
                print("- Show school: \(self.matchedUserShowSchool), value: \(self.matchedUserSchool)")
                print("- Show religion: \(self.matchedUserShowReligion), value: \(self.matchedUserReligion)")
                print("- Show hometown: \(self.matchedUserShowHometown), value: \(self.matchedUserHometown)")
                print("- Instagram: \(self.matchedUserInstagramHandle ?? "not set")")
                print("- Twitter: \(self.matchedUserTwitterHandle ?? "not set")")
            }
        }
    }


    // Function to fetch user videos
    // In fetchUserVideos function
    // 3. Complete replacement for fetchUserVideos function
    private func fetchUserVideos(userId: String) {
        print("Fetching videos for user ID: \(userId)")
        let database = CKContainer.default().publicCloudDatabase
        
        let predicate = NSPredicate(format: "owner == %@", userId)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching videos: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.matchedUserVideos = []
                }
                return
            }
            
            if let videoRecords = records, !videoRecords.isEmpty {
                print("Found \(videoRecords.count) videos for user ID: \(userId)")
                
                var loadedVideos: [(id: UUID, title: String, url: URL?, views: Int)] = []
                let group = DispatchGroup()
                
                for record in videoRecords {
                    group.enter()
                    
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    
                    if let videoAsset = record["videoFile"] as? CKAsset, let assetURL = videoAsset.fileURL {
                        // Create a unique copy with timestamp to prevent conflicts
                        let uniqueFilename = "\(Date().timeIntervalSince1970)-\(videoIdString).mp4"
                        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename)
                        
                        do {
                            // Check if asset file exists
                            if FileManager.default.fileExists(atPath: assetURL.path) {
                                // Remove any existing file with same name
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    try FileManager.default.removeItem(at: localURL)
                                }
                                
                                // Copy the file
                                try FileManager.default.copyItem(at: assetURL, to: localURL)
                                
                                print("✅ Video copied successfully: \(title) to \(localURL.path)")
                                
                                // Verify the file was copied correctly
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                                    if let size = attributes[.size] as? NSNumber {
                                        print("File size: \(size.intValue) bytes")
                                        
                                        // Only add if file size is reasonable
                                        if size.intValue > 100 { // At least 100 bytes
                                            loadedVideos.append((id: videoId, title: title, url: localURL, views: views))
                                        } else {
                                            print("⚠️ File appears to be empty or corrupt")
                                        }
                                    }
                                } else {
                                    print("⚠️ File copy failed - cannot find at destination")
                                }
                            } else {
                                print("⚠️ Source video file doesn't exist at \(assetURL.path)")
                            }
                        } catch {
                            print("❌ Error copying video file: \(error.localizedDescription)")
                        }
                    } else {
                        print("⚠️ No video asset in record")
                    }
                    
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    self.matchedUserVideos = loadedVideos
                    print("✅ Updated matchedUserVideos with \(loadedVideos.count) videos")
                }
            } else {
                print("No videos found for user ID: \(userId)")
                DispatchQueue.main.async {
                    self.matchedUserVideos = []
                }
            }
        }
    }

    // Function to play a user's video
    func playUserVideo(url: URL, videoId: UUID) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Video file doesn't exist at path: \(url.path)")
            return
        }
        
        // Create a player and controller
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        // Find the top window and root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            // Find the current top-most presented controller
            var topController = window.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            
            // Dismiss any existing presentation first
            if topController?.presentedViewController != nil {
                topController?.dismiss(animated: false) {
                    // Then present our player
                    topController?.present(playerViewController, animated: true) {
                        player.play()
                    }
                }
            } else {
                // No active presentation, we can present directly
                topController?.present(playerViewController, animated: true) {
                    player.play()
                }
            }
        }
    }
    
    // Like notification handling
    // In your receivedLikeFrom function in LiveKitVideoCallView
    func receivedLikeFrom(userName: String) {
        // Set flag that the other user has liked us
        otherUserHasLiked = true
        print("⚠️ RECEIVED LIKE FROM: \(userName)")
        
        // Show liked message
        withAnimation {
            showLikedByMessage = true
        }
        
        // Play notification sound
        playSound("received_like")
        
        // Hide message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                self.showLikedByMessage = false
                
                // Check if we've both liked each other
                if self.hasLiked && self.otherUserHasLiked {
                    print("⚠️ MUTUAL LIKE DETECTED! SHOWING CONFIRMATION")
                    // Show match dialog
                    self.showPrivateConfirmation = true
                    
                    // Play match sound
                    self.playSound("match")
                }
            }
        }
    }

    func sendLikeNotification() {
        let likeData = ["type": "like", "sender": userIdentifier, "name": firstName]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: likeData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Sending like notification: \(jsonString)")
                
                Task {
                    if let data = jsonString.data(using: .utf8) {
                        do {
                            try await activeRoom?.localParticipant.publish(data: data)
                            print("Like notification sent successfully")
                        } catch {
                            print("Failed to send like notification: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to serialize like notification: \(error.localizedDescription)")
        }
    }

    // Match notification handling
    func matchedWith(userName: String) {
        withAnimation {
            showMatchMessage = true
        }
        
        // Play match sound
        playSound("match")
        
        // Hide message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showMatchMessage = false
            }
        }
    }

    // In LiveKitVideoCallView, replace the profileOverlayView() function with this:
    private func profileOverlayView() -> some View {
        VideoLoadingProfileView(
            userDetails: UnifiedProfileDetails(
                id: matchedUserId,
                name: matchedUserName,
                image: profileImage,
                gender: matchedUserGender,
                stateOfMind: matchedUserStateOfMind,
                religion: matchedUserReligion,
                showReligion: matchedUserShowReligion,
                jobTitle: matchedUserJobTitle,
                showJobTitle: matchedUserShowJobTitle,
                school: matchedUserSchool,
                showSchool: matchedUserShowSchool,
                hometown: matchedUserHometown,
                showHometown: matchedUserShowHometown,
                instagramHandle: matchedUserInstagramHandle ?? "",
                twitterHandle: matchedUserTwitterHandle ?? "",
                likeCount: userLikes,
                distanceMiles: matchedUserDistanceMiles,
                videos: [] // Start with empty videos
            ),
            userId: matchedUserId,
            onClose: {
                hideProfile()
            },
            loadVideos: loadVideosForProfileView
        )
    }
    
    private func loadVideosForProfileView(userId: String, completion: @escaping ([(id: UUID, title: String, url: URL?, views: Int)]) -> Void) {
        print("🎬 Explicitly loading videos for user profile: \(userId)")
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "owner == %@", userId)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error loading videos: \(error.localizedDescription)")
                completion([])
                return
            }
            
            var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
            
            if let videoRecords = records, !videoRecords.isEmpty {
                print("✅ Found \(videoRecords.count) videos for user \(userId)")
                
                for record in videoRecords {
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    
                    if let videoAsset = record["videoFile"] as? CKAsset, let assetURL = videoAsset.fileURL {
                        // Create a unique file in the temp directory
                        if FileManager.default.fileExists(atPath: assetURL.path) {
                            print("✅ Found video at asset URL: \(assetURL.path)")
                            videos.append((id: videoId, title: title, url: assetURL, views: views))
                        }
                    }
                }
            } else {
                print("No videos found for user \(userId)")
            }
            
            completion(videos)
        }
    }
    
    private func showProfile() {
        // Just set the state flag - no other actions that could affect the connection
        withAnimation {
            showProfileOverlay = true
        }
    }

    private func hideProfile() {
        // Just set the state flag - no other actions that could affect the connection
        withAnimation {
            showProfileOverlay = false
        }
    }

    // Add this function to load the profile image
    private func loadProfileImage() {
        // Use matchedUserId which is already available
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", matchedUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first,
               let imageAsset = record["profileImage"] as? CKAsset,
               let imageUrl = imageAsset.fileURL,
               FileManager.default.fileExists(atPath: imageUrl.path) {
                
                do {
                    let imageData = try Data(contentsOf: imageUrl)
                    if let image = UIImage(data: imageData) {
                        DispatchQueue.main.async {
                            self.profileImage = image
                            print("✅ Profile image loaded for user")
                        }
                    }
                } catch {
                    print("Error loading profile image: \(error)")
                }
            }
        }
    }
    
    private func fetchMyProfile() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                DispatchQueue.main.async {
                    // Update your state of mind from your profile record
                    if let myStateOfMind = userRecord["stateOfMind"] as? String {
                        self.stateOfMind = myStateOfMind
                    }
                    print("Loaded your state of mind: \(self.stateOfMind)")
                }
            }
        }
    }
    
    // Helper method to play sound effects
    func playSound(_ soundName: String) {
        // Implemented with actual sound files
        print("Playing sound: \(soundName)")
    }
    
    // CloudKit functions
    private func fetchUserLikes() {
        // Fetch the user's actual like count from CloudKit
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", matchedUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let record):
                if let likes = record["likeCount"] as? Int {
                    DispatchQueue.main.async {
                        self.userLikes = likes
                    }
                }
                
                // Get location and calculate distance
                if let location = record["location"] as? CLLocation {
                    DispatchQueue.main.async {
                        self.matchedUserLocation = location
                        
                        // Request current user's record to get their location
                        self.fetchCurrentUserLocation(otherUserLocation: location)
                    }
                }
                
                // Other fields...
            case .failure(let error):
                print("Error fetching likes: \(error.localizedDescription)")
            }
        }
        
        database.add(operation)
    }

    private func fetchCurrentUserLocation(otherUserLocation: CLLocation) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first, let myLocation = record["location"] as? CLLocation {
                let distanceInMeters = myLocation.distance(from: otherUserLocation)
                let distanceInMiles = distanceInMeters / 1609.34 // Convert meters to miles
                
                DispatchQueue.main.async {
                    self.matchedUserDistanceMiles = distanceInMiles
                }
            }
        }
    }
        
        private func reportUser() {
            // Find user in CloudKit and increment report count
            let database = CKContainer.default().publicCloudDatabase
            let predicate = NSPredicate(format: "identifier == %@", matchedUserId)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            
            let operation = CKQueryOperation(query: query)
            operation.recordMatchedBlock = { (recordID, result) in
                switch result {
                case .success(let record):
                    let currentCount = record["reportCount"] as? Int ?? 0
                    record["reportCount"] = currentCount + 1
                    
                    database.save(record) { _, error in
                        if let error = error {
                            print("Report save error: \(error.localizedDescription)")
                        } else {
                            print("User reported successfully")
                        }
                    }
                case .failure(let error):
                    print("Record fetch error for report: \(error.localizedDescription)")
                }
            }
            
            database.add(operation)
        }
        
        // Fix local preview
    // Replace the existing fixLocalPreview method with this
    // THIRD - Fix the fixLocalPreview method in LiveKitVideoCallView

    // In LiveKitVideoCallView:
    func fixLocalPreview() {
        VideoDebugger.shared.log("Using LiveKit approach for local preview")
        
        guard let room = activeRoom else {
            VideoDebugger.shared.log("No active room available")
            return
        }
        
        // Get all local video tracks
        let localTracks = room.localParticipant.trackPublications.values
        
        if let videoPublication = localTracks.first(where: { $0.kind == .video }),
           let videoTrack = videoPublication.track as? VideoTrack {
            
            VideoDebugger.shared.log("Found local video track, manually connecting it to UI")
            
            // Force the UI to update by posting a notification with the track ID
            NotificationCenter.default.post(
                name: NSNotification.Name("ConnectLocalVideoTrack"),
                object: nil,
                userInfo: [
                    "trackId": videoPublication.sid.stringValue,
                    "firstName": firstName,
                    "stateOfMind": stateOfMind
                ]
            )
            
            // Also directly update the local video view if we can find it
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                
                if let previewView = topVC.view.viewWithTag(200) as? VideoView {
                    // Remove any existing track first
                    if let currentTrack = previewView.track as? VideoTrack {
                        currentTrack.remove(videoRenderer: previewView)
                    }
                    
                    // Set the new track and ensure view is enabled
                    previewView.track = videoTrack
                    previewView.isEnabled = true
                    previewView.setNeedsLayout()
                    
                    VideoDebugger.shared.log("Directly updated local preview view")
                }
            }
        } else {
            VideoDebugger.shared.log("No local video track found")
        }
    }
        
    // Updated connectToRoom function - for LiveKitVideoCallView
    private func connectToRoom() {
        // Reset any existing connections first
        if let existingRoom = activeRoom, existingRoom.connectionState != .disconnected {
            Task {
                print("Disconnecting existing room before reconnection attempt")
                await existingRoom.disconnect()
                
                DispatchQueue.main.async {
                    self.activeRoom = nil
                    self.continueConnectToRoom()
                }
            }
        } else {
            continueConnectToRoom()
        }
    }

    private func continueConnectToRoom() {
        // Increment connection attempts
        connectionAttempts += 1
        VideoDebugger.shared.log("Starting connection attempt \(connectionAttempts) of \(maxConnectionAttempts)")
        
        // Check if we've exceeded max attempts
        if connectionAttempts > maxConnectionAttempts {
            errorMessage = "Failed to connect after \(maxConnectionAttempts) attempts"
            return
        }
        
        // Create a fresh SignalingClient for this connection
        let signalingClient = SignalingClient(userId: userIdentifier)
        
        VideoDebugger.shared.log("Current room state: \(signalingClient.room.connectionState)")
        
        signalingClient.connectToLiveKit { success in
            VideoDebugger.shared.log("Connection attempt result: \(success)")
            
            if success {
                VideoDebugger.shared.log("LiveKit connection successful, setting up video")
                
                // ⭐⭐⭐ CRITICAL CHANGE: Create a standalone delegate with no dependencies
  //              let dataDelegate = ChatDataDelegate()
                
                // Add to room explicitly
  //              signalingClient.room.add(delegate: dataDelegate)
  //              print("✅ Added standalone ChatDataDelegate explicitly for handling messages")
                
  //              // Store as property to prevent deallocation
  //              self.delegateHolder.delegate = dataDelegate
                
                // Update our state-managed room reference
                self.activeRoom = signalingClient.room
                self.isConnected = true
                
                // Create ActiveSession record for this room
                if let room = self.activeRoom {
                    print("Creating ActiveSession for the room")
                    signalingClient.createActiveSession(
                        roomId: room.name ?? "unknown-room",
                        participant1: self.userIdentifier,
                        participant2: self.matchedUserId
                    )
                }
                
                // Wait a bit before enabling media to ensure connection is stable
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.enableMediaForRoom(signalingClient.room)
                }
                
//                // Announce join
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
//                    self.announceJoin()
//                }
            } else {
                if self.connectionAttempts < self.maxConnectionAttempts {
                    // Try again after delay
                    VideoDebugger.shared.log("Scheduling retry in 2 seconds")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.connectToRoom()
                    }
                } else {
                    self.errorMessage = "Failed to connect to video service"
                }
            }
        }
    }
        
    // Modified enableMediaForRoom function in LiveKitVideoCallView
    private func enableMediaForRoom(_ room: Room) {
        VideoDebugger.shared.log("Enabling media for participant in room (state: \(room.connectionState))")
        
        Task {
            do {
                // Check camera permissions
                let authorized = await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        VideoDebugger.shared.log("Camera permission check result: \(granted)")
                        continuation.resume(returning: granted)
                    }
                }
                
                guard authorized else {
                    VideoDebugger.shared.log("Camera permission denied")
                    throw NSError(domain: "com.buzzaboo", code: 403)
                }
                
                // IMPORTANT: Get the actual position from UserDefaults
                let useBackCamera = UserDefaults.standard.bool(forKey: "useBackCamera")
                let cameraPosition: AVCaptureDevice.Position = useBackCamera ? .back : .front
                
                VideoDebugger.shared.log("Creating camera track with \(cameraPosition == .back ? "back" : "front") camera")
                let cameraOptions = CameraCaptureOptions(position: cameraPosition)
                
                // Add debugging to check original camera orientation
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) {
                    print("DEBUG: Camera interface orientation: \(UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.rawValue ?? 0)")
                    print("DEBUG: Camera device orientation: \(UIDevice.current.orientation.rawValue)")
                }
                
                let videoTrack = LocalVideoTrack.createCameraTrack(options: cameraOptions)
                VideoDebugger.shared.log("Local camera track created successfully")
                
                // Log video dimensions
                if let dimensions = videoTrack.dimensions {
                    print("DEBUG: Local video track dimensions: \(dimensions.width)x\(dimensions.height)")
                } else {
                    print("DEBUG: Local track has no dimensions")
                }
                
                // Try to adjust the video track before publishing
                print("DEBUG: Attempting to force video track to fit full face")
                
                // Make sure controller exists and update UI first
                if let controller = activeRoom?.localParticipant as? SafeVideoViewController {
                    controller.safeUpdateLocalVideo(videoTrack)
                    VideoDebugger.shared.log("Updated UI with local track before publishing")
                }
                
                // Then publish track with a short delay to ensure view setup is complete
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Log dimensions again before publishing
                if let dimensions = videoTrack.dimensions {
                    print("DEBUG: Video dimensions right before publishing: \(dimensions.width)x\(dimensions.height)")
                }
                
                try await room.localParticipant.publish(videoTrack: videoTrack)
                VideoDebugger.shared.log("Published local video track successfully")
                
                // Try to update the view again after publish
                if let controller = activeRoom?.localParticipant as? SafeVideoViewController {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        VideoDebugger.shared.log("Refreshing local video view after publishing")
                        controller.safeUpdateLocalVideo(videoTrack)
                    }
                }
                
                // Set up audio if possible, but don't crash if it fails
                do {
                    try await setupAudioIfPossible(for: room)
                } catch {
                    VideoDebugger.shared.log("Audio setup failed, continuing without audio: \(error)")
                }
                
                // After everything is set up, try a different approach to fix the preview
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Add extra debugging here
                    print("DEBUG: Fixing local preview with extra logging")
                    self.fixLocalPreview()
                    VideoDebugger.shared.log("Final attempt to fix local preview after everything is set up")
                }
                
            } catch {
                VideoDebugger.shared.log("Media setup error: \(error.localizedDescription)")
            }
        }
    }

    private func setupAudioIfPossible(for room: Room) async throws {
        do {
            VideoDebugger.shared.log("Setting up audio session...")
            
            // Configure the audio session with minimal options
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use a very basic configuration to avoid AVAudioEngine issues
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Add a significant delay before trying to enable the microphone
            // This gives the audio system time to fully initialize
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            // Use a try-catch block specifically for the microphone setup
            do {
                VideoDebugger.shared.log("Enabling microphone")
                // Use setMicrophone instead of directly publishing an audio track
                try await room.localParticipant.setMicrophone(enabled: true)
                VideoDebugger.shared.log("Microphone enabled")
            } catch {
                VideoDebugger.shared.log("⚠️ Could not enable microphone: \(error.localizedDescription)")
                // Just log the error but don't rethrow - continue without microphone
            }
        } catch {
            VideoDebugger.shared.log("⚠️ Audio session setup failed: \(error)")
            // Log but don't rethrow to prevent app crash
        }
    }
        

    }

                

struct LiveKitVideoUIView: UIViewRepresentable {
    let room: Room
    let parentView: LiveKitVideoCallView

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight] // Ensure it resizes properly
        
        // Create top half for remote video
        let remoteContainer = UIView(frame: CGRect(x: 0, y: 0, width: container.bounds.width, height: container.bounds.height/2))
        remoteContainer.backgroundColor = .black
        remoteContainer.tag = 100 // For finding later
        container.addSubview(remoteContainer)
        
        // Create button container for like and report at bottom of remote video
        let buttonContainer = UIView()
        buttonContainer.tag = 500
        buttonContainer.backgroundColor = .clear
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        remoteContainer.addSubview(buttonContainer)

        // Set up constraints
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: remoteContainer.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: remoteContainer.trailingAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 80),
            buttonContainer.bottomAnchor.constraint(equalTo: remoteContainer.bottomAnchor, constant: -10)
        ])
        
        // Create bottom half for local video
        let localContainer = UIView(frame: CGRect(x: 0, y: container.bounds.height/2, width: container.bounds.width, height: container.bounds.height/2))
        localContainer.backgroundColor = .darkGray
        localContainer.tag = 200 // For finding later
        container.addSubview(localContainer)
        
        // Set autoresizing to fill parent view
        remoteContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        buttonContainer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        localContainer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleHeight]
        
        // Set up delegates and listeners
        context.coordinator.setupRoomDelegate(room: room)
        
        // Start a timer to check for video tracks
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            context.coordinator.checkForVideoTracks(in: container)
        }
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.checkForVideoTracks(in: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        print("Making coordinator for \(room.name ?? "unknown room")")
        return Coordinator(room: room, parentView: parentView)
    }
    
    class Coordinator: NSObject, RoomDelegate {
        let room: Room
        let parentView: LiveKitVideoCallView
        var remoteVideoView: VideoView?
        var localVideoView: VideoView?
        
        init(room: Room, parentView: LiveKitVideoCallView) {
            self.room = room
            self.parentView = parentView
            super.init()
            
            // Remove any existing delegates first
            room.remove(delegate: self)
            
            // Add ourselves as a delegate
            room.add(delegate: self)
            print("✅ Room delegate explicitly set in Coordinator for data messages")
        }
        
        func updateLocalNameAndState(name: String, state: String) {
            // Use NotificationCenter to broadcast this update
            // This will let any interested components know about the change
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateNameAndState"),
                object: nil,
                userInfo: [
                    "name": name,
                    "state": state
                ]
            )
            
            // Always post the notification regardless of active room
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Post a notification specifically for the SafeVideoViewController to handle
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateLocalVideoLabels"),
                    object: nil,
                    userInfo: [
                        "name": name,
                        "state": state
                    ]
                )
            }
        }
        
        func setupRoomDelegate(room: Room) {
            room.add(delegate: self)
        }
        
        @objc func toggleStateOfMindExpansion(_ gesture: UITapGestureRecognizer) {
            print("State of mind label tapped!")
            
            // Get the state label directly from the gesture
            if let stateLabel = gesture.view as? UILabel {
                // Get the container view
                guard let nameView = stateLabel.superview, nameView.tag == 776 else {
                    return
                }
                
                // Find the name label by tag
                guard let nameLabel = nameView.viewWithTag(777) as? UILabel else {
                    return
                }
                
                // Toggle between condensed and expanded
                if stateLabel.numberOfLines == 2 {
                    print("Expanding state of mind to show all lines")
                    
                    // 1. Make label show all lines
                    stateLabel.numberOfLines = 0
                    
                    // 2. Calculate new height based on content
                    let newSize = stateLabel.sizeThatFits(CGSize(width: stateLabel.frame.width, height: CGFloat.greatestFiniteMagnitude))
                    
                    // 3. Resize the container to accommodate expanded text
                    var containerFrame = nameView.frame
                    containerFrame.size.height = nameLabel.frame.maxY + newSize.height + 10 // Add some padding
                    nameView.frame = containerFrame
                    
                    // 4. Resize the label itself
                    var labelFrame = stateLabel.frame
                    labelFrame.size.height = newSize.height
                    stateLabel.frame = labelFrame
                } else {
                    print("Collapsing state of mind to 2 lines")
                    
                    // 1. Set back to 2 lines
                    stateLabel.numberOfLines = 2
                    
                    // 2. Reset container to original size
                    var containerFrame = nameView.frame
                    containerFrame.size.height = 70 // Original height
                    nameView.frame = containerFrame
                    
                    // 3. Reset label to original size
                    stateLabel.frame = CGRect(x: 40, y: 23, width: 200, height: 25)
                }
            }
        }
        
        // In LiveKitVideoUIView.Coordinator class, modify the checkForVideoTracks method:

        func checkForVideoTracks(in container: UIView) {
            // Check for remote video tracks first with more robust detection
            if remoteVideoView == nil || remoteVideoView?.track == nil {
    //            print("Actively looking for remote tracks to display...")
                
                for participant in room.remoteParticipants.values {
                    for publication in participant.trackPublications.values {
                        if publication.kind == .video,
                           let videoTrack = publication.track as? VideoTrack,
                           let remoteContainer = container.viewWithTag(100) {
                            print("✅ Found remote video track to display - creating view")
                            createRemoteVideoView(in: remoteContainer, with: videoTrack)
                            break
                        }
                    }
                }
            }
            
            // Check for local video track as before
            if localVideoView == nil {
                for publication in room.localParticipant.trackPublications.values {
                    if publication.kind == .video,
                       let videoTrack = publication.track as? VideoTrack,
                       let localContainer = container.viewWithTag(200) {
                        createLocalVideoView(in: localContainer, with: videoTrack)
                        break
                    }
                }
            }
        }
        
        @objc func openMyProfile() {
            // Post a notification that the SwiftUI view can listen for
            NotificationCenter.default.post(name: NSNotification.Name("OpenMyProfileEditor"), object: nil)
        }
        
        // In the LiveKitVideoUIView.Coordinator class, modify the createLocalVideoView method:

        // In LiveKitVideoUIView.Coordinator class, modify the createLocalVideoView method:

        private func createLocalVideoView(in container: UIView, with videoTrack: VideoTrack) {
            // Remove any existing video views
            for subview in container.subviews {
                if subview is VideoView {
                    subview.removeFromSuperview()
                }
            }
            
            // Create new video view
            let videoView = VideoView(frame: container.bounds)
            videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            videoView.backgroundColor = .black
            videoView.layoutMode = .fill
            
            // Flip horizontally for selfie mode
            videoView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            
            // Add to container
            container.addSubview(videoView)
            
            // Set track
            videoView.track = videoTrack
            videoView.isEnabled = true
            
            // Save reference
            localVideoView = videoView
            
            // Add name and profile container to local video
            let nameView = UIView(frame: CGRect(x: 20, y: 20, width: 200, height: 70))
            nameView.tag = 776 // Specific tag for the name container
            
            // Make the name clickable
            nameView.isUserInteractionEnabled = true
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(openMyProfile))
            nameView.addGestureRecognizer(tapGesture)
            
            // Add profile image view
            let profileImageView = UIImageView(frame: CGRect(x: 0, y: 10, width: 30, height: 30))
            profileImageView.layer.cornerRadius = 15
            profileImageView.clipsToBounds = true
            profileImageView.contentMode = .scaleAspectFill
            profileImageView.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
            profileImageView.tag = 779 // Tag for finding the image view later
            
            // Load the current user's profile image
            loadCurrentUserProfileImage(imageView: profileImageView)
            
            // In createLocalVideoView:
            let nameLabel = UILabel(frame: CGRect(x: 40, y: 3, width: 200, height: 25)) // Moved right to make room for image
            nameLabel.text = self.parentView.firstName // Simple fallback name
            nameLabel.tag = 777 // Tag for finding later
            nameLabel.textColor = .white
            nameLabel.font = UIFont.boldSystemFont(ofSize: 16)

            // State of mind label - update these properties
            let stateLabel = UILabel(frame: CGRect(x: 40, y: 23, width: 200, height: 25))
            stateLabel.text = self.parentView.stateOfMind.isEmpty ? "" : "\"\(self.parentView.stateOfMind)\""
            stateLabel.tag = 778 // Tag for finding the state label later
            stateLabel.textColor = .white
            stateLabel.font = UIFont.systemFont(ofSize: 12)
            stateLabel.numberOfLines = 2

            // Make the state label a separate interactive element
            stateLabel.isUserInteractionEnabled = true

            // Create a separate tap gesture for the state label
            let stateTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleStateOfMindExpansion))
            stateTapGesture.cancelsTouchesInView = false // Allow tap to pass through
            stateLabel.addGestureRecognizer(stateTapGesture)
            
            nameView.addSubview(profileImageView)
            nameView.addSubview(nameLabel)
            nameView.addSubview(stateLabel)
            container.addSubview(nameView)
            
            print("Local video view created with name and profile image overlay")
        }

        // Add this helper method to load your profile image
        private func loadCurrentUserProfileImage(imageView: UIImageView) {
            let database = CKContainer.default().publicCloudDatabase
            let predicate = NSPredicate(format: "identifier == %@", parentView.userIdentifier)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            
            database.perform(query, inZoneWith: nil) { records, error in
                if let record = records?.first,
                   let imageAsset = record["profileImage"] as? CKAsset,
                   let imageUrl = imageAsset.fileURL,
                   FileManager.default.fileExists(atPath: imageUrl.path) {
                    
                    do {
                        let imageData = try Data(contentsOf: imageUrl)
                        if let image = UIImage(data: imageData) {
                            DispatchQueue.main.async {
                                imageView.image = image
                            }
                        }
                    } catch {
                        print("Error loading current user profile image: \(error)")
                        // Fallback to initials if image loading fails
                        DispatchQueue.main.async {
                            let label = UILabel(frame: imageView.bounds)
                            label.text = self.parentView.firstName.prefix(1).uppercased()
                            label.textAlignment = .center
                            label.textColor = .white
                            label.font = UIFont.boldSystemFont(ofSize: 14)
                            imageView.addSubview(label)
                        }
                    }
                } else {
                    // Fallback to initials if no image is found
                    DispatchQueue.main.async {
                        let label = UILabel(frame: imageView.bounds)
                        label.text = self.parentView.firstName.prefix(1).uppercased()
                        label.textAlignment = .center
                        label.textColor = .white
                        label.font = UIFont.boldSystemFont(ofSize: 14)
                        imageView.addSubview(label)
                    }
                }
            }
        }
        
        // In LiveKitVideoUIView.Coordinator class, add this to the createRemoteVideoView method
        // In LiveKitVideoUIView.Coordinator
        private func createRemoteVideoView(in container: UIView, with videoTrack: VideoTrack) {
            print("Creating remote video view with dynamic position for track: \(videoTrack)")
            
            // Remove any existing video views
            for subview in container.subviews {
                if subview is VideoView {
                    subview.removeFromSuperview()
                }
            }
            
            // Create new video view - use Auto Layout instead of frame-based layout
            let videoView = VideoView()
            videoView.translatesAutoresizingMaskIntoConstraints = false
            videoView.backgroundColor = .black
            videoView.layoutMode = .fill  // Using fill to ensure content is visible
            
            // Add to container first without any transforms
            container.addSubview(videoView)
            container.clipsToBounds = true
            
            // Set up Auto Layout constraints
            NSLayoutConstraint.activate([
                videoView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                videoView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                videoView.widthAnchor.constraint(equalTo: container.widthAnchor),
                videoView.heightAnchor.constraint(equalTo: container.heightAnchor)
            ])
            
            // Force layout immediately
            container.layoutIfNeeded()
            
            // Now check device order
            let isSecondDevice = room.remoteParticipants.count > 0 &&
                                 room.localParticipant.joinedAt != nil &&
                                 room.remoteParticipants.values.first?.joinedAt != nil &&
                                 (room.localParticipant.joinedAt ?? Date()) > (room.remoteParticipants.values.first?.joinedAt ?? Date())
            
            // Apply vertical offset based on connection order
            let verticalOffset = container.bounds.height * (isSecondDevice ? 0.20 : 0.25)
            print("Device connection order: \(isSecondDevice ? "SECOND" : "FIRST"), applying offset: \(verticalOffset)")
            
            // Use longer delay to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // First make sure any existing track is removed
                if let currentTrack = videoView.track as? VideoTrack {
                    currentTrack.remove(videoRenderer: videoView)
                }
                
                // Set up track
                videoView.track = videoTrack
                videoView.isEnabled = true
                self.remoteVideoView = videoView
                
                // After track is set, apply transform with animation
                UIView.animate(withDuration: 0.3) {
                    videoView.transform = CGAffineTransform(translationX: 0, y: -verticalOffset)
                }
                
                print("✅ Remote video track attached with vertical offset: \(verticalOffset)")
            }
        }
        
        // Room delegate methods
        func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication, track: Track) {
            if track.kind == .video, let videoTrack = track as? VideoTrack {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let container = self.remoteVideoView?.superview else { return }
                    self.createRemoteVideoView(in: container, with: videoTrack)
                }
            }
        }
        
        func room(_ room: Room, didConnect participant: RemoteParticipant) {
            print("Remote participant connected")
        }
        
        func room(_ room: Room, didFailToConnectWithError error: Error) {
            print("Failed to connect to room: \(error)")
        }
        
        func room(_ room: Room, didDisconnectWithError error: Error?) {
            print("Room disconnected")
        }
    }
}

class CallRequestObserver {
    static let shared = CallRequestObserver()
    private var timer: Timer?
    private var lastCheckTime = Date()
    private var processedRequestIds = Set<String>()
    
    func startObserving(for userId: String) {
        // Cancel any existing timer
        timer?.invalidate()
        
        // Create a new timer that checks every 5 seconds instead of 10
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkForCallRequests(userId: userId)
        }
        
        // Do an initial check immediately
        checkForCallRequests(userId: userId)
    }
    
    func stopObserving() {
        timer?.invalidate()
        timer = nil
    }
    
    func checkForCallRequests(userId: String) {
        print("Checking for call requests to \(userId)")
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Filter for only RECENT pending requests (within last 5 minutes)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let predicate = NSPredicate(format: "receiverId == %@ AND status == %@ AND timestamp > %@",
                                   userId, "pending", fiveMinutesAgo as NSDate)
        let query = CKQuery(recordType: "CallRequest", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching call requests: \(error.localizedDescription)")
                return
            }
            
            if let records = records, !records.isEmpty {
                print("Found \(records.count) pending call requests")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let request = records.first,
                       let senderId = request["senderId"] as? String,
                       let senderName = request["senderName"] as? String,
                       !self.processedRequestIds.contains(request.recordID.recordName) {
                        
                        let requestId = request.recordID.recordName
                        
                        print("Found call request from \(senderName)")
                        
                        // Add to processed set immediately to prevent duplicates
                        self.processedRequestIds.insert(requestId)
                        
                        // Mark request as processing to prevent duplicates
                        request["status"] = "processing"
                        database.save(request) { _, _ in }
                        
                        // Post notification for MainView to handle
                        NotificationCenter.default.post(
                            name: NSNotification.Name("IncomingCallRequest"),
                            object: nil,
                            userInfo: [
                                "senderId": senderId,
                                "senderName": senderName,
                                "requestId": requestId
                            ]
                        )
                        
                        // Allow re-processing this request after 60 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                            self?.processedRequestIds.remove(requestId)
                        }
                    }
                }
            }
        }
    }
}

class CustomRemoteVideoView: UIView {
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var videoTrack: VideoTrack?
    var videoView: VideoView?
    
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDisplayLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDisplayLayer()
    }
    
    private func setupDisplayLayer() {
        displayLayer = layer as? AVSampleBufferDisplayLayer
        displayLayer?.videoGravity = .resizeAspectFill
        displayLayer?.backgroundColor = UIColor.black.cgColor
    }
    
    // Connect to a LiveKit video track
    func connectToTrack(_ track: VideoTrack) -> Bool {
        // Create a standard VideoView to actually handle the track
        let hiddenView = VideoView(frame: bounds)
        hiddenView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hiddenView.backgroundColor = .clear
        hiddenView.layoutMode = .fill
        hiddenView.track = track
        hiddenView.isEnabled = true
        
        // Add it as a subview
        addSubview(hiddenView)
        videoView = hiddenView
        
        return true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
        videoView?.frame = bounds
    }
}

// Modified SafeVideoViewController class
class SafeVideoViewController: UIViewController {
    let room: Room
    var remoteVideoView: VideoView?
    var localVideoView: VideoView?
    private var remoteVideoContainer: UIView!
    private var localVideoContainer: UIView!
    private var roomDelegate: SafeRoomDelegate?
    private var statusLabel: UILabel?
    private var debugTimer: Timer?
    
    init(room: Room) {
        self.room = room
        super.init(nibName: nil, bundle: nil)
        VideoDebugger.shared.log("SafeVideoViewController initialized with room state: \(room.connectionState)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupRoomDelegate()
        
        // Listen for local video track notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectLocalVideoTrack),
            name: NSNotification.Name("ConnectLocalVideoTrack"),
            object: nil
        )
        
        // Add this new observer for updating labels
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLabels),
            name: NSNotification.Name("UpdateLocalVideoLabels"),
            object: nil
        )
        
        // Add periodic debug checks
        debugTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.performDebugChecks()
        }
    }

    // Add this new method
    @objc func updateLabels(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let name = userInfo["name"] as? String,
              let state = userInfo["state"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let container = self.view.viewWithTag(776) {
                if let nameLabel = container.viewWithTag(777) as? UILabel {
                    nameLabel.text = name
                }
                
                if let stateLabel = container.viewWithTag(778) as? UILabel {
                    stateLabel.text = state.isEmpty ? "" : "\"\(state)\""
                }
            }
        }
    }
    
    @objc func connectLocalVideoTrack(_ notification: Notification) {
        if let trackId = notification.userInfo?["trackId"] as? String {
            VideoDebugger.shared.log("Received notification to connect local track: \(trackId)")
            
            // Find track by ID
            for publication in room.localParticipant.trackPublications.values {
                if publication.sid.stringValue == trackId && publication.kind == .video,
                   let videoTrack = publication.track as? VideoTrack {
                    safeUpdateLocalVideo(videoTrack)
                    return
                }
            }
        }
    }
    
    deinit {
        debugTimer?.invalidate()
        debugTimer = nil
    }
    
    func directAttachLocalVideoTrack() {
        VideoDebugger.shared.log("Directly attaching local video track")
        
        // Get all local video tracks
        let localTracks = room.localParticipant.trackPublications.values
        
        if let videoPublication = localTracks.first(where: { $0.kind == .video }),
           let videoTrack = videoPublication.track as? VideoTrack {
            
            VideoDebugger.shared.log("Found LOCAL video track to attach: \(videoPublication.sid.stringValue)")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Clear existing views
                for view in self.localVideoContainer.subviews {
                    if view is VideoView {
                        view.removeFromSuperview()
                    }
                }
                
                // Create simple VideoView with frame-based layout (avoid Auto Layout issues)
                let videoView = VideoView(frame: self.localVideoContainer.bounds)
                videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                videoView.layoutMode = .fill
                videoView.backgroundColor = .gray
                
                // Mirror the view
                videoView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                
                // Add the view first, then set track after a delay
                self.localVideoContainer.insertSubview(videoView, at: 0)
                
                // First make LiveKit aware of the view
                videoView.layoutIfNeeded()
                
                // Then set the track after rendering view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoView.track = videoTrack
                    videoView.isEnabled = true
                    
                    self.localVideoView = videoView
                    self.statusLabel?.text = "Local video attached to view"
                    
                    VideoDebugger.shared.log("LOCAL video track directly attached to view")
                    VideoDebugger.shared.log("View frame: \(videoView.frame), VideoView enabled: \(videoView.isEnabled)")
                }
            }
        } else {
            VideoDebugger.shared.log("⚠️ No local video track found to attach")
        }
    }
    
    func modifySetupUI() {
        // Find safeUpdateLocalVideo method in LiveKitVideoCallView
        let videoTrack = room.localParticipant.trackPublications.values.first { $0.kind == .video }?.track as? VideoTrack
        
        if videoTrack != nil {
            print("Found video track to add")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.safeUpdateLocalVideo(videoTrack)
        }
    }

    // Call this right after setupUI() in viewDidLoad
    
    private func performDebugChecks() {
        // Check room connection status
        VideoDebugger.shared.log("Room connection state: \(room.connectionState)")
        
        // Check local participant's tracks
        let localTracks = room.localParticipant.trackPublications.values
        VideoDebugger.shared.log("Local tracks count: \(localTracks.count)")
        for pub in localTracks {
            VideoDebugger.shared.log("Local track: kind=\(pub.kind), name=\(pub.name), sid=\(pub.sid.stringValue), track=\(pub.track != nil ? "available" : "nil")")
            
            if pub.kind == .video, let track = pub.track as? VideoTrack {
                _ = VideoDebugger.shared.checkVideoTrack(track)
            }
        }
        
        // Check remote participants and their tracks
        VideoDebugger.shared.log("Remote participants count: \(room.remoteParticipants.count)")
        for (_, participant) in room.remoteParticipants {
            VideoDebugger.shared.log("Remote participant: \(participant.identity?.stringValue ?? "unknown")")
            
            let remoteTracks = participant.trackPublications.values
            VideoDebugger.shared.log("  - Remote tracks count: \(remoteTracks.count)")
            
            for pub in remoteTracks {
                VideoDebugger.shared.log("  - Remote track: kind=\(pub.kind), name=\(pub.name), sid=\(pub.sid.stringValue), track=\(pub.track != nil ? "subscribed" : "not subscribed")")
                
                if pub.kind == .video, let track = pub.track as? VideoTrack {
                    _ = VideoDebugger.shared.checkVideoTrack(track)
                    
                    if let view = remoteVideoView {
                        _ = VideoDebugger.shared.checkVideoView(view)
                        
                        // Check if this track is actually assigned to the view
                        let trackMatches = view.track === track
                        VideoDebugger.shared.log("Remote track matches view track: \(trackMatches)")
                    }
                }
            }
        }
    }
    
    // FIRST - Fix the SafeVideoViewController setupUI method to use Auto Layout

    private func setupUI() {
        view.backgroundColor = .black
        
        // Main container for remote video (top half)
        remoteVideoContainer = UIView()
        remoteVideoContainer.backgroundColor = .black
        remoteVideoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remoteVideoContainer)
        
        // Container for local video (bottom half)
        localVideoContainer = UIView()
        localVideoContainer.backgroundColor = .darkGray
        localVideoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(localVideoContainer)
        
        // Set up constraints for the containers
        NSLayoutConstraint.activate([
            // Remote container takes top half
            remoteVideoContainer.topAnchor.constraint(equalTo: view.topAnchor),
            remoteVideoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remoteVideoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remoteVideoContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
            
            // Local container takes bottom half
            localVideoContainer.topAnchor.constraint(equalTo: remoteVideoContainer.bottomAnchor),
            localVideoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            localVideoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            localVideoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Add a label to clearly identify the local preview
        let localLabel = UILabel()
        localLabel.text = "You"
        localLabel.textColor = .white
        localLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        localLabel.layer.cornerRadius = 5
        localLabel.layer.masksToBounds = true
        localLabel.textAlignment = .center
        localLabel.translatesAutoresizingMaskIntoConstraints = false
        localVideoContainer.addSubview(localLabel)
        
        NSLayoutConstraint.activate([
            localLabel.topAnchor.constraint(equalTo: localVideoContainer.topAnchor, constant: 10),
            localLabel.leadingAnchor.constraint(equalTo: localVideoContainer.leadingAnchor, constant: 10),
            localLabel.widthAnchor.constraint(equalToConstant: 100),
            localLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Add a status label for debugging
        statusLabel = UILabel()
        statusLabel?.textColor = .white
        statusLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        statusLabel?.text = "Waiting for LiveKit..."
        statusLabel?.font = UIFont.systemFont(ofSize: 12)
        statusLabel?.translatesAutoresizingMaskIntoConstraints = false
        localVideoContainer.addSubview(statusLabel!)
        
        NSLayoutConstraint.activate([
            statusLabel!.topAnchor.constraint(equalTo: localLabel.bottomAnchor, constant: 10),
            statusLabel!.leadingAnchor.constraint(equalTo: localVideoContainer.leadingAnchor, constant: 10),
            statusLabel!.trailingAnchor.constraint(lessThanOrEqualTo: localVideoContainer.trailingAnchor, constant: -10),
            statusLabel!.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        VideoDebugger.shared.log("UI setup complete with Auto Layout 50/50 split screen layout")
    }
    
    private func setupRoomDelegate() {
        roomDelegate = SafeRoomDelegate(viewController: self)
        room.add(delegate: roomDelegate!)
        setupExistingTracks()
    }
    
    private func setupExistingTracks() {
        // Check for existing remote tracks
        for participant in room.remoteParticipants.values {
            for publication in participant.trackPublications.values {
                if publication.kind == .video, let videoTrack = publication.track as? VideoTrack {
                    VideoDebugger.shared.log("Found existing remote video track from \(participant.identity?.stringValue ?? "unknown")")
                    safeUpdateRemoteVideo(videoTrack)
                }
            }
        }
        
        // Check for existing local tracks
        for publication in room.localParticipant.trackPublications.values {
            if publication.kind == .video, let videoTrack = publication.track as? VideoTrack {
                VideoDebugger.shared.log("Found existing local video track")
                safeUpdateLocalVideo(videoTrack)
            }
        }
    }
    
    // Updated method to use LiveKit's video track for local preview
    // Updated method to use LiveKit's video track for local preview with mirroring
    // SECOND - Fix the video view creation methods

    func safeUpdateLocalVideo(_ videoTrack: VideoTrack?) {
        VideoDebugger.shared.log("Updating local video preview with LiveKit track")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Remove any existing VideoView
            for subview in self.localVideoContainer.subviews {
                if subview is VideoView {
                    subview.removeFromSuperview()
                }
            }
            
            guard let videoTrack = videoTrack else {
                VideoDebugger.shared.log("No video track provided for local preview")
                self.statusLabel?.text = "No local video track available"
                return
            }
            
            // Create a new VideoView with Auto Layout
            let videoView = VideoView()
            videoView.translatesAutoresizingMaskIntoConstraints = false
            videoView.backgroundColor = .black
            videoView.layoutMode = .fill
            
            // Apply transform to mirror the view
            videoView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            
            // Add to hierarchy (at index 0 to be behind other elements)
            self.localVideoContainer.insertSubview(videoView, at: 0)
            
            // Set up constraints
            NSLayoutConstraint.activate([
                videoView.topAnchor.constraint(equalTo: self.localVideoContainer.topAnchor),
                videoView.leadingAnchor.constraint(equalTo: self.localVideoContainer.leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: self.localVideoContainer.trailingAnchor),
                videoView.bottomAnchor.constraint(equalTo: self.localVideoContainer.bottomAnchor)
            ])
            
            // Explicitly render the view before setting track
            videoView.layoutIfNeeded()
            
            // Set track and enable with debug info
            videoView.track = videoTrack
            videoView.isEnabled = true
            self.localVideoView = videoView
            
            // Force layout update after track assignment
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            
            // Update status with dimensions info
            if let dimensions = videoTrack.dimensions {
                self.statusLabel?.text = "Local video: \(dimensions.width)x\(dimensions.height)"
                VideoDebugger.shared.log("Local track dimensions: \(dimensions.width)x\(dimensions.height)")
            } else {
                self.statusLabel?.text = "Local video connected (no dimensions)"
                VideoDebugger.shared.log("Local video view created with LiveKit track (no dimensions)")
            }
            
            VideoDebugger.shared.log("Local video view frame: \(videoView.frame)")
        }
    }

    func safeUpdateRemoteVideo(_ videoTrack: VideoTrack) {
        VideoDebugger.shared.log("Setting up remote video track")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Remove existing VideoViews
            for subview in self.remoteVideoContainer.subviews {
                if subview is VideoView {
                    subview.removeFromSuperview()
                }
            }
            
            // Create a VideoView with Auto Layout
            let videoView = VideoView()
            videoView.translatesAutoresizingMaskIntoConstraints = false
            videoView.backgroundColor = .black
            videoView.layoutMode = .fill
            
            // Add to container
            self.remoteVideoContainer.addSubview(videoView)
            
            // Set constraints
            NSLayoutConstraint.activate([
                videoView.topAnchor.constraint(equalTo: self.remoteVideoContainer.topAnchor),
                videoView.leadingAnchor.constraint(equalTo: self.remoteVideoContainer.leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: self.remoteVideoContainer.trailingAnchor),
                videoView.bottomAnchor.constraint(equalTo: self.remoteVideoContainer.bottomAnchor)
            ])
            
            // Explicitly render the view before setting track
            videoView.layoutIfNeeded()
            
            // Set track and enable
            videoView.track = videoTrack
            videoView.isEnabled = true
            self.remoteVideoView = videoView
            
            // Force layout update after track assignment
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            
            // Log dimensions for debugging
            if let dimensions = videoTrack.dimensions {
                VideoDebugger.shared.log("Remote track dimensions: \(dimensions.width)x\(dimensions.height)")
            }
            
            VideoDebugger.shared.log("Remote video view created and enabled, frame: \(videoView.frame)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update VideoView frames when the view layout changes
        if let localView = localVideoView {
            localView.frame = localVideoContainer.bounds
        }
        
        if let remoteView = remoteVideoView {
            remoteView.frame = remoteVideoContainer.bounds
        }
    }
    
}

// In SafeRoomDelegate.swift

class SafeRoomDelegate: NSObject, RoomDelegate {
    weak var viewController: SafeVideoViewController?
    
    init(viewController: SafeVideoViewController) {
        self.viewController = viewController
        super.init()
        print("Room delegate initialized")
    }
    
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication, track: Track) {
        print("✅ didSubscribeTrack called for kind: \(track.kind)")
        VideoDebugger.shared.log("Track subscribed: \(publication.kind) from \(participant.identity?.stringValue ?? "unknown")")

        if track.kind == .video, let videoTrack = track as? VideoTrack {
            VideoDebugger.shared.log("Remote video track received, updating UI")
            DispatchQueue.main.async { [weak self] in
                self?.viewController?.safeUpdateRemoteVideo(videoTrack)
            }
        }
    }
    
    func room(_ room: Room, didConnect participant: RemoteParticipant) {
        print("Remote participant connected: \(participant.identity?.stringValue ?? "unknown")")
    }
    
    func room(_ room: Room, didFailToConnectWithError error: Error) {
        print("Failed to connect: \(error)")
    }
    
    func room(_ room: Room, didDisconnectWithError error: Error?) {
        print("Room disconnected: \(error?.localizedDescription ?? "normally")")
    }
}

struct VideoLoadingProfileView: View {
    var userDetails: UnifiedProfileDetails
    let userId: String
    let onClose: () -> Void
    let loadVideos: (String, @escaping ([(id: UUID, title: String, url: URL?, views: Int)]) -> Void) -> Void
    
    @State private var isLoadingVideos = true
    @State private var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
    
    var body: some View {
        ZStack {
            // The main profile view with current video data
            UnifiedProfileView(
                userDetails: UnifiedProfileDetails(
                    id: userDetails.id,
                    name: userDetails.name,
                    image: userDetails.image,
                    gender: userDetails.gender,
                    stateOfMind: userDetails.stateOfMind,
                    religion: userDetails.religion,
                    showReligion: userDetails.showReligion,
                    jobTitle: userDetails.jobTitle,
                    showJobTitle: userDetails.showJobTitle,
                    school: userDetails.school,
                    showSchool: userDetails.showSchool,
                    hometown: userDetails.hometown,
                    showHometown: userDetails.showHometown,
                    instagramHandle: userDetails.instagramHandle,
                    twitterHandle: userDetails.twitterHandle,
                    likeCount: userDetails.likeCount,
                    distanceMiles: userDetails.distanceMiles,
                    videos: videos // Use the dynamically loaded videos
                ),
                onClose: onClose
            )
            
            // Loading indicator for videos
            if isLoadingVideos {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Load videos when view appears
            loadVideos(userId) { loadedVideos in
                DispatchQueue.main.async {
                    self.videos = loadedVideos
                    self.isLoadingVideos = false
                    print("✅ Set \(loadedVideos.count) videos in profile view")
                }
            }
        }
    }
}

    // Fallback view with just local camera
struct LocalOnlyVideoView: View {
    let matchedUserName: String
    let onClose: () -> Void
    let onLike: () -> Void
    
    @State private var timer = 0
    @State private var hasLiked = false
    @State private var isLikeAnimating = false
    @State private var hasReported = false
    @State private var showReportConfirmation = false
    @State private var stateOfMind = ""
    @State private var showFullStateOfMind = false
    
    private let swipeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Local camera view
            LocalCameraView()
                .edgesIgnoringSafeArea(.all)
            
            // UI overlay
            VStack {
                HStack {
                    Text("\(matchedUserName) - Fallback Mode")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.top, 40)
                
                Spacer()
                
                // State of Mind section
                VStack(alignment: .leading, spacing: 8) {
                    Text("State of Mind")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.leading, 4)
                    
                    if showFullStateOfMind {
                        Text(stateOfMind)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                            .onTapGesture {
                                withAnimation {
                                    showFullStateOfMind = false
                                }
                            }
                    } else {
                        HStack {
                            Text(stateOfMind)
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(12)
                            
                            if stateOfMind.count > 50 {
                                Button(action: {
                                    withAnimation {
                                        showFullStateOfMind = true
                                    }
                                }) {
                                    Text("...more")
                                        .foregroundColor(.blue)
                                        .padding(8)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding()
            
            // Report confirmation dialog
            if showReportConfirmation {
                VStack(spacing: 16) {
                    Text("Report inappropriate behavior?")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("This will increase the user's report count and notify moderation.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            withAnimation {
                                showReportConfirmation = false
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Report User") {
                            // Handle report
                            hasReported = true
                            withAnimation {
                                showReportConfirmation = false
                            }
                        }
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(24)
                .background(Color.black.opacity(0.9))
                .cornerRadius(16)
                .shadow(radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
                .edgesIgnoringSafeArea(.all)
            }
        }
        .onReceive(swipeTimer) { _ in
            if timer < 10 { timer += 1 }
        }
    }
}

    struct LocalCameraView: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .black
            
            // Setup camera controller
            let cameraController = CameraViewController()
            
            // Add camera view to our container
            cameraController.view.frame = view.bounds
            cameraController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(cameraController.view)
            
            // Store controller in coordinator
            context.coordinator.controller = cameraController
            
            return view
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Nothing to update
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }
        
        class Coordinator {
            var controller: CameraViewController?
        }
    }

    class CameraViewController: UIViewController {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        
        override func viewDidLoad() {
            super.viewDidLoad()
            setupCamera()
        }
        
        private func setupCamera() {
            let captureSession = AVCaptureSession()
            
            // Check for device
            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("No front camera available")
                return
            }
            
            do {
                // Create input
                let input = try AVCaptureDeviceInput(device: frontCamera)
                
                // Add input to session
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                
                // Create preview layer
                let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = view.bounds
                
                // Add this line to mirror the camera preview
                  previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
                  previewLayer.connection?.isVideoMirrored = true
                
                view.layer.addSublayer(previewLayer)
                
                // Store references
                self.captureSession = captureSession
                self.previewLayer = previewLayer
                
                // Start capturing
                DispatchQueue.global(qos: .userInitiated).async {
                    captureSession.startRunning()
                }
                
            } catch {
                print("Camera setup error: \(error)")
            }
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }
        
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            captureSession?.stopRunning()
        }
    }

extension SafeVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Just monitoring frames - no action needed
        // This confirms the camera is actively producing frames
    }
}

// Simple component for state of mind display
struct StateOfMindView: View {
    let stateOfMind: String
    @Binding var showFullStateOfMind: Bool
    
    var body: some View {
        HStack { // Add this HStack wrapper
            if stateOfMind.count > 50 && !showFullStateOfMind {
                Text("\"\(stateOfMind.prefix(50))...\"")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1) // Limit to 1 line when collapsed
            } else if showFullStateOfMind {
                Text("\"\(stateOfMind)\"")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
            } else {
                Text("\"\(stateOfMind)\"")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer() // This forces left alignment
        } // Close the HStack
        .onTapGesture {
            withAnimation {
                showFullStateOfMind.toggle()
            }
        }
    }
}

// Simple component for chat input
struct ChatInputView: View {
    @Binding var chatMessage: String
    let onSend: () -> Void
    
    var body: some View {
        HStack {
            TextField("", text: $chatMessage) // Remove placeholder here
                .font(.appBody)
                .padding(.leading, 16) // Add explicit leading padding
                .padding(.vertical, 10)
                .padding(.trailing, 10)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(20)
                .foregroundColor(.white)
                .overlay(
                    // Custom placeholder with proper positioning
                    Group {
                        if chatMessage.isEmpty {
                            Text("Type a message...")
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.leading, 16) // Match the TextField padding
                        }
                    },
                    alignment: .leading
                )
            
            Button(action: {
                if !chatMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Use the CloudKit method
                    onSend()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
        .padding(.horizontal)
    }
}

struct ProfilePhotoSectionView: View {
    @Binding var profileImage: UIImage?
    @Binding var showingImagePicker: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            ZStack {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                        )
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 60))
                        )
                }
                
                Button(action: {
                    showingImagePicker = true
                }) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "pencil")
                                .foregroundColor(.white)
                                .font(.system(size: 18))
                        )
                        .shadow(radius: 3)
                }
                .offset(x: 40, y: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

struct SocialMediaSectionView: View {
    @Binding var instagramHandle: String
    @Binding var twitterHandle: String
    
    var body: some View {
        Group {
            HStack {
                Text("Instagram:")
                    .foregroundColor(.appForeground)
                TextField("@username", text: $instagramHandle)
                    .padding(8)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("X/Twitter:")
                    .foregroundColor(.appForeground)
                TextField("@username", text: $twitterHandle)
                    .padding(8)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
    }
}

struct MatchesSectionView: View {
    let matches: [MainViewUserMatch]
    let onTapMatch: (String) -> Void
    let onCallMatch: (String, String) -> Void
    let onUnmatch: (String, String) -> Void
    
    @State private var showUnmatchConfirm = false
    @State private var unmatchUserId = ""
    @State private var unmatchUserName = ""
    @State private var lastCallTime: [String: Date] = [:]
    @State private var showCallCooldownAlert = false
    @State private var cooldownUserName = ""
    @State private var likedMatches: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Matches")
                .font(.appHeadline)
                .foregroundColor(.appForeground)
            
            if matches.isEmpty {
                Text("No matches yet")
                    .font(.appCaption)
                    .foregroundColor(.appSecondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(matches) { match in
                            HStack {
                                // Profile image with online indicator
                                ZStack(alignment: .bottomTrailing) {
                                    if let image = match.profileImage {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Text(match.name.prefix(1))
                                                    .foregroundColor(.white)
                                            )
                                    }
                                    
                                    // Online indicator
                                    if match.isOnline {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.black, lineWidth: 1)
                                            )
                                    }
                                }
                                
                                // User name - tap to view profile
                                Button(action: {
                                    // Ensure no other UI is currently presented
                                    dismissAnyPresentedViews {
                                        onTapMatch(match.id)
                                    }
                                }) {
                                    Text(match.name)
                                        .font(.appBody)
                                        .foregroundColor(.appForeground)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                // LIVE indicator for online users
                                if match.isOnline {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("LIVE")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.red.opacity(0.7))
                                    )
                                }

                                // Video call button
                                if match.isOnline {
                                    Button(action: {
                                        dismissAnyPresentedViews {
                                            if canCallUser(userId: match.id) {
                                                onCallMatch(match.id, match.name)
                                            } else {
                                                cooldownUserName = match.name
                                                showCallCooldownAlert = true
                                            }
                                        }
                                    }) {
                                        Image(systemName: "video.fill")
                                            .foregroundColor(.red)
                                            .padding(4)
                                    }
                                    .disabled(!match.isOnline)
                                }

                                // Heart/Like button in the matches list
                                Button(action: {
                                    // Call the function to handle like/unlike
                                    likeOrUnlikeUser(userId: match.id, userName: match.name)
                                }) {
                                    Image(systemName: likedMatches.contains(match.id) ? "heart.fill" : "heart")
                                        .foregroundColor(likedMatches.contains(match.id) ? .red : .white)
                                        .padding(4)
                                }
                            }
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .alert(isPresented: $showUnmatchConfirm) {
            Alert(
                title: Text("Unmatch"),
                message: Text("Are you sure you want to unmatch with \(unmatchUserName)?"),
                primaryButton: .destructive(Text("Yes")) {
                    onUnmatch(unmatchUserId, unmatchUserName)
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Cannot Call Now", isPresented: $showCallCooldownAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only call \(cooldownUserName) again after 10 minutes from your last request.")
        }
        .onAppear {
            // Load initial like statuses when the view appears
            loadLikeStatuses()
        }
    }
    
    private func removeFromOtherUserMatches(currentUserId: String, otherUserId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", otherUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                var matches = record["matches"] as? [String] ?? []
                matches.removeAll(where: { $0 == currentUserId })
                record["matches"] = matches
                
                database.save(record) { _, error in
                    if let error = error {
                        print("❌ Error removing from other user's matches: \(error.localizedDescription)")
                    } else {
                        print("✅ Successfully removed from other user's matches")
                    }
                }
            } else if let error = error {
                print("❌ Error finding other user's record: \(error.localizedDescription)")
            } else {
                print("❌ Other user's record not found")
            }
        }
    }
    
    // Check if enough time has passed to call user again
    private func canCallUser(userId: String) -> Bool {
        if let lastTime = lastCallTime[userId] {
            let tenMinutesAgo = Date().addingTimeInterval(-600) // 10 minutes
            return lastTime < tenMinutesAgo
        }
        return true
    }
    
    // Update last call time for a user
    mutating func updateCallTime(for userId: String) {
        lastCallTime[userId] = Date()
    }
    
    func dismissAnyPresentedViews(completion: @escaping () -> Void) {
        // Find top controller and dismiss any presented views
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            // Now check if this top controller has anything presented
            if topVC.presentedViewController != nil {
                topVC.dismiss(animated: true) {
                    completion()
                }
            } else {
                completion()
            }
        } else {
            completion()
        }
    }
    
    // Load the user's liked statuses
    private func loadLikeStatuses() {
        guard let currentUserId = UserDefaults.standard.string(forKey: "userIdentifier") else { return }
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", currentUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first, let likedUsers = record["likedUsers"] as? [String] {
                DispatchQueue.main.async {
                    self.likedMatches = Set(likedUsers)
                    print("✅ Loaded liked status for \(likedUsers.count) users")
                }
            } else if let error = error {
                print("❌ Error loading like statuses: \(error.localizedDescription)")
            }
        }
    }
    
    // Function to handle liking/unliking a user
    private func likeOrUnlikeUser(userId: String, userName: String) {
        print("Toggle like status for \(userName)")
        
        // Get the current user ID from UserDefaults
        guard let currentUserId = UserDefaults.standard.string(forKey: "userIdentifier") else {
            print("❌ Cannot like user - userIdentifier not found in UserDefaults")
            return
        }
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Get the current user's record
        let myPredicate = NSPredicate(format: "identifier == %@", currentUserId)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error finding current user record: \(error.localizedDescription)")
                return
            }
            
            guard let myRecord = records?.first else {
                print("❌ Could not find current user record")
                return
            }
            
            // Determine current like status
            var likedUsers = myRecord["likedUsers"] as? [String] ?? []
            let hasLiked = likedUsers.contains(userId)
            
            if hasLiked {
                // Unlike: Remove from liked users
                likedUsers.removeAll(where: { $0 == userId })
                myRecord["likedUsers"] = likedUsers
                
                // Update the target user's like count
                decrementLikeCount(for: userId)
                
                print("✅ Unliked user \(userName)")
                
                // Update UI state immediately
                DispatchQueue.main.async {
                    var updatedLikedMatches = self.likedMatches
                    updatedLikedMatches.remove(userId)
                    self.likedMatches = updatedLikedMatches
                }
            } else {
                // Like: Add to liked users
                likedUsers.append(userId)
                myRecord["likedUsers"] = likedUsers
                
                // Update the target user's like count
                incrementLikeCount(for: userId)
                
                print("✅ Liked user \(userName)")
                
                // Update UI state immediately
                DispatchQueue.main.async {
                    var updatedLikedMatches = self.likedMatches
                    updatedLikedMatches.insert(userId)
                    self.likedMatches = updatedLikedMatches
                }
                
                // Check for potential match after liking
   //             checkForPossibleMatch(currentUserId: currentUserId, likedUserId: userId)
            }
            
            // Save the updated record
            database.save(myRecord) { _, error in
                if let error = error {
                    print("❌ Error saving like status: \(error.localizedDescription)")
                } else {
                    print("✅ Successfully updated like status")
                    
                    // Notify to reload matches
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ReloadMatchesNeeded"),
                            object: nil
                        )
                    }
                }
            }
        }
    }
    
    // Increment the like count for a user
    private func incrementLikeCount(for userId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                let currentLikes = record["likeCount"] as? Int ?? 0
                record["likeCount"] = currentLikes + 1
                
                database.save(record) { _, error in
                    if let error = error {
                        print("❌ Error incrementing like count: \(error.localizedDescription)")
                    } else {
                        print("✅ Successfully incremented like count")
                    }
                }
            }
        }
    }
    
    // Decrement the like count for a user
    private func decrementLikeCount(for userId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                let currentLikes = record["likeCount"] as? Int ?? 0
                record["likeCount"] = max(0, currentLikes - 1)
                
                database.save(record) { _, error in
                    if let error = error {
                        print("❌ Error decrementing like count: \(error.localizedDescription)")
                    } else {
                        print("✅ Successfully decremented like count")
                    }
                }
            }
        }
    }
}

// Ensure CallRequestManager initializes correctly
// Improved CallRequestManager
class CallRequestManager {
    static let shared = CallRequestManager()
    private var pendingRequests: [String: Date] = [:]
    private var cooldowns: [String: Date] = [:]
    
    // Check if user is in cooldown period
    func isInCooldown(userId: String) -> Bool {
        if let lastTime = cooldowns[userId] {
            let tenMinutesAgo = Date().addingTimeInterval(-600) // 10 minutes
            return lastTime > tenMinutesAgo
        }
        return false
    }
    
    func fetchCallRequests(forUser userId: String, completion: @escaping ([CKRecord]) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Query for pending requests for this user
        let predicate = NSPredicate(format: "receiverId == %@ AND status == %@", userId, "pending")
        let query = CKQuery(recordType: "CallRequest", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 10 // Increase limit to make sure we see all requests
        
        var foundRecords: [CKRecord] = []
        
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let record):
                foundRecords.append(record)
            case .failure(let error):
                print("Error fetching call request: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                print("Found \(foundRecords.count) pending call requests")
                completion(foundRecords)
            case .failure(let error):
                print("Error in query: \(error.localizedDescription)")
                completion([])
            }
        }
        
        database.add(operation)
    }
    
    // Send a call request
    // Update in CallRequestManager:
    func sendCallRequest(from senderId: String, to receiverId: String, senderName: String, completion: @escaping (Bool) -> Void = {_ in}) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Create new request record with additional fields to ensure it's properly indexed
        let record = CKRecord(recordType: "CallRequest")
        record["senderId"] = senderId
        record["senderName"] = senderName
        record["receiverId"] = receiverId
        record["status"] = "pending"
        record["timestamp"] = Date()
        record["requestId"] = UUID().uuidString // Add a unique ID
        
        print("📞 Sending call request from \(senderName) to user \(receiverId)")
        
        // Save to CloudKit with priority
        let saveOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        saveOperation.savePolicy = .allKeys
        saveOperation.qualityOfService = .userInitiated
        
        saveOperation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                print("✅ Call request sent successfully")
                completion(true)
                
                // Also post a local notification to trigger immediate UI updates
                NotificationCenter.default.post(
                    name: NSNotification.Name("CallRequestSent"),
                    object: nil,
                    userInfo: [
                        "senderId": senderId,
                        "receiverId": receiverId,
                        "senderName": senderName
                    ]
                )
            case .failure(let error):
                print("❌ Error saving call request: \(error.localizedDescription)")
                completion(false)
            }
        }
        
        database.add(saveOperation)
    }
    
    // Respond to call request
    func respondToCallRequest(requestId: String, accept: Bool, responseMessage: String = "") {
        print("Responding to call request: \(requestId), accept: \(accept)")
        
        let database = CKContainer.default().publicCloudDatabase
        let recordID = CKRecord.ID(recordName: requestId)
        
        database.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching call request: \(error.localizedDescription)")
                return
            }
            
            guard let record = record else {
                print("No call request found with ID: \(requestId)")
                return
            }
            
            // Update record with response
            record["status"] = accept ? "accepted" : "declined"
            record["responseMessage"] = responseMessage
            record["responseTime"] = Date()
            
            // Save with higher priority
            let saveOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            saveOperation.savePolicy = .changedKeys
            saveOperation.qualityOfService = .userInitiated
            
            saveOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("Successfully responded to call request: \(accept ? "accepted" : "declined")")
                    
                    // Post notification for accepted calls
                    if accept, let senderId = record["senderId"] as? String,
                            let senderName = record["senderName"] as? String {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("StartDirectCall"),
                                object: nil,
                                userInfo: [
                                    "userId": senderId,
                                    "name": senderName
                                ]
                            )
                        }
                    }
                case .failure(let error):
                    print("Error responding to call request: \(error.localizedDescription)")
                }
            }
            
            database.add(saveOperation)
        }
    }
}

// Improved UnifiedProfileView with working like button
// Improved UnifiedProfileView WITH ALL PROFILE DETAILS PRESERVED
struct UnifiedProfileView: View {
    let userDetails: UnifiedProfileDetails
    let onClose: () -> Void
    @State private var hasLiked = false
    @State private var likeCount: Int
    @State private var isLiking = false
    
    init(userDetails: UnifiedProfileDetails, onClose: @escaping () -> Void) {
        self.userDetails = userDetails
        self.onClose = onClose
        self._likeCount = State(initialValue: userDetails.likeCount)
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onClose()
                }
            
            // Profile content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with close button
                    HStack {
                        // Profile image
                        if let profileImage = userDetails.image {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 30))
                                )
                        }
                        
                        Text("\(userDetails.name)'s Profile")
                            .font(.appHeadline)
                            .fontWeight(.bold)
                            .foregroundColor(.appForeground)
                        
                        Spacer()
                        
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.appHeadline)
                                .foregroundColor(.appForeground)
                        }
                    }
                    
                    // Basic info
                    Group {
                        HStack {
                            Text("Gender: \(userDetails.gender)")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            if let distance = userDetails.distanceMiles {
                                Text("\(String(format: "%.1f", distance)) miles away")
                                    .font(.appBody)
                                    .foregroundColor(.appForeground)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.appCaption)
                            Text("\(likeCount) likes")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            
                            Spacer()
                            
                            // Like button
                            Button(action: {
                                if !isLiking {
                                    isLiking = true
                                    hasLiked.toggle()
                                    
                                    if hasLiked {
                                        likeCount += 1
                                        likeUser(userId: userDetails.id)
                                    } else {
                                        likeCount = max(0, likeCount - 1)
                                        unlikeUser(userId: userDetails.id)
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        isLiking = false
                                    }
                                }
                            }) {
                                Image(systemName: hasLiked ? "heart.fill" : "heart")
                                    .foregroundColor(hasLiked ? .red : .white)
                                    .font(.system(size: 22))
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            }
                            .disabled(isLiking)
                        }
                    }
                    
                    // Social Media section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Social Media")
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.appForeground)
                        
                        // Instagram
                        // Replace the Instagram section with:
                        HStack {
                            Image(systemName: "camera")
                                .foregroundColor(.pink)
                                .font(.appCaption)
                            Text("Instagram:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            if !userDetails.instagramHandle.isEmpty {
                                Button(action: {
                                    openInstagram(username: userDetails.instagramHandle)
                                }) {
                                    Text("@\(userDetails.instagramHandle)")
                                        .font(.appBody)
                                        .foregroundColor(.appAccent)
                                }
                            } else {
                                Text("Not set")
                                    .font(.appBody)
                                    .foregroundColor(.appSecondary)
                            }
                        }
                        .padding(.vertical, 4)

                        // Replace the Twitter section with:
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundColor(.blue)
                                .font(.appCaption)
                            Text("Twitter/X:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            if !userDetails.twitterHandle.isEmpty {
                                Button(action: {
                                    openTwitter(username: userDetails.twitterHandle)
                                }) {
                                    Text("@\(userDetails.twitterHandle)")
                                        .font(.appBody)
                                        .foregroundColor(.appAccent)
                                }
                            } else {
                                Text("Not set")
                                    .font(.appBody)
                                    .foregroundColor(.appSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    
                    // State of Mind
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current State of Mind")
                            .font(.appBody)
                            .foregroundColor(.appForeground)
                        
                        Text(userDetails.stateOfMind.isEmpty ? "Not set" : userDetails.stateOfMind)
                            .font(.appCaption)
                            .foregroundColor(.appForeground)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                    }
                    
                    // Job title (if showing)
                    if userDetails.showJobTitle && !userDetails.jobTitle.isEmpty {
                        HStack {
                            Text("Job Title:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            Text(userDetails.jobTitle)
                                .font(.appBody)
                                .foregroundColor(.appSecondary)
                        }
                    }
                    
                    // School (if showing)
                    if userDetails.showSchool && !userDetails.school.isEmpty {
                        HStack {
                            Text("School:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            Text(userDetails.school)
                                .font(.appBody)
                                .foregroundColor(.appSecondary)
                        }
                    }
                    
                    // Religion (if showing)
                    if userDetails.showReligion && !userDetails.religion.isEmpty {
                        HStack {
                            Text("Religious Beliefs:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            Text(userDetails.religion)
                                .font(.appBody)
                                .foregroundColor(.appSecondary)
                        }
                    }
                    
                    // Hometown (if showing)
                    if userDetails.showHometown && !userDetails.hometown.isEmpty {
                        HStack {
                            Text("Hometown:")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            Spacer()
                            Text(userDetails.hometown)
                                .font(.appBody)
                                .foregroundColor(.appSecondary)
                        }
                    }
                    
                    // Videos section
                    if !userDetails.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Videos")
                                .font(.appBody)
                                .foregroundColor(.appForeground)
                            
                            // Video thumbnails
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(userDetails.videos, id: \.id) { video in
                                        VStack(alignment: .leading) {
                                            if let url = video.url {
                                                ZStack {
                                                    // Use a Rectangle with AsyncImage for better performance
                                                    RectangleThumbnailView(videoURL: url)
                                                        .frame(width: 120, height: 160)
                                                        .cornerRadius(10)
                                                        .overlay(
                                                            Image(systemName: "play.fill")
                                                                .font(.system(size: 30))
                                                                .foregroundColor(.white.opacity(0.8))
                                                        )
                                                }
                                                .onTapGesture {
                                                    playVideo(url: url)
                                                }
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.5))
                                                    .frame(width: 120, height: 160)
                                                    .cornerRadius(10)
                                            }
                                            
                                            Text(video.title)
                                                .font(.appCaption)
                                                .foregroundColor(.appForeground)
                                            
                                            Text("\(video.views) views")
                                                .font(.appTiny)
                                                .foregroundColor(.appSecondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
                .padding()
            }
        }
        .onAppear {
            // Check if the current user has already liked this user
            checkIfUserLiked(userId: userDetails.id)
        }
    }
    
    // Add this more reliable video thumbnail view
    struct RectangleThumbnailView: View {
        let videoURL: URL
        @State private var thumbnailImage: UIImage? = nil
        @State private var isLoading = true
        
        var body: some View {
            ZStack {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .background(Color.black)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.6))
                        .overlay(
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "film")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        )
                }
            }
            .onAppear {
                generateThumbnail()
            }
        }
        
        private func generateThumbnail() {
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                print("❌ Video file not found: \(videoURL.path)")
                isLoading = false
                return
            }
            
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            // Fix the CMTime initializers with proper parameters
            let timePoints = [
                CMTime(value: 0, timescale: 1),
                CMTime(value: 1, timescale: 1)
            ]
            
            DispatchQueue.global().async {
                for time in timePoints {
                    do {
                        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                        let uiImage = UIImage(cgImage: cgImage)
                        
                        DispatchQueue.main.async {
                            self.thumbnailImage = uiImage
                            self.isLoading = false
                        }
                        return
                    } catch {
                        print("Failed to generate thumbnail at time \(time.seconds): \(error)")
                        // Continue to next time point
                    }
                }
                
                // If we get here, all time points failed
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func openInstagram(username: String) {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: "instagram://user?username=\(cleanUsername)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webURL = URL(string: "https://www.instagram.com/\(cleanUsername)") {
                UIApplication.shared.open(webURL)
            }
        }
    }

    private func openTwitter(username: String) {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: "twitter://user?screen_name=\(cleanUsername)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webURL = URL(string: "https://twitter.com/\(cleanUsername)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    // Additional helper functions for the UnifiedProfileView
    private func checkIfUserLiked(userId: String) {
        // Get the current user ID from UserDefaults
        guard let currentUserId = UserDefaults.standard.string(forKey: "userIdentifier") else {
            return
        }
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", currentUserId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let userRecord = records?.first, let likedUsers = userRecord["likedUsers"] as? [String] {
                // Check if target user ID is in the likedUsers array
                DispatchQueue.main.async {
                    self.hasLiked = likedUsers.contains(userId)
                }
            }
        }
    }
    
    private func likeUser(userId: String) {
        // Get the current user ID from UserDefaults
        guard let currentUserId = UserDefaults.standard.string(forKey: "userIdentifier") else {
            return
        }
        
        print("Liking user \(userId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // 1. Update target user's like count
        let targetPredicate = NSPredicate(format: "identifier == %@", userId)
        let targetQuery = CKQuery(recordType: "UserProfile", predicate: targetPredicate)
        
        database.perform(targetQuery, inZoneWith: nil) { records, error in
            if let targetRecord = records?.first {
                let currentLikes = targetRecord["likeCount"] as? Int ?? 0
                targetRecord["likeCount"] = currentLikes + 1
                
                database.save(targetRecord) { _, error in
                    if let error = error {
                        print("Error updating like count: \(error.localizedDescription)")
                    } else {
                        print("Successfully liked user \(userId)")
                    }
                }
            }
        }
        
        // 2. Update current user's liked list
        let myPredicate = NSPredicate(format: "identifier == %@", currentUserId)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { records, error in
            if let myRecord = records?.first {
                var likedUsers = myRecord["likedUsers"] as? [String] ?? []
                
                // Add to likedUsers array if not already present
                if !likedUsers.contains(userId) {
                    likedUsers.append(userId)
                    myRecord["likedUsers"] = likedUsers
                    
                    database.save(myRecord) { _, error in
                        if let error = error {
                            print("Error updating likedUsers: \(error.localizedDescription)")
                        } else {
                            print("Successfully added to likedUsers array")
                            
                            // Check for potential match
                            checkForMatch(myId: currentUserId, otherId: userId)
                        }
                    }
                }
            }
        }
    }
    
    private func unlikeUser(userId: String) {
        // Get the current user ID from UserDefaults
        guard let currentUserId = UserDefaults.standard.string(forKey: "userIdentifier") else {
            return
        }
        
        print("Unliking user \(userId)")
        let database = CKContainer.default().publicCloudDatabase
        
        // 1. Update target user's like count
        let targetPredicate = NSPredicate(format: "identifier == %@", userId)
        let targetQuery = CKQuery(recordType: "UserProfile", predicate: targetPredicate)
        
        database.perform(targetQuery, inZoneWith: nil) { records, error in
            if let targetRecord = records?.first {
                let currentLikes = targetRecord["likeCount"] as? Int ?? 0
                targetRecord["likeCount"] = max(0, currentLikes - 1)
                
                database.save(targetRecord) { _, error in
                    if let error = error {
                        print("Error updating like count: \(error.localizedDescription)")
                    } else {
                        print("Successfully unliked user \(userId)")
                    }
                }
            }
        }
        
        // 2. Update current user's liked list
        let myPredicate = NSPredicate(format: "identifier == %@", currentUserId)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { records, error in
            if let myRecord = records?.first {
                var likedUsers = myRecord["likedUsers"] as? [String] ?? []
                
                // Remove from likedUsers array if present
                likedUsers.removeAll(where: { $0 == userId })
                myRecord["likedUsers"] = likedUsers
                
                database.save(myRecord) { _, error in
                    if let error = error {
                        print("Error updating likedUsers: \(error.localizedDescription)")
                    } else {
                        print("Successfully removed from likedUsers array")
                    }
                }
            }
        }
    }
    
    private func checkForMatch(myId: String, otherId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let otherPredicate = NSPredicate(format: "identifier == %@", otherId)
        let otherQuery = CKQuery(recordType: "UserProfile", predicate: otherPredicate)
        
        database.perform(otherQuery, inZoneWith: nil) { records, error in
            if let otherRecord = records?.first, let likedUsers = otherRecord["likedUsers"] as? [String] {
                // Check if the other user has liked us back
                if likedUsers.contains(myId) {
                    print("Match found! Both users liked each other.")
                    
                    // Update matches arrays for both users
                    self.addMatchToBothUsers(myId: myId, otherId: otherId)
                }
            }
        }
    }
    
    private func addMatchToBothUsers(myId: String, otherId: String) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Update my matches
        let myPredicate = NSPredicate(format: "identifier == %@", myId)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { records, error in
            if let myRecord = records?.first {
                var matches = myRecord["matches"] as? [String] ?? []
                
                if !matches.contains(otherId) {
                    matches.append(otherId)
                    myRecord["matches"] = matches
                    
                    database.save(myRecord) { _, _ in
                        print("Added match to my profile")
                    }
                }
            }
        }
        
        // Update other user's matches
        let otherPredicate = NSPredicate(format: "identifier == %@", otherId)
        let otherQuery = CKQuery(recordType: "UserProfile", predicate: otherPredicate)
        
        database.perform(otherQuery, inZoneWith: nil) { records, error in
            if let otherRecord = records?.first {
                var matches = otherRecord["matches"] as? [String] ?? []
                
                if !matches.contains(myId) {
                    matches.append(myId)
                    otherRecord["matches"] = matches
                    
                    database.save(otherRecord) { _, _ in
                        print("Added match to other user's profile")
                    }
                }
            }
        }
    }
    
    // In UnifiedProfileView, add a more robust video player function
    // In UnifiedProfileView's playVideo function:
    // In UnifiedProfileView, replace the playVideo function:
    private func playVideo(url: URL) {
        // Make sure we have a valid URL and file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Video file doesn't exist at path: \(url.path)")
            
            // Show an error to the user
            let alert = UIAlertController(
                title: "Video Unavailable",
                message: "The video file could not be found. It may have been deleted or moved.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Get the UIWindow scene to present the alert
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Find the top-most view controller to present from
                var topController = windowScene.windows.first?.rootViewController
                while let presentedController = topController?.presentedViewController {
                    topController = presentedController
                }
                
                // Present the alert
                topController?.present(alert, animated: true)
            }
            return
        }
        
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        // Get the UIWindow scene properly
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Find the top-most view controller to present from
            var topController = windowScene.windows.first?.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            
            // Dismiss any current presentation first if needed
            if topController?.presentedViewController != nil {
                topController?.dismiss(animated: false) {
                    topController?.present(playerViewController, animated: true) {
                        player.play()
                    }
                }
            } else {
                topController?.present(playerViewController, animated: true) {
                    player.play()
                }
            }
        }
    }

    private func showPlaybackErrorAlert(message: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            let alert = UIAlertController(
                title: "Video Playback Error",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            topVC.present(alert, animated: true)
        }
    }
}

struct VideosSectionView: View {
    let videos: [(id: UUID, title: String, url: URL?, views: Int)]
    let onTapVideo: (URL) -> Void
    let onDeleteVideo: (UUID) -> Void
    let onAddVideo: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Videos")
                    .font(.appBody)
                    .foregroundColor(.appForeground)
                
                Spacer()
                
                Button(action: onAddVideo) {
                    Text("+ Add Video")
                        .font(.appCaption)
                        .foregroundColor(.appAccent)
                }
            }
            
            if videos.isEmpty {
                Text("No videos added yet")
                    .font(.appCaption)
                    .foregroundColor(.appSecondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(videos, id: \.id) { video in
                            VStack(alignment: .leading) {
                                ZStack(alignment: .topTrailing) {
                                    if let url = video.url {
                                        VideoThumbnailView(videoURL: url)
                                            .frame(width: 120, height: 160)
                                            .cornerRadius(10)
                                            .overlay(
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 30))
                                                    .foregroundColor(.white.opacity(0.8))
                                            )
                                            .onTapGesture {
                                                onTapVideo(url)
                                            }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.5))
                                            .frame(width: 120, height: 160)
                                            .cornerRadius(10)
                                    }
                                    
                                    Button {
                                        onDeleteVideo(video.id)
                                    } label: {
                                        Image(systemName: "trash.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.red)
                                            .background(Circle().fill(Color.black).frame(width: 34, height: 34))
                                            .padding(8)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .frame(width: 50, height: 50)
                                }
                                
                                Text(video.title)
                                    .font(.appCaption)
                                    .foregroundColor(.appForeground)
                                
                                Text("\(video.views) views")
                                    .font(.appTiny)
                                    .foregroundColor(.appSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

// UPDATED ProfileEditorView
struct ProfileEditorView: View {
    let firstName: String
    let userIdentifier: String
    @Binding var stateOfMind: String
    let onSave: (String, String, Bool, Bool, Bool, Bool, String, String, String, String) -> Void
    let onCancel: () -> Void
    
    // User profile data
    @State private var isAuthenticatingTwitter = false
    @State private var twitterAuthSession: ASWebAuthenticationSession?
    @State private var syncStateOfMindWithX = false
    @State private var isFetchingTweet = false
    @State private var lastSyncTime: Date?
    @State private var editedStateOfMind: String = ""
    @State private var religion: String = ""
    @State private var showJobTitle = false
    @State private var jobTitle: String = ""
    @State private var showSchool = false
    @State private var school: String = ""
    @State private var showReligion = false
    @State private var showHometown = false
    @State private var hometown: String = ""
    @State private var gender = "Male"
    @State private var showingImagePicker = false
    
    // Social media handles
    @State private var instagramHandle: String = ""
    @State private var twitterHandle: String = ""
    
    // Profile photo
    @State private var profileImage: UIImage?
    @State private var inputImage: UIImage?
    @State private var activeSheet: ActiveSheet?
    
    enum ActiveSheet: Identifiable {
        case photoLibrary, camera, cropper
        
        var id: Int {
            switch self {
            case .photoLibrary: return 0
            case .camera: return 1
            case .cropper: return 2
            }
        }
    }
    
    // Matches
    @State private var matches: [MainViewUserMatch] = []
    
    // Video management
    @State private var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
    @State private var showDeleteConfirm = false
    @State private var videoToDelete: UUID? = nil
    @State private var isShowingVideoSourceSheet = false
    @State private var isShowingCamera = false
    @State private var videoPickerShowing = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isVideoUploading = false
    
    // Processing state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showSuccessMessage = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                  
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Profile photo section
                        VStack(alignment: .center, spacing: 16) {
                            ZStack {
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.5))
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.white)
                                                .font(.system(size: 60))
                                        )
                                }
                                
                                Button(action: {
                                    showingImagePicker = true
                                }) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "pencil")
                                                .foregroundColor(.white)
                                                .font(.system(size: 18))
                                        )
                                        .shadow(radius: 3)
                                }
                                .offset(x: 40, y: 40)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 20)
                        
                        // Basic info
                        Group {
                            HStack {
                                Text("Name: \(firstName)")
                                    .font(.appBody)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        
                        // Social media handles
                        Group {
                            HStack {
                                Text("Instagram:")
                                    .foregroundColor(.white)
                                TextField("@username", text: $instagramHandle)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("X/Twitter:")
                                    .foregroundColor(.white)
                                TextField("@username", text: $twitterHandle)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Toggle("Use latest X/Twitter post as State of Mind", isOn: $syncStateOfMindWithX)
                            .foregroundColor(.white)
                            .disabled(twitterHandle.isEmpty)
                            .onChange(of: syncStateOfMindWithX) { newValue in
                                if newValue && !twitterHandle.isEmpty {
                                    authenticateWithTwitter()
                                }
                            }

                        if syncStateOfMindWithX {
                            HStack {
                                if isFetchingTweet {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else if let lastSync = lastSyncTime {
                                    Text("Last synced: \(timeAgoString(from: lastSync))")
                                        .font(.appCaption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                
                                Spacer()
                                
                                Button("Sync Now") {
                                    fetchTweetDirectly()
                                }
                                .font(.appCaption)
                                .foregroundColor(.appAccent)
                                .disabled(twitterHandle.isEmpty || isFetchingTweet)
                            }
                            .padding(.top, 4)
                        }
                        
                        // State of Mind
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current State of Mind")
                                .font(.appBody)
                                .foregroundColor(.white)
                            
                            TextEditor(text: $editedStateOfMind)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .colorScheme(.dark)
                        }
                        
                        // Job title
                        Toggle("Show Job Title", isOn: $showJobTitle)
                            .foregroundColor(.white)
                        
                        if showJobTitle {
                            TextField("Your job title", text: $jobTitle)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        // School
                        Toggle("Show School", isOn: $showSchool)
                            .foregroundColor(.white)
                        
                        if showSchool {
                            TextField("Your school", text: $school)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        // Religion
                        Toggle("Show Religion", isOn: $showReligion)
                            .foregroundColor(.white)

                        if showReligion {
                            NavigationLink {
                                ReligionSelectionView(
                                    selectedReligion: $religion,
                                    onSelect: { newReligion in
                                        // This explicit callback ensures the religion is updated
                                        self.religion = newReligion
                                        print("Religion updated to: \(newReligion)")
                                    }
                                )
                            } label: {
                                HStack {
                                    Text("Religious Beliefs")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(religion.isEmpty ? "Not selected" : religion)
                                        .foregroundColor(.white.opacity(0.7))
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Hometown
                        Toggle("Show Hometown", isOn: $showHometown)
                            .foregroundColor(.white)
                        
                        if showHometown {
                            TextField("Your hometown", text: $hometown)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        // Gender
                        HStack {
                            Text("Gender")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("Gender", selection: $gender) {
                                Text("Male").tag("Male")
                                Text("Female").tag("Female")
                                Text("Prefer not to say").tag("Prefer not to say")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .accentColor(.white)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        
                        // Matches section
                        MatchesSectionView(
                            matches: matches,
                            onTapMatch: { userId in
                                showUserProfile(userId: userId)
                            },
                            onCallMatch: { userId, name in
                                sendCallRequest(to: userId, name: name)
                            },
                            onUnmatch: { userId, name in
                                unmatchUser(userId: userId, userName: name)
                            }
                        )
                        
                        // Videos section
                        VideosSectionView(
                            videos: videos,
                            onTapVideo: { url in
                                playVideo(url: url)
                            },
                            onDeleteVideo: { id in
                                deleteVideoDirectly(id: id)
                            },
                            onAddVideo: {
                                isShowingVideoSourceSheet = true
                            }
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .padding()
                }
                
                // Loading overlay
                if isSaving {
                    Color.black.opacity(0.7)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        PulsingLoaderView()
                        Text("Saving changes...")
                            .foregroundColor(.white)
                            .padding(.top, 20)
                    }
                }
                
                // Success message
                if showSuccessMessage {
                    VStack {
                        Text("Profile saved successfully!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(10)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showSuccessMessage = false
                            }
                        }
                    }
                }
            }
            // Use a single sheet presentation with ID to manage all sheet states
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(
                    image: $profileImage,
                    sourceType: .photoLibrary,
                    userIdentifier: userIdentifier
                )
            }
            .actionSheet(isPresented: $isShowingVideoSourceSheet) {
                ActionSheet(
                    title: Text("Add Video"),
                    message: Text("Choose a source"),
                    buttons: [
                        .default(Text("Take Video")) {
                            self.sourceType = .camera
                            self.isShowingCamera = true
                        },
                        .default(Text("Choose from Library")) {
                            self.sourceType = .photoLibrary
                            self.videoPickerShowing = true
                        },
                        .cancel()
                    ]
                )
            }
            .sheet(isPresented: $videoPickerShowing) {
                VideoCaptureView(isCamera: false) { videoURL, title in
                    if let url = videoURL {
                        uploadVideo(url: url, title: title)
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                VideoCaptureView(isCamera: true) { videoURL, title in
                    if let url = videoURL {
                        uploadVideo(url: url, title: title)
                    }
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .navigationBarItems(
                leading: Button("Cancel") { onCancel() },
                trailing: Button("Save") {
                    saveProfile()
                }
            )
            .navigationBarTitle("Edit Profile", displayMode: .inline)
            .onAppear {
                // Add observer for Twitter OAuth callback - fixed without weak self
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("TwitterAuthCallback"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let url = notification.userInfo?["url"] as? URL,
                       let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
                       let code = codeItem.value {
                        // Handle the authorization code
                        // Get the stored verifier from UserDefaults
                        let verifier = UserDefaults.standard.string(forKey: "twitter_code_verifier_\(self.userIdentifier)") ?? "challenge"
                        self.getAccessToken(code: code, verifier: verifier)
                    }
                }
                
                loadUserProfile()
                loadMatches()
                // Check if we need to sync with Twitter
                if syncStateOfMindWithX && !twitterHandle.isEmpty {
                    // Only auto-sync if it's been more than 30 minutes since the last sync
                    if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) > 1800 {
                        print("Auto-syncing Twitter status of mind")
                        fetchLatestTweet()
                    }
                }
            }
            .onDisappear {
                // Remove the Twitter callback observer
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSNotification.Name("TwitterAuthCallback"),
                    object: nil
                )
            }
        }
    }
    
    // Helper functions for PKCE
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        
        let verifier = Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        print("Generated code verifier: \(verifier)")
        return verifier
    }
    
    private func fetchTweetDirectly() {
        guard !twitterHandle.isEmpty else { return }
        
        // Indicate loading
        self.isFetchingTweet = true
        
        // Clean handle if needed (remove @ if present)
        let username = twitterHandle.replacingOccurrences(of: "@", with: "")
        
        // Twitter API v2 endpoints
        let userEndpoint = "https://api.twitter.com/2/users/by/username/\(username)"
        
        // API credentials from your Twitter Developer Portal
        let bearerToken = "AAAAAAAAAAAAAAAAAAAAAHFd0gEAAAAAKU5sNYTvr1nxmgnWzGzG0wV3OQQ%3Dl0xcuD86wrsoLZQGZQJ5RO7nCcjAXefeMcfSszeKsbnuxC6iD0"
        
        // Create the request for user lookup
        var userRequest = URLRequest(url: URL(string: userEndpoint)!)
        userRequest.httpMethod = "GET"
        userRequest.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        print("Fetching Twitter user: \(username)")
        
        // First find the user ID
        URLSession.shared.dataTask(with: userRequest) { data, response, error in
            if let error = error {
                print("Error fetching Twitter user: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
                return
            }
            
            guard let data = data else {
                print("No data received from Twitter")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
                return
            }
            
            // Log the full response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Twitter user response: \(responseString)")
            }
            
            do {
                // Parse the JSON response
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                // Extract the user ID from the response
                if let userData = json?["data"] as? [String: Any],
                   let userId = userData["id"] as? String {
                    
                    print("Found Twitter user ID: \(userId)")
                    
                    // Now fetch the tweets for this user
                    self.fetchTweetsForUserId(userId: userId, bearerToken: bearerToken)
                } else {
                    print("Could not find Twitter user ID in response")
                    DispatchQueue.main.async {
                        self.isFetchingTweet = false
                    }
                }
            } catch {
                print("Error parsing Twitter response: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
            }
        }.resume()
    }

    private func fetchTweetsForUserId(userId: String, bearerToken: String) {
        // Tweets endpoint with user ID
        let tweetsEndpoint = "https://api.twitter.com/2/users/\(userId)/tweets?max_results=5"
        
        // Create the request for tweets
        var tweetsRequest = URLRequest(url: URL(string: tweetsEndpoint)!)
        tweetsRequest.httpMethod = "GET"
        tweetsRequest.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        print("Fetching tweets for user ID: \(userId)")
        
        // Fetch the tweets
        URLSession.shared.dataTask(with: tweetsRequest) { data, response, error in
            // Always mark as not fetching when complete
            defer {
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
            }
            
            if let error = error {
                print("Error fetching tweets: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No tweet data received from Twitter")
                return
            }
            
            // Log the full response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Twitter tweets response: \(responseString)")
            }
            
            do {
                // Parse the JSON response
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                // Extract the tweets from the response
                if let tweetsData = json?["data"] as? [[String: Any]],
                   let firstTweet = tweetsData.first,
                   let tweetText = firstTweet["text"] as? String {
                    
                    print("Found tweet: \(tweetText)")
                    
                    // Update the state of mind with the tweet text
                    DispatchQueue.main.async {
                        self.editedStateOfMind = tweetText
                        self.lastSyncTime = Date()
                        UserDefaults.standard.set(Date(), forKey: "twitterLastSync_\(self.userIdentifier)")
                    }
                } else {
                    print("No tweets found or could not parse tweets from response")
                }
            } catch {
                print("Error parsing tweets response: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        // For simplicity, using plain method where challenge equals verifier
        // In production, you would use S256 method with proper hashing
        return verifier
    }
    
    // Add this method to ProfileEditorView
    private func authenticateWithTwitter() {
        print("Starting Twitter authentication flow")
        guard !twitterHandle.isEmpty else { return }
        
        isAuthenticatingTwitter = true
        
        // Create a proper code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Store the code verifier for later use
        UserDefaults.standard.set(codeVerifier, forKey: "twitter_code_verifier_\(userIdentifier)")
        
        // Get the client ID from your Twitter developer portal
        let clientId = "TU5YUERRROVpUE5ZMGVNY3pMSVU6MTpjaQ"
        
        // Use the standard callback that Twitter expects
        let redirectUri = "https://buzzaboo.com"
        let state = UUID().uuidString
        
        // Create the auth URL with proper encoding
        let encodedRedirect = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? redirectUri
        let authURL = "https://twitter.com/i/oauth2/authorize?response_type=code&client_id=\(clientId)&redirect_uri=\(encodedRedirect)&scope=tweet.read%20users.read&state=\(state)&code_challenge=\(codeChallenge)&code_challenge_method=plain"
        
        guard let url = URL(string: authURL) else {
            isAuthenticatingTwitter = false
            print("Error creating Twitter auth URL")
            return
        }
        
        // Log the URL for debugging
        print("Opening Twitter auth URL: \(authURL)")
        
        // Create the auth session
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { callbackURL, error in
            self.isAuthenticatingTwitter = false
            
            if let error = error {
                print("Error during Twitter auth: \(error.localizedDescription)")
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("No callback URL received")
                return
            }
            
            print("Received callback URL: \(callbackURL)")
            
            // Extract the code from the callback URL
            if let components = URLComponents(string: callbackURL.absoluteString),
               let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
               let code = codeItem.value {
                
                // Get the stored verifier
                let verifier = UserDefaults.standard.string(forKey: "twitter_code_verifier_\(self.userIdentifier)") ?? "challenge"
                self.getAccessToken(code: code, verifier: verifier)
            }
        }
        
        // This is necessary for the auth session to work properly
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            session.presentationContextProvider = TwitterPresentationContextProvider(window: window)
            
            // Set this to true to force it to use an embedded browser
            session.prefersEphemeralWebBrowserSession = true
            
            let started = session.start()
            // Keep a reference to prevent deallocation
            self.twitterAuthSession = session
            print("Authentication session started: \(started)")
        } else {
            print("Could not find window scene to present authentication")
            isAuthenticatingTwitter = false
        }
    }

    // Add this to get the access token - with correct self handling
    private func getAccessToken(code: String, verifier: String) {
        print("Getting access token with code: \(code)")
        
        let clientId = "TU5YUERRROVpUE5ZMGVNY3pMSVU6MTpjaQ"
        let clientSecret = "TnMqJ2H7QWr7dr_PnzwXEl8verOIp_tIUyvJHERmy5LBRR2kbj"
        let redirectUri = "https://buzzaboo.com?redirect=true"
        
        let url = URL(string: "https://api.twitter.com/2/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create the proper form data
        let parameters = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier
        ]
        
        // Add proper headers
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Create URL-encoded form data
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        print("Sending token request with parameters: \(parameters)")
        
        // Remove weak self since ProfileEditorView is a struct
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Store needed properties in local variables to avoid capturing self
            let userIdentifier = self.userIdentifier
            
            if let error = error {
                print("Error getting access token: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from token endpoint")
                return
            }
            
            // Log the full response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("Token response: \(responseStr)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let accessToken = json?["access_token"] as? String {
                    print("✅ Successfully obtained Twitter access token")
                    
                    // Save the access token
                    UserDefaults.standard.set(accessToken, forKey: "twitterAccessToken_\(userIdentifier)")
                    
                    // Now fetch the latest tweet
                    self.fetchLatestTweetWithAPI(accessToken: accessToken)
                } else {
                    print("Failed to extract access token from response")
                }
            } catch {
                print("Error parsing token response: \(error)")
            }
        }.resume()
    }

    // Add this to fetch the latest tweet using the Twitter API
    // Fixed fetchLatestTweetWithAPI without weak self
    private func fetchLatestTweetWithAPI(accessToken: String) {
        // The Twitter handle without @
        let username = twitterHandle.replacingOccurrences(of: "@", with: "")
        
        // First get the user ID from the username
        let userURL = URL(string: "https://api.twitter.com/2/users/by/username/\(username)")!
        var userRequest = URLRequest(url: userURL)
        userRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("Fetching Twitter user ID for username: \(username)")
        
        // Store needed properties in local variables to avoid capturing self
        let capturedUserIdentifier = userIdentifier
        
        URLSession.shared.dataTask(with: userRequest) { data, response, error in
            if let error = error {
                print("Error fetching Twitter user: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
                return
            }
            
            guard let data = data else {
                print("No data received for Twitter user")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
                return
            }
            
            // Log the response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("Twitter user response: \(responseStr)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let userData = json?["data"] as? [String: Any],
                   let userId = userData["id"] as? String {
                    print("Found Twitter user ID: \(userId)")
                    // Now get the latest tweet
                    self.fetchTweetsForUser(userId: userId, accessToken: accessToken)
                } else {
                    print("Could not get Twitter user ID")
                    DispatchQueue.main.async {
                        self.isFetchingTweet = false
                    }
                }
            } catch {
                print("Error parsing Twitter user response: \(error)")
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
            }
        }.resume()
    }

    // Fixed fetchTweetsForUser without weak self
    private func fetchTweetsForUser(userId: String, accessToken: String) {
        let tweetsURL = URL(string: "https://api.twitter.com/2/users/\(userId)/tweets?max_results=5")!
        var tweetsRequest = URLRequest(url: tweetsURL)
        tweetsRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("Fetching tweets for user ID: \(userId)")
        
        // Store needed properties in local variables to avoid capturing self
        let capturedUserIdentifier = userIdentifier
        
        URLSession.shared.dataTask(with: tweetsRequest) { data, response, error in
            // Always set fetching to false at the end
            defer {
                DispatchQueue.main.async {
                    self.isFetchingTweet = false
                }
            }
            
            if let error = error {
                print("Error fetching tweets: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received for tweets")
                return
            }
            
            // Log the response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("Tweets response: \(responseStr)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let tweetsData = json?["data"] as? [[String: Any]],
                   let latestTweet = tweetsData.first,
                   let tweetText = latestTweet["text"] as? String {
                    
                    print("Found latest tweet: \(tweetText)")
                    
                    DispatchQueue.main.async {
                        self.editedStateOfMind = tweetText
                        self.lastSyncTime = Date()
                        UserDefaults.standard.set(Date(), forKey: "twitterLastSync_\(capturedUserIdentifier)")
                        UserDefaults.standard.set(self.syncStateOfMindWithX, forKey: "syncStateOfMindWithX_\(capturedUserIdentifier)")
                    }
                } else {
                    print("No tweets found or could not parse tweet data")
                }
            } catch {
                print("Error parsing tweets response: \(error)")
            }
        }.resume()
    }
    
    // Add this function to handle call requests:
    private func sendCallRequest(to userId: String, name: String) {
        if !CallRequestManager.shared.isInCooldown(userId: userId) {
            CallRequestManager.shared.sendCallRequest(
                from: userIdentifier,
                to: userId,
                senderName: firstName
            ) { success in
                if success {
                    // Only attempt to show the alert if the request was successful
                    DispatchQueue.main.async {
                        self.showCallRequestSentAlert(to: name)
                    }
                }
            }
        } else {
            showCooldownAlert(for: name)
        }
    }
    
    private func fetchLatestTweet() {
        guard !twitterHandle.isEmpty else { return }
        
        self.isFetchingTweet = true
        
        // Check if we have a saved access token
        if let accessToken = UserDefaults.standard.string(forKey: "twitterAccessToken_\(userIdentifier)") {
            print("Using existing Twitter access token")
            self.fetchLatestTweetWithAPI(accessToken: accessToken)
        } else {
            // No token - need to authenticate
            print("No existing token, starting authentication")
            self.authenticateWithTwitter()
        }
    }

    private func fetchTweetAlternative(username: String) {
        let urlString = "https://syndication.twitter.com/timeline/profile?screen_name=\(username)"
        
        guard let url = URL(string: urlString) else {
            isFetchingTweet = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isFetchingTweet = false
                
                guard let data = data,
                      let html = String(data: data, encoding: .utf8) else {
                    return
                }
                
                // Extract the latest tweet text
                if let tweetRange = html.range(of: "<p class=\"timeline-Tweet-text\">"),
                   let endRange = html[tweetRange.upperBound...].range(of: "</p>") {
                    
                    var tweetText = String(html[tweetRange.upperBound..<endRange.lowerBound])
                    
                    // Clean up HTML entities
                    tweetText = tweetText.replacingOccurrences(of: "&amp;", with: "&")
                    tweetText = tweetText.replacingOccurrences(of: "&lt;", with: "<")
                    tweetText = tweetText.replacingOccurrences(of: "&gt;", with: ">")
                    tweetText = tweetText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    
                    // Update state of mind
                    self.editedStateOfMind = tweetText
                    self.lastSyncTime = Date()
                    
                    // Save the toggle state to UserDefaults
                    UserDefaults.standard.set(self.syncStateOfMindWithX, forKey: "syncStateOfMindWithX_\(self.userIdentifier)")
                    print("Updated state of mind from tweet (alternative): \(tweetText)")
                }
            }
        }.resume()
    }

    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return "\(day) day\(day == 1 ? "" : "s") ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour) hour\(hour == 1 ? "" : "s") ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute) minute\(minute == 1 ? "" : "s") ago"
        } else {
            return "just now"
        }
    }

    private func showCallRequestSentAlert(to name: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let topController = window.rootViewController {
            
            var currentController = topController
            while let presented = currentController.presentedViewController {
                currentController = presented
            }
            
            let alert = UIAlertController(
                title: "Call Request Sent",
                message: "Your request to video chat with \(name) has been sent. They can accept or decline.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Only present if nothing else is presented
            if currentController.presentedViewController == nil {
                currentController.present(alert, animated: true)
            }
        }
    }

    private func showCooldownAlert(for name: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let topController = window.rootViewController {
            
            var currentController = topController
            while let presented = currentController.presentedViewController {
                currentController = presented
            }
            
            let alert = UIAlertController(
                title: "Please Wait",
                message: "You can only send another call request to \(name) after 10 minutes from your last request.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Only present if nothing else is presented
            if currentController.presentedViewController == nil {
                currentController.present(alert, animated: true)
            }
        }
    }
    
    // Update the unmatch function in ProfileEditorView
    // In ProfileEditorView:
    private func unmatchUser(userId: String, userName: String) {
        print("Starting unmatch process for \(userName)")
        
        // Toggle like/unlike instead of unmatch
        let database = CKContainer.default().publicCloudDatabase
        let myPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let myQuery = CKQuery(recordType: "UserProfile", predicate: myPredicate)
        
        database.perform(myQuery, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error finding current user record: \(error.localizedDescription)")
                return
            }
            
            guard let myRecord = records?.first else {
                print("Could not find current user record")
                return
            }
            
            // Check if user has liked this match
            var likedUsers = myRecord["likedUsers"] as? [String] ?? []
            let isLiked = likedUsers.contains(userId)
            
            // Toggle like state
            if isLiked {
                // Unlike: Remove from likedUsers
                likedUsers.removeAll(where: { $0 == userId })
                myRecord["likedUsers"] = likedUsers
                
                // Update target user's like count
                self.decrementLikeCount(for: userId)
                
                print("Unliking user \(userId)")
            } else {
                // Like: Add to likedUsers
                likedUsers.append(userId)
                myRecord["likedUsers"] = likedUsers
                
                // Update target user's like count
                self.incrementLikeCount(for: userId)
                
                print("Liking user \(userId)")
            }
            
            // Save changes
            database.save(myRecord) { _, error in
                if let error = error {
                    print("Error updating like status: \(error.localizedDescription)")
                } else {
                    print("Successfully updated like status for \(userName)")
                }
            }
        }
    }

    // Add these helper methods to ProfileEditorView
    private func incrementLikeCount(for userId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                let currentLikes = record["likeCount"] as? Int ?? 0
                record["likeCount"] = currentLikes + 1
                
                database.save(record) { _, error in
                    if let error = error {
                        print("Error incrementing like count: \(error.localizedDescription)")
                    } else {
                        print("Successfully incremented like count")
                    }
                }
            }
        }
    }

    private func decrementLikeCount(for userId: String) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                let currentLikes = record["likeCount"] as? Int ?? 0
                record["likeCount"] = max(0, currentLikes - 1)
                
                database.save(record) { _, error in
                    if let error = error {
                        print("Error decrementing like count: \(error.localizedDescription)")
                    } else {
                        print("Successfully decremented like count")
                    }
                }
            }
        }
    }
    
    private func loadMatches() {
        print("Loading matches for user: \(userIdentifier)")
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error loading profile for matches: \(error.localizedDescription)")
                return
            }
            
            guard let record = records?.first else {
                print("No profile record found for \(self.userIdentifier)")
                return
            }

            // Initialize matches array if it doesn't exist
            if record["matches"] == nil {
                record["matches"] = [String]()
                database.save(record) { _, _ in
                    print("Created empty matches array")
                }
                
                DispatchQueue.main.async {
                    self.matches = []
                }
                return
            }

            if let matchIds = record["matches"] as? [String], !matchIds.isEmpty {
                print("Found \(matchIds.count) matches: \(matchIds)")
                
                // For each matched ID, fetch the user profile
                let group = DispatchGroup()
                var fetchedMatches: [MainViewUserMatch] = []
                
                for matchId in matchIds {
                    group.enter()
                    self.fetchUserProfile(userId: matchId) { name, image, isOnline in
                        if let name = name {
                            let match = MainViewUserMatch(id: matchId, name: name, profileImage: image, isOnline: isOnline)
                            fetchedMatches.append(match)
                            print("Added match: \(name), online: \(isOnline)")
                        } else {
                            print("Could not fetch profile for match ID: \(matchId)")
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self.matches = fetchedMatches
                    print("Updated matches array with \(fetchedMatches.count) items")
                }
            } else {
                print("No matches array found or it's empty")
                DispatchQueue.main.async {
                    self.matches = []
                }
            }
        }
    }
    
    // Load existing profile data
    private func loadUserProfile() {
        // Set initial values from binding
        editedStateOfMind = stateOfMind
        
        // Store current religion before loading
        let currentReligion = self.religion
        
        // Load sync state from UserDefaults first
        self.syncStateOfMindWithX = UserDefaults.standard.bool(forKey: "syncStateOfMindWithX_\(userIdentifier)")
        
        // Load profile from CloudKit
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error loading profile: \(error.localizedDescription)")
                return
            }
            
            if let record = records?.first {
                DispatchQueue.main.async {
                    // Load profile image if available
                    if let imageAsset = record["profileImage"] as? CKAsset,
                       let imageUrl = imageAsset.fileURL,
                       let imageData = try? Data(contentsOf: imageUrl),
                       let image = UIImage(data: imageData) {
                        self.profileImage = image
                    }
                    
                    // Load social handles
                    self.instagramHandle = record["instagramHandle"] as? String ?? ""
                    self.twitterHandle = record["twitterHandle"] as? String ?? ""
                    
                    // Check for syncStateOfMindWithX in the record and update UserDefaults if needed
                    if let syncWithX = record["syncStateOfMindWithX"] as? Int, syncWithX == 1 {
                        self.syncStateOfMindWithX = true
                        UserDefaults.standard.set(true, forKey: "syncStateOfMindWithX_\(self.userIdentifier)")
                    }
                    
                    // Load basic profile fields
                    if let religionValue = record["religion"] as? String {
                        print("Loaded religion from CloudKit: \(religionValue)")
                        // ONLY CHANGED LINE: Add condition to prevent overwriting new selection
                        if self.religion.isEmpty {
                            self.religion = religionValue
                        }
                    } else {
                        print("No religion value found in CloudKit")
                        // Only set to empty if we haven't changed it
                        if self.religion.isEmpty {
                            self.religion = ""
                        }
                    }
                    self.showReligion = record["showReligion"] as? Int == 1
                    
                    self.showJobTitle = record["showJobTitle"] as? Int == 1
                    self.jobTitle = record["jobTitle"] as? String ?? ""
                    self.showSchool = record["showSchool"] as? Int == 1
                    self.school = record["school"] as? String ?? ""
                    self.showHometown = record["showHometown"] as? Int == 1
                    self.hometown = record["hometown"] as? String ?? ""
                    self.gender = record["gender"] as? String ?? "Male"
                    
                    // Load videos
                    self.loadUserVideos()
                }
            }
        }
    }
    
    private func saveImageToCloudKit(_ image: UIImage) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                // Save image to temporary file
                if let imageData = image.jpegData(compressionQuality: 0.7) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
                    
                    do {
                        try imageData.write(to: tempURL)
                        let asset = CKAsset(fileURL: tempURL)
                        record["profileImage"] = asset
                        
                        database.save(record) { _, _ in
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                    } catch {
                        print("Error saving image: \(error)")
                    }
                }
            }
        }
    }

    // Modify the showUserProfile method in ProfileEditorView
    private func showUserProfile(userId: String) {
        ProfileViewHelper.shared.showUserProfile(userId: userId)
    }

    // Add this method to ProfileEditorView
    // Improved loadVideosForProfileView function for ProfileEditorView
    private func loadVideosForProfileView(userId: String, completion: @escaping ([(id: UUID, title: String, url: URL?, views: Int)]) -> Void) {
        print("🎬 Loading videos for user profile: \(userId)")
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "owner == %@", userId)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error loading videos: \(error.localizedDescription)")
                completion([])
                return
            }
            
            var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
            let group = DispatchGroup()
            
            if let videoRecords = records, !videoRecords.isEmpty {
                print("✅ Found \(videoRecords.count) videos for user \(userId)")
                
                for record in videoRecords {
                    group.enter()
                    
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    
                    if let videoAsset = record["videoFile"] as? CKAsset, let assetURL = videoAsset.fileURL {
                        // Create a local copy of the video for reliable access
                        if FileManager.default.fileExists(atPath: assetURL.path) {
                            // Create a unique file in the temp directory
                            let uniqueFileName = "\(UUID().uuidString)_\(videoIdString).mp4"
                            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFileName)
                            
                            do {
                                // Remove any existing file at the destination
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    try FileManager.default.removeItem(at: localURL)
                                }
                                
                                // Copy the file
                                try FileManager.default.copyItem(at: assetURL, to: localURL)
                                
                                // Verify the file was properly copied
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    do {
                                        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                                        if let fileSize = attributes[FileAttributeKey.size] as? NSNumber, fileSize.intValue > 100 {
                                            print("✅ Successfully copied video (\(fileSize.intValue) bytes): \(title)")
                                            videos.append((id: videoId, title: title, url: localURL, views: views))
                                        } else {
                                            print("⚠️ Video file appears too small or size attribute missing")
                                        }
                                    } catch {
                                        print("❌ Error checking file attributes: \(error.localizedDescription)")
                                    }
                                } else {
                                    print("⚠️ Copy failed - file doesn't exist at destination")
                                }
                            } catch {
                                print("❌ Error copying video file: \(error.localizedDescription)")
                            }
                        } else {
                            print("⚠️ Source video asset file not found: \(assetURL.path)")
                        }
                    }
                    
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    print("✅ Completed loading \(videos.count) videos")
                    completion(videos)
                }
            } else {
                print("No videos found for user \(userId)")
                completion([])
            }
        }
    }
    
    private func createProfileDetailsFromRecord(_ record: CKRecord) -> UnifiedProfileDetails {
            var profileImage: UIImage? = nil
            
            // Try to get profile image
            if let imageAsset = record["profileImage"] as? CKAsset,
               let imageUrl = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageUrl) {
                profileImage = UIImage(data: imageData)
            }
            
            // Get distance if location is available
            var distance: Double? = nil
            if let location = record["location"] as? CLLocation,
               let myLocation = CLLocationManager().location {
                let distanceMeters = myLocation.distance(from: location)
                distance = distanceMeters / 1609.34 // Convert to miles
            }
            
            // Create the profile details
            return UnifiedProfileDetails(
                id: record["identifier"] as? String ?? "",
                name: record["firstName"] as? String ?? "User",
                image: profileImage,
                gender: record["gender"] as? String ?? "Not specified",
                stateOfMind: record["stateOfMind"] as? String ?? "",
                religion: record["religion"] as? String ?? "",
                showReligion: record["showReligion"] as? Int == 1,
                jobTitle: record["jobTitle"] as? String ?? "",
                showJobTitle: record["showJobTitle"] as? Int == 1,
                school: record["school"] as? String ?? "",
                showSchool: record["showSchool"] as? Int == 1,
                hometown: record["hometown"] as? String ?? "",
                showHometown: record["showHometown"] as? Int == 1,
                instagramHandle: record["instagramHandle"] as? String ?? "",
                twitterHandle: record["twitterHandle"] as? String ?? "",
                likeCount: record["likeCount"] as? Int ?? 0,
                distanceMiles: distance,
                videos: [] // Videos will be loaded separately
            )
        }

    private func presentProfile(_ record: CKRecord) {
        // Create a UnifiedProfileDetails instance from the record
        let details = createProfileDetailsFromRecord(record)
        
        let profileView = UnifiedProfileView(
            userDetails: details,
            onClose: {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let topController = window.rootViewController {
                    topController.dismiss(animated: true)
                }
            }
        )
        
        let hostingController = UIHostingController(rootView: profileView)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let topController = window.rootViewController {
            // Find the top-most controller
            var currentController = topController
            while let presented = currentController.presentedViewController {
                currentController = presented
            }
            
            // Present the new controller
            currentController.present(hostingController, animated: true)
        }
    }

    // Add this function to fetch videos
    private func fetchUserVideos(userId: String, completion: @escaping ([(id: UUID, title: String, url: URL?, views: Int)]) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "owner == %@", userId)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
            
            if let videoRecords = records, !videoRecords.isEmpty {
                print("Found \(videoRecords.count) videos for user \(userId)")
                
                for record in videoRecords {
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    
                    if let videoAsset = record["videoFile"] as? CKAsset, let fileURL = videoAsset.fileURL {
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            videos.append((id: videoId, title: title, url: fileURL, views: views))
                            print("Added video: \(title)")
                        }
                    }
                }
            }
            
            completion(videos)
        }
    }
    
    // Fetch user profile for a specific user ID
    private func fetchUserProfile(userId: String, completion: @escaping (String?, UIImage?, Bool) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let record = records?.first {
                    let name = record["firstName"] as? String ?? "User"
                    var profileImage: UIImage? = nil
                    var isOnline = false
                    
                    // Get last active time
                    let lastActive = record["lastActiveTime"] as? Date
                    
                    // Consider user online if active in the last 30 seconds
                    if let lastActive = lastActive {
                        let thirtySecondsAgo = Date().addingTimeInterval(-30)
                        isOnline = lastActive > thirtySecondsAgo
                    }
                    
                    if let imageAsset = record["profileImage"] as? CKAsset,
                       let imageUrl = imageAsset.fileURL,
                       let imageData = try? Data(contentsOf: imageUrl) {
                        profileImage = UIImage(data: imageData)
                    }
                    
                    completion(name, profileImage, isOnline)
                } else {
                    completion(nil, nil, false)
                }
            }
        }
    }
    
    // Fetch a complete user profile record
    private func fetchUserProfile(for userId: String, completion: @escaping (CKRecord?) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                completion(records?.first)
            }
        }
    }
    
    // Load user's videos
    private func loadUserVideos() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "owner == %@", userIdentifier)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error loading videos: \(error.localizedDescription)")
                return
            }
            
            if let videoRecords = records, !videoRecords.isEmpty {
                var loadedVideos: [(id: UUID, title: String, url: URL?, views: Int)] = []
                
                let group = DispatchGroup()
                
                for record in videoRecords {
                    group.enter()
                    
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    var videoURL: URL? = nil
                    
                    // First try to get from local path if available
                    if let localPath = record["localPath"] as? String {
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let fileURL = documentsDirectory.appendingPathComponent(localPath)
                        
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            print("✅ Found video at local path: \(fileURL.path)")
                            videoURL = fileURL
                        } else {
                            print("⚠️ Local path file doesn't exist: \(fileURL.path)")
                        }
                    }
                    
                    // If not found locally, try from CloudKit asset
                    if videoURL == nil, let videoAsset = record["videoFile"] as? CKAsset, let assetURL = videoAsset.fileURL {
                        if FileManager.default.fileExists(atPath: assetURL.path) {
                            // Create a persistent copy
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let videosDirectory = documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
                            
                            // Create the directory if needed
                            try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
                            
                            let persistentURL = videosDirectory.appendingPathComponent("\(videoIdString).mp4")
                            
                            do {
                                // Remove any existing file at destination
                                if FileManager.default.fileExists(atPath: persistentURL.path) {
                                    try FileManager.default.removeItem(at: persistentURL)
                                }
                                
                                // Copy the file to a persistent location
                                try FileManager.default.copyItem(at: assetURL, to: persistentURL)
                                
                                // Update CloudKit record with the local path
                                record["localPath"] = "Videos/\(videoIdString).mp4"
                                database.save(record) { _, _ in }
                                
                                videoURL = persistentURL
                                print("✅ Copied CloudKit asset to persistent storage: \(persistentURL.path)")
                            } catch {
                                print("❌ Error copying CloudKit asset: \(error.localizedDescription)")
                                videoURL = assetURL
                            }
                        } else {
                            print("⚠️ CloudKit asset file doesn't exist: \(assetURL.path)")
                        }
                    }
                    
                    if let url = videoURL {
                        // Check file size to ensure it's a valid video
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                            if let size = attributes[.size] as? NSNumber, size.intValue > 100 {
                                loadedVideos.append((id: videoId, title: title, url: url, views: views))
                                print("✅ Added video to list: \(title), size: \(size.intValue) bytes")
                            } else {
                                print("⚠️ Skipping video - file size too small: \(url.path)")
                            }
                        } catch {
                            print("❌ Error checking file attributes: \(error.localizedDescription)")
                        }
                    } else {
                        print("⚠️ No valid URL found for video: \(videoIdString)")
                    }
                    
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    self.videos = loadedVideos
                    print("✅ Updated videos with \(loadedVideos.count) videos")
                }
            } else {
                print("No videos found for user ID: \(self.userIdentifier)")
                DispatchQueue.main.async {
                    self.videos = []
                }
            }
        }
    }
    
    // Save profile changes
    // Keep the original name, but improve the implementation
    func saveProfile() {
        // Start by setting the saving state
        isSaving = true
        
        // Implement the retry mechanism
        saveProfileWithRetry(retriesLeft: 3)
    }
    
    // Internal function to handle retries
    private func saveProfileWithRetry(retriesLeft: Int) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error finding profile: \(error.localizedDescription)"
                    self.showErrorAlert = true
                    self.isSaving = false
                }
                return
            }
            
            var recordToSave: CKRecord
            
            if let existingRecord = records?.first {
                // Update existing record
                recordToSave = existingRecord
            } else {
                // Create new record
                recordToSave = CKRecord(recordType: "UserProfile")
                recordToSave["identifier"] = self.userIdentifier
                recordToSave["firstName"] = self.firstName
            }
            
            // Update all fields
            recordToSave["stateOfMind"] = self.editedStateOfMind
            recordToSave["religion"] = self.religion
            recordToSave["showJobTitle"] = self.showJobTitle ? 1 : 0
            recordToSave["jobTitle"] = self.jobTitle
            recordToSave["showSchool"] = self.showSchool ? 1 : 0
            recordToSave["school"] = self.school
            recordToSave["showReligion"] = self.showReligion ? 1 : 0
            recordToSave["showHometown"] = self.showHometown ? 1 : 0
            recordToSave["hometown"] = self.hometown
            recordToSave["gender"] = self.gender
            recordToSave["syncStateOfMindWithX"] = self.syncStateOfMindWithX ? 1 : 0
            recordToSave["instagramHandle"] = self.instagramHandle
            recordToSave["twitterHandle"] = self.twitterHandle
            
            // Save profile image if available
            if let profileImage = self.profileImage,
               let imageData = profileImage.jpegData(compressionQuality: 0.7) {
                
                let temporaryImageURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".jpg")
                
                do {
                    try imageData.write(to: temporaryImageURL)
                    let imageAsset = CKAsset(fileURL: temporaryImageURL)
                    recordToSave["profileImage"] = imageAsset
                } catch {
                    print("Error creating temporary file: \(error)")
                }
            }
            
            // Use a dedicated save operation with proper error handling and retries
            let saveOperation = CKModifyRecordsOperation(recordsToSave: [recordToSave], recordIDsToDelete: nil)
            saveOperation.savePolicy = .changedKeys // Only update what changed
            saveOperation.qualityOfService = .userInitiated
            
            saveOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        print("✅ Profile saved successfully")
                        
                        // Update UserDefaults for local caching
                        UserDefaults.standard.set(self.editedStateOfMind, forKey: "userStateOfMind_\(self.userIdentifier)")
                        
                        // Call the onSave completion handler
                        self.onSave(
                            self.editedStateOfMind,
                            self.religion,
                            self.showJobTitle,
                            self.showSchool,
                            self.showReligion,
                            self.showHometown,
                            self.gender,
                            self.jobTitle,
                            self.school,
                            self.hometown
                        )
                        
                        // Show success message and reset state
                        withAnimation {
                            self.showSuccessMessage = true
                            self.isSaving = false
                        }
                        
                        // Hide success message after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                self.showSuccessMessage = false
                            }
                        }
                    }
                    
                case .failure(let error):
                    if let ckError = error as? CKError,
                       ckError.code == .serverRecordChanged && retriesLeft > 0 {
                        
                        print("Record changed on server, retrying (\(retriesLeft) retries left)")
                        // Wait a short time before retrying to avoid immediate conflicts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.saveProfileWithRetry(retriesLeft: retriesLeft - 1)
                        }
                    } else {
                        DispatchQueue.main.async {
                            print("Error saving profile: \(error.localizedDescription)")
                            self.errorMessage = "Error saving profile: \(error.localizedDescription)"
                            self.showErrorAlert = true
                            self.isSaving = false
                        }
                    }
                }
            }
            
            database.add(saveOperation)
        }
    }
    
    // Upload a video to CloudKit
    private func uploadVideo(url: URL, title: String) {
        isVideoUploading = true
        
        // Create a unique ID for the video
        let videoId = UUID()
        
        // Create a persistent URL in the Documents directory instead of temp
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDirectory = documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
        
        // Create the directory if needed
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        
        let persistentURL = videosDirectory.appendingPathComponent("\(videoId.uuidString).mp4")
        
        do {
            // Remove any existing file at destination
            if FileManager.default.fileExists(atPath: persistentURL.path) {
                try FileManager.default.removeItem(at: persistentURL)
            }
            
            // Copy the file to a persistent location
            try FileManager.default.copyItem(at: url, to: persistentURL)
            
            // Create a CKAsset from the persistent file URL
            let asset = CKAsset(fileURL: persistentURL)
            
            // Create a new record for the video
            let record = CKRecord(recordType: "UserVideo")
            
            // Set fields explicitly - use identifier instead of firstName
            record["title"] = title.isEmpty ? "My Video" : title
            record["owner"] = userIdentifier  // Use userIdentifier, not firstName
            record["videoFile"] = asset
            record["dateUploaded"] = Date()
            record["views"] = 0
            record["likes"] = 0
            record["videoId"] = videoId.uuidString
            record["localPath"] = "Videos/\(videoId.uuidString).mp4"
            
            print("Saving UserVideo to CloudKit with identifier: \(userIdentifier), title: \(title)")
            let database = CKContainer.default().publicCloudDatabase
            database.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error uploading video: \(error.localizedDescription)")
                        self.errorMessage = "Error uploading video: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    } else {
                        print("✅ Video uploaded successfully")
                        
                        // Add the video to the local list
                        self.videos.append((id: videoId, title: title.isEmpty ? "My Video" : title, url: persistentURL, views: 0))
                        
                        // Reload videos to ensure UI is updated
                        self.loadUserVideos()
                    }
                    
                    self.isVideoUploading = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                print("Error preparing video file: \(error.localizedDescription)")
                self.errorMessage = "Error preparing video: \(error.localizedDescription)"
                self.showErrorAlert = true
                self.isVideoUploading = false
            }
        }
    }
    
    // Delete a video from local storage and CloudKit
    private func deleteVideoDirectly(id: UUID) {
        print("Starting direct deletion for video: \(id)")
        
        // Find the video in local array
        guard let index = videos.firstIndex(where: { $0.id == id }) else {
            print("Cannot find video with ID \(id) in local array")
            return
        }
        
        // Remove from local array immediately
        let deletedVideo = videos.remove(at: index)
        print("Removed video from local array: \(deletedVideo.title)")
        
        // Delete the local file first
        if let url = deletedVideo.url {
            do {
                try FileManager.default.removeItem(at: url)
                print("Deleted local file at: \(url.path)")
            } catch {
                print("Error deleting local file: \(error.localizedDescription)")
            }
        }
        
        // Delete from CloudKit
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "videoId == %@", id.uuidString)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        print("Querying CloudKit for video with ID: \(id.uuidString)")
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("CloudKit query error: \(error.localizedDescription)")
                return
            }
            
            guard let records = records, !records.isEmpty else {
                print("No matching records found in CloudKit")
                return
            }
            
            print("Found \(records.count) records to delete")
            
            // Delete each matching record
            for record in records {
                print("Deleting record: \(record.recordID.recordName)")
                database.delete(withRecordID: record.recordID) { _, error in
                    if let error = error {
                        print("Delete error: \(error.localizedDescription)")
                    } else {
                        print("Record deleted successfully")
                    }
                }
            }
        }
    }
    
    // Play a video
    private func playVideo(url: URL) {
        // Make sure we have a valid URL and file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Video file doesn't exist at path: \(url.path)")
            
            // Show an error to the user
            let alert = UIAlertController(
                title: "Video Unavailable",
                message: "The video file could not be found. It may have been deleted or moved.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Get the UIWindow scene to present the alert
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Find the top-most view controller to present from
                var topController = windowScene.windows.first?.rootViewController
                while let presentedController = topController?.presentedViewController {
                    topController = presentedController
                }
                
                // Present the alert
                topController?.present(alert, animated: true)
            }
            return
        }
        
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        // Get the UIWindow scene properly
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Find the top-most view controller to present from
            var topController = windowScene.windows.first?.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            
            // Dismiss any current presentation first if needed
            if topController?.presentedViewController != nil {
                topController?.dismiss(animated: false) {
                    topController?.present(playerViewController, animated: true) {
                        player.play()
                    }
                }
            } else {
                topController?.present(playerViewController, animated: true) {
                    player.play()
                }
            }
        }
    }
}

// In MainView.swift, rename UserMatch to MainViewUserMatch
struct MainViewUserMatch: Identifiable {
    let id: String // User ID
    let name: String
    let profileImage: UIImage?
    var isOnline: Bool = false
    var lastActiveTime: Date?
}

// Image picker for profile photo
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    var userIdentifier: String
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
                
                // DIRECT SAVE IMMEDIATELY AFTER SELECTION
                saveImageToCloudKit(uiImage, userId: parent.userIdentifier)
            }
            
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        // Direct save function
        func saveImageToCloudKit(_ image: UIImage, userId: String) {
            print("DIRECT SAVE: Starting CloudKit save...")
            
            let database = CKContainer.default().publicCloudDatabase
            let predicate = NSPredicate(format: "identifier == %@", userId)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            
            database.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    print("DIRECT SAVE: Error finding profile: \(error.localizedDescription)")
                    return
                }
                
                guard let record = records?.first else {
                    print("DIRECT SAVE: No profile record found")
                    return
                }
                
                // Save image to temporary file
                if let imageData = image.jpegData(compressionQuality: 0.7) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
                    
                    do {
                        try imageData.write(to: tempURL)
                        let asset = CKAsset(fileURL: tempURL)
                        record["profileImage"] = asset
                        
                        print("DIRECT SAVE: Saving profile image to CloudKit...")
                        database.save(record) { savedRecord, error in
                            if let error = error {
                                print("DIRECT SAVE: Error saving: \(error.localizedDescription)")
                            } else {
                                print("DIRECT SAVE: SUCCESS! Profile image saved to CloudKit")
                            }
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                    } catch {
                        print("DIRECT SAVE: Error preparing image data: \(error)")
                    }
                }
            }
        }
    }
}

// Image cropper for circular profile photos
struct ImageCropper: UIViewControllerRepresentable {
    let image: UIImage
    let completion: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> CropViewController {
        let cropViewController = CropViewController(croppingStyle: .circular, image: image)
        cropViewController.delegate = context.coordinator
        cropViewController.aspectRatioPreset = .presetSquare
        cropViewController.aspectRatioLockEnabled = true
        cropViewController.toolbarPosition = .bottom
        
        // Make sure we're handling memory properly
        context.coordinator.parent = self
        
        return cropViewController
    }
    
    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {
        // Make sure we update the coordinator's reference if needed
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CropViewControllerDelegate {
        var parent: ImageCropper
        
        init(_ parent: ImageCropper) {
            self.parent = parent
            super.init()
        }
        
        func cropViewController(_ cropViewController: CropViewController, didCropToCircularImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
            // Call completion FIRST before dismissal
            parent.completion(image)
            
            // Then dismiss
            cropViewController.dismiss(animated: true)
        }
        
        func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
            if cancelled {
                cropViewController.dismiss(animated: true)
            }
        }
    }
}

// Custom crop view controller
class CropViewController: UIViewController {
    var croppingStyle: CroppingStyle
    var delegate: CropViewControllerDelegate?
    var aspectRatioPreset: AspectRatioPreset = .presetSquare
    var aspectRatioLockEnabled: Bool = true
    var toolbarPosition: ToolbarPosition = .bottom
    var onCancel: (() -> Void)?
    
    @objc private func cancelTapped() {
        delegate?.cropViewController(self, didFinishCancelled: true)
        dismiss(animated: true)
    }
    
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let cropAreaView = UIView()
    private let originalImage: UIImage
    
    enum CroppingStyle {
        case circular
        case rectangular  // Changed from "default"
    }
    
    enum AspectRatioPreset {
        case presetSquare
    }
    
    enum ToolbarPosition {
        case bottom
        case top
    }
    
    init(croppingStyle: CroppingStyle, image: UIImage) {
        self.croppingStyle = croppingStyle
        self.originalImage = image
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Set up scroll view for zooming
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set up image view
        imageView.contentMode = .scaleAspectFit
        imageView.image = originalImage
        scrollView.addSubview(imageView)
        
        // Set up crop overlay
        cropAreaView.layer.borderColor = UIColor.white.cgColor
        cropAreaView.layer.borderWidth = 2
        cropAreaView.isUserInteractionEnabled = false
        view.addSubview(cropAreaView)
        
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Pinch to zoom, drag to position"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 14)
        view.addSubview(instructionLabel)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add buttons
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        
        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, doneButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .equalSpacing
        buttonStack.spacing = 50
        
        view.addSubview(buttonStack)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Layout constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Set up scroll view content size
        let imageSize = originalImage.size
        let scrollViewSize = scrollView.bounds.size
        
        // Calculate the scale to fit the image to the scroll view
        let widthScale = scrollViewSize.width / imageSize.width
        let heightScale = scrollViewSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
        
        // Set the image view's frame to fit the scroll view
        imageView.frame = CGRect(x: 0, y: 0, width: imageSize.width * minScale, height: imageSize.height * minScale)
        
        // Center the image if needed
        if imageView.frame.width < scrollViewSize.width {
            imageView.frame.origin.x = (scrollViewSize.width - imageView.frame.width) / 2
        }
        if imageView.frame.height < scrollViewSize.height {
            imageView.frame.origin.y = (scrollViewSize.height - imageView.frame.height) / 2
        }
        
        scrollView.contentSize = imageView.frame.size
        
        // Update crop area to be square
        let cropSize = min(scrollViewSize.width, scrollViewSize.height) * 0.8
        cropAreaView.frame = CGRect(
            x: (view.bounds.width - cropSize) / 2,
            y: (scrollView.bounds.height - cropSize) / 2,
            width: cropSize,
            height: cropSize
        )
        
        // Make it circular for circular style
        if croppingStyle == .circular {
            cropAreaView.layer.cornerRadius = cropSize / 2
            cropAreaView.clipsToBounds = true
        } else {
            cropAreaView.layer.cornerRadius = 0
        }
    }
    
    @objc private func doneTapped() {
        // Calculate the crop rect in the image coordinate space
        let scrollViewFrame = scrollView.frame
        let cropFrame = cropAreaView.frame
        
        // Get the visible rect of the image in the scroll view
        let visibleRect = CGRect(
            x: (scrollView.contentOffset.x + cropFrame.origin.x - scrollView.frame.origin.x) / scrollView.zoomScale,
            y: (scrollView.contentOffset.y + cropFrame.origin.y - scrollView.frame.origin.y) / scrollView.zoomScale,
            width: cropFrame.width / scrollView.zoomScale,
            height: cropFrame.height / scrollView.zoomScale
        )
        
        // Make sure we stay within the image bounds
        let imageSize = originalImage.size
        let cropX = max(0, min(visibleRect.origin.x, imageSize.width - visibleRect.width))
        let cropY = max(0, min(visibleRect.origin.y, imageSize.height - visibleRect.height))
        let cropWidth = min(visibleRect.width, imageSize.width - cropX)
        let cropHeight = min(visibleRect.height, imageSize.height - cropY)
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        // Create the cropped image
        if let cgImage = originalImage.cgImage?.cropping(to: cropRect) {
            let croppedImage = UIImage(cgImage: cgImage)
            
            if croppingStyle == .circular {
                let circularImage = createCircularImage(from: croppedImage)
                // IMPORTANT: Don't dismiss here, just call the delegate
                delegate?.cropViewController(self, didCropToCircularImage: circularImage, withRect: cropRect, angle: 0)
            } else {
                delegate?.cropViewController(self, didCropToImage: croppedImage, withRect: cropRect, angle: 0)
            }
        }
        
        // Add this line instead of relying on the delegate to handle dismissal
        self.dismiss(animated: true)
    }
    
    private func createCircularImage(from image: UIImage) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.addEllipse(in: rect)
            ctx.cgContext.clip()
            
            image.draw(in: rect)
        }
    }
}

extension CropViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Keep the image centered in the scroll view when zooming
        let imageViewSize = imageView.frame.size
        let scrollViewSize = scrollView.bounds.size
        
        let verticalPadding = imageViewSize.height < scrollViewSize.height ? (scrollViewSize.height - imageViewSize.height) / 2 : 0
        let horizontalPadding = imageViewSize.width < scrollViewSize.width ? (scrollViewSize.width - imageViewSize.width) / 2 : 0
        
        scrollView.contentInset = UIEdgeInsets(top: verticalPadding, left: horizontalPadding, bottom: verticalPadding, right: horizontalPadding)
    }
}

protocol CropViewControllerDelegate: AnyObject {
    func cropViewController(_ cropViewController: CropViewController, didCropToCircularImage image: UIImage, withRect cropRect: CGRect, angle: Int)
    func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int)
    func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool)
}

// Default implementation
extension CropViewControllerDelegate {
    func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        // Default implementation does nothing
    }
    
    func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
        // Default implementation does nothing
    }
}

// Video thumbnail view
// Improved VideoThumbnailView - replace the current implementation
// Replace the current VideoThumbnailView implementation with this enhanced version:
struct VideoThumbnailView: UIViewRepresentable {
    let videoURL: URL
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .darkGray
        
        // Create image view for thumbnail
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .darkGray
        
        // Play button overlay
        let playButton = UIImageView(image: UIImage(systemName: "play.circle.fill"))
        playButton.tintColor = .white
        playButton.contentMode = .scaleAspectFit
        
        container.addSubview(imageView)
        container.addSubview(playButton)
        
        // Auto layout
        imageView.translatesAutoresizingMaskIntoConstraints = false
        playButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            playButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Generate thumbnail using a more reliable method
        generateReliableThumbnail(for: videoURL, imageView: imageView)
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // If we don't have a thumbnail yet, try again
        if let imageView = uiView.subviews.first as? UIImageView, imageView.image == nil {
            generateReliableThumbnail(for: videoURL, imageView: imageView)
        }
    }
    
    private func generateReliableThumbnail(for url: URL, imageView: UIImageView) {
        print("Attempting to generate thumbnail using reliable method for: \(url.path)")
        
        // First verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Video file not found: \(url.path)")
            DispatchQueue.main.async {
                imageView.image = UIImage(systemName: "film")
                imageView.contentMode = .center
                imageView.tintColor = .white
            }
            return
        }
        
        // Create a temp copy for better access
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("thumb_\(UUID().uuidString).mp4")
        
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            let asset = AVAsset(url: tempURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            // Try multiple time points
            let timePoints = [
                CMTime.zero,
                CMTime(seconds: 0.5, preferredTimescale: 600),
                CMTime(seconds: 1.0, preferredTimescale: 600)
            ]
            
            DispatchQueue.global().async {
                var succeeded = false
                
                // Try each time point until one works
                for time in timePoints {
                    if succeeded { break }
                    
                    do {
                        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                        let uiImage = UIImage(cgImage: cgImage)
                        
                        DispatchQueue.main.async {
                            imageView.image = uiImage
                        }
                        succeeded = true
                    } catch {
                        print("Failed at time \(time.seconds): \(error)")
                    }
                }
                
                // If all time points failed, use placeholder
                if !succeeded {
                    DispatchQueue.main.async {
                        imageView.image = UIImage(systemName: "film")
                        imageView.contentMode = .center
                        imageView.tintColor = .white
                    }
                }
                
                // Clean up temp file when done
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("Error creating temp file: \(error)")
            DispatchQueue.main.async {
                imageView.image = UIImage(systemName: "film")
                imageView.contentMode = .center
                imageView.tintColor = .white
            }
        }
    }
}

// Add this extension to UIImage
extension UIImage {
    var thumbnail: UIImage? {
        get {
            let size = CGSize(width: 120, height: 120)
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            defer { UIGraphicsEndImageContext() }
            
            draw(in: CGRect(origin: .zero, size: size))
            return UIGraphicsGetImageFromCurrentImageContext()
        }
    }
}

// Also fix video playback in UnifiedProfileView:
private func playVideo(url: URL) {
    print("Playing video at: \(url.path)")
    
    // Create temp copy to ensure playback works
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("play_\(UUID().uuidString).mp4")
    
    do {
        // Remove any existing file at destination
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        
        // Copy to temp location for secure playback
        try FileManager.default.copyItem(at: url, to: tempURL)
        
        // Create player and view controller
        let player = AVPlayer(url: tempURL)
        let playerController = AVPlayerViewController()
        playerController.player = player
        
        // Find the top view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            
            // Present the player
            topController?.present(playerController, animated: true) {
                player.play()
                
                // Set up cleanup when done
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                      object: player.currentItem,
                                                      queue: .main) { _ in
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
    } catch {
        print("Error preparing video for playback: \(error.localizedDescription)")
        
        // Show an error alert to the user
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let topController = window.rootViewController {
            
            let alert = UIAlertController(
                title: "Playback Error",
                message: "The video couldn't be played. Please try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            topController.present(alert, animated: true)
        }
    }
}

struct ReligionSelectionView: View {
    @Binding var selectedReligion: String
    @Environment(\.presentationMode) var presentationMode
    
    // Create an explicit callback function
    var onSelect: (String) -> Void
    
    let religions = [
        "Agnostic", "Atheist", "Buddhist", "Catholic",
        "Christian", "Hindu", "Jewish", "Muslim",
        "Sikh", "Spiritual", "Other", "Prefer not to say"
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            List {
                ForEach(religions, id: \.self) { religion in
                    Button {
                        // Call the callback with the selected religion
                        onSelect(religion)
                        
                        // Dismiss the view
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Text(religion)
                                .foregroundColor(.black)
                            Spacer()
                            if selectedReligion == religion {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("Religious Beliefs")
    }
}

struct VideoCaptureView: UIViewControllerRepresentable {
    let isCamera: Bool
    let onComplete: (URL?, String) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    // New state for audio track
    @State private var selectedAudioTrack: AudioTrack?
    @State private var showAudioBrowser = false
    
    func makeUIViewController(context: Context) -> UIViewController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.mediaTypes = ["public.movie"]
        picker.sourceType = isCamera ? .camera : .photoLibrary
        picker.videoQuality = .typeHigh
        
        if isCamera {
            picker.cameraCaptureMode = .video
            picker.videoMaximumDuration = 30 // 30 seconds max
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoCaptureView
        
        init(_ parent: VideoCaptureView) {
            self.parent = parent
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                // Present video editor with audio options
                picker.dismiss(animated: true) {
                    let videoEditor = EnhancedVideoEditorView(
                        videoURL: videoURL,
                        onComplete: self.parent.onComplete
                    )
                    
                    let hostingController = UIHostingController(rootView: videoEditor)
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController {
                            topVC = presented
                        }
                        
                        topVC.present(hostingController, animated: true)
                    }
                }
            } else {
                parent.onComplete(nil, "")
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onComplete(nil, "")
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct VideoEditorView: UIViewControllerRepresentable {
    let videoURL: URL
    let onComplete: (URL?, String) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = VideoEditorViewController(videoURL: videoURL)
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VideoEditorDelegate {
        let parent: VideoEditorView
        
        init(_ parent: VideoEditorView) {
            self.parent = parent
        }
        
        func videoEditorDidFinish(with url: URL?, title: String) {
            parent.onComplete(url, title)
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

protocol VideoEditorDelegate: AnyObject {
    func videoEditorDidFinish(with url: URL?, title: String)
}

class VideoEditorViewController: UIViewController {
    weak var delegate: VideoEditorDelegate?
    private let videoURL: URL
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var titleTextField: UITextField!
    private var textOverlay: UILabel!
    private var outputURL: URL?
    private var isProcessing = false
    
    // Video editing components
    private var asset: AVAsset!
    private var composition: AVMutableComposition!
    private var videoComposition: AVMutableVideoComposition!
    private var exportSession: AVAssetExportSession?
    
    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        self.asset = AVAsset(url: videoURL)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPlayer()
        prepareComposition()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Video player container
        let videoContainer = UIView()
        videoContainer.backgroundColor = .black
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoContainer)
        
        // Text overlay will be added on top of video
        textOverlay = UILabel()
        textOverlay.text = ""
        textOverlay.textAlignment = .center
        textOverlay.textColor = .white
        textOverlay.font = UIFont.boldSystemFont(ofSize: 24)
        textOverlay.numberOfLines = 0
        textOverlay.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(textOverlay)
        
        // Controls container
        let controlsContainer = UIView()
        controlsContainer.backgroundColor = UIColor.darkGray.withAlphaComponent(0.8)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)
        
        // Title input
        titleTextField = UITextField()
        titleTextField.placeholder = "Enter video title"
        titleTextField.textColor = .white
        titleTextField.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        titleTextField.layer.cornerRadius = 8
        titleTextField.layer.borderWidth = 1
        titleTextField.layer.borderColor = UIColor.white.cgColor
        titleTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        titleTextField.leftViewMode = .always
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(titleTextField)
        
        // Text overlay input
        let overlayTextField = UITextField()
        overlayTextField.placeholder = "Add text overlay"
        overlayTextField.textColor = .white
        overlayTextField.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlayTextField.layer.cornerRadius = 8
        overlayTextField.layer.borderWidth = 1
        overlayTextField.layer.borderColor = UIColor.white.cgColor
        overlayTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        overlayTextField.leftViewMode = .always
        overlayTextField.addTarget(self, action: #selector(updateTextOverlay), for: .editingChanged)
        overlayTextField.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(overlayTextField)
        
        // Color picker for text
        let colorWell = UIColorWell()
        colorWell.supportsAlpha = true
        colorWell.selectedColor = .white
        colorWell.addTarget(self, action: #selector(textColorChanged), for: .valueChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(colorWell)
        
        // Music button
        let musicButton = UIButton(type: .system)
        musicButton.setTitle("Add Music", for: .normal)
        musicButton.setTitleColor(.white, for: .normal)
        musicButton.backgroundColor = UIColor.systemBlue
        musicButton.layer.cornerRadius = 8
        musicButton.addTarget(self, action: #selector(addMusic), for: .touchUpInside)
        musicButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(musicButton)
        
        // Save button
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.systemGreen
        saveButton.layer.cornerRadius = 8
        saveButton.addTarget(self, action: #selector(saveVideo), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(saveButton)
        
        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.systemRed
        cancelButton.layer.cornerRadius = 8
        cancelButton.addTarget(self, action: #selector(cancelEditing), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(cancelButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Video container
            videoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),
            
            // Text overlay
            textOverlay.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            textOverlay.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            textOverlay.leadingAnchor.constraint(greaterThanOrEqualTo: videoContainer.leadingAnchor, constant: 20),
            textOverlay.trailingAnchor.constraint(lessThanOrEqualTo: videoContainer.trailingAnchor, constant: -20),
            
            // Controls container
            controlsContainer.topAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Title field
            titleTextField.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 20),
            titleTextField.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 20),
            titleTextField.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -20),
            titleTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Text overlay
            overlayTextField.topAnchor.constraint(equalTo: titleTextField.bottomAnchor, constant: 20),
            overlayTextField.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 20),
            overlayTextField.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -70),
            overlayTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Color picker
            colorWell.centerYAnchor.constraint(equalTo: overlayTextField.centerYAnchor),
            colorWell.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -20),
            colorWell.widthAnchor.constraint(equalToConstant: 40),
            colorWell.heightAnchor.constraint(equalToConstant: 40),
            
            // Music button
            musicButton.topAnchor.constraint(equalTo: overlayTextField.bottomAnchor, constant: 20),
            musicButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 20),
            musicButton.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -20),
            musicButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -30),
            cancelButton.widthAnchor.constraint(equalTo: controlsContainer.widthAnchor, multiplier: 0.45),
            cancelButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Save button
            saveButton.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -30),
            saveButton.widthAnchor.constraint(equalTo: controlsContainer.widthAnchor, multiplier: 0.45),
            saveButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        
        if let videoContainer = view.subviews.first {
            playerLayer?.frame = videoContainer.bounds
            videoContainer.layer.addSublayer(playerLayer!)
            
            // Add notification to restart video when it ends
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
            
            // Start playing
            player?.play()
        }
    }
    
    private func prepareComposition() {
        // Create a composition
        composition = AVMutableComposition()
        
        // Get video track
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return }
        
        // Get audio track if available
        let audioTracks = asset.tracks(withMediaType: .audio)
        let audioTrack = audioTracks.first
        
        // Create composition tracks
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // Get the timeRange of the video
        let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        do {
            // Add video track to composition
            try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            
            // Add audio track to composition if available
            if let audioTrack = audioTrack {
                let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }
            
            // Setup video composition for adding text overlay
            videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: videoTrack.naturalSize.width, height: videoTrack.naturalSize.height)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
            
            // Create the instruction
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            
            // Create the layer instruction
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            
        } catch {
            print("Error creating composition: \(error)")
        }
    }
    
    @objc private func updateTextOverlay(_ sender: UITextField) {
        textOverlay.text = sender.text
    }
    
    @objc private func textColorChanged(_ sender: UIColorWell) {
        textOverlay.textColor = sender.selectedColor ?? .white
    }
    
    @objc private func addMusic() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    @objc private func playerDidFinishPlaying() {
            player?.seek(to: CMTime.zero)
            player?.play()
        }
    
    @objc private func saveVideo() {
        guard !isProcessing else { return }
        isProcessing = true
        
        // Create loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.center = view.center
        view.addSubview(activityIndicator)
        activityIndicator.startAnimating()
        
        // Create a unique output URL in the temporary directory
        let outputFileName = UUID().uuidString + ".mp4"
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName)
        
        // If there was a previous temp file, remove it
        if let previousURL = outputURL, FileManager.default.fileExists(atPath: previousURL.path) {
            try? FileManager.default.removeItem(at: previousURL)
        }
        
        // Remove any existing file at the output path
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            activityIndicator.stopAnimating()
            activityIndicator.removeFromSuperview()
            isProcessing = false
            return
        }
        
        exportSession.outputURL = tmpURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        // Apply text overlay if there is text
        if let overlayText = textOverlay.text, !overlayText.isEmpty {
            applyTextOverlay(to: exportSession, text: overlayText, color: textOverlay.textColor)
        }
        
        // Export the video
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                activityIndicator.stopAnimating()
                activityIndicator.removeFromSuperview()
                self.isProcessing = false
                
                switch exportSession.status {
                case .completed:
                    self.outputURL = tmpURL
                    self.delegate?.videoEditorDidFinish(with: tmpURL, title: self.titleTextField.text ?? "My Video")
                case .failed, .cancelled:
                    print("Export failed: \(String(describing: exportSession.error))")
                    let alert = UIAlertController(title: "Export Failed", message: "There was an error processing your video.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                default:
                    break
                }
            }
        }
    }
    
    private func applyTextOverlay(to exportSession: AVAssetExportSession, text: String, color: UIColor) {
        guard let videoTrack = composition.tracks(withMediaType: .video).first else { return }
        
        // Get video dimensions
        let videoSize = videoTrack.naturalSize
        
        // Create an AVVideoComposition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Create a composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        // Create a layer instruction using the video track
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Create a CATextLayer for the text overlay
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = UIFont.boldSystemFont(ofSize: 36)
        textLayer.fontSize = 36
        textLayer.foregroundColor = color.cgColor
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .none
        
        // Size the text layer to fit the text
        let textSize = (text as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: 36)])
        textLayer.frame = CGRect(x: (videoSize.width - textSize.width) / 2,
                                 y: (videoSize.height - textSize.height) / 2,
                                 width: textSize.width,
                                 height: textSize.height)
        
        // Create a parent layer that will hold the video and text layers
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        
        // Create a video layer
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        
        // Add the video and text layers to the parent layer
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(textLayer)
        
        // Set the layers on the video composition
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        
        // Set the video composition on the export session
        exportSession.videoComposition = videoComposition
    }
    
    @objc private func cancelEditing() {
        // Just dismiss directly without trying to call a non-existent delegate method
        delegate?.videoEditorDidFinish(with: nil, title: "")
        dismiss(animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let videoContainer = view.subviews.first {
            playerLayer?.frame = videoContainer.bounds
        }
    }
}

extension VideoEditorViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let audioURL = urls.first else { return }
        
        // Add the audio track to the composition
        do {
            let audioAsset = AVAsset(url: audioURL)
            let audioTrack = audioAsset.tracks(withMediaType: .audio).first
            
            // Make sure we have an audio track
            guard let audioTrack = audioTrack else { return }
            
            // Remove existing audio tracks if any
            for track in composition.tracks(withMediaType: .audio) {
                composition.removeTrack(track)
            }
            
            // Add the new audio track
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            // Calculate the duration to use (minimum of video and audio)
            let videoDuration = composition.duration
            let audioDuration = audioAsset.duration
            let timeRange = CMTimeRange(start: .zero, duration: min(videoDuration, audioDuration))
            
            try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            
            // Show success indication
            let alert = UIAlertController(title: "Music Added", message: "The selected music has been added to your video.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            
        } catch {
            print("Error adding audio: \(error)")
            
            // Show error
            let alert = UIAlertController(title: "Error", message: "Could not add the music to your video.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

struct VideoFeedView: View {
    let video: (userId: String, videoId: String, url: URL, title: String, views: Int)
    let matchedUser: CKRecord
    let onClose: () -> Void
    let onLike: () -> Void
    let onNext: () -> Void
    
    @State private var isPlaying = true
    @State private var hasLiked = false
    @State private var showUserProfile = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Video player
            if isPlaying {
                VideoPlayerView(url: video.url, isPlaying: $isPlaying)
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Show thumbnail when paused
                VideoThumbnailView(videoURL: video.url)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        Button(action: {
                            isPlaying = true
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            }
            
            // Overlay controls
            VStack {
                // Top bar
                HStack {
                    Button(action: {
                        showUserProfile = true
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let name = matchedUser["firstName"] as? String {
                                Text(name)
                                    .font(.appHeadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            Text(video.title)
                                .font(.appCaption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                            .foregroundColor(.white)
                        Text("\(video.views)")
                            .foregroundColor(.white)
                            .font(.appCaption)
                    }
                    
                    Button(action: {
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Bottom controls
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // Like button
                        Button(action: {
                            if !hasLiked {
                                hasLiked = true
                                onLike()
                            }
                        }) {
                            Image(systemName: hasLiked ? "heart.fill" : "heart")
                                .font(.title)
                                .foregroundColor(hasLiked ? .red : .white)
                        }
                        
                        // Pause/play
                        Button(action: {
                            isPlaying.toggle()
                        }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    // Next button
                    Button(action: {
                        onNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .sheet(isPresented: $showUserProfile) {
            ProfileDetailView(userRecord: matchedUser)
        }
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        // Set up observation of playback status
        context.coordinator.player = player
        context.coordinator.setupObservers()
        
        // Start playing automatically
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if isPlaying {
            uiViewController.player?.play()
        } else {
            uiViewController.player?.pause()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: VideoPlayerView
        var player: AVPlayer?
        private var timeObserver: Any?
        
        init(_ parent: VideoPlayerView) {
            self.parent = parent
            super.init()
        }
        
        func setupObservers() {
            // Add observer for video end
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
            
            // Add time observer to loop video
            timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: DispatchQueue.main) { [weak self] _ in
                guard let self = self, let player = self.player else { return }
                
                if let currentItem = player.currentItem {
                    let duration = currentItem.duration
                    if player.currentTime() >= duration {
                        player.seek(to: .zero)
                        player.play()
                    }
                }
            }
        }
        
        @objc func playerDidFinishPlaying() {
                   // Loop the video
                   player?.seek(to: .zero)
                   player?.play()
               }
        
        deinit {
            if let timeObserver = timeObserver, let player = player {
                player.removeTimeObserver(timeObserver)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct ProfileDetailView: View {
    let userRecord: CKRecord
    @State private var profileImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with close button
                    HStack {
                        Text("User Profile")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom)
                    
                    // Basic info
                    if let name = userRecord["firstName"] as? String {
                        HStack {
                            // Profile image
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 36))
                                    )
                            }
                            
                            VStack(alignment: .leading) {
                                Text(name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                if let gender = userRecord["gender"] as? String {
                                    Text(gender)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .background(Color.gray)
                    
                    // Social Media
                    Group {
                        Text("Social Media")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.bottom, 5)
                        
                        if let instagram = userRecord["instagramHandle"] as? String, !instagram.isEmpty {
                            HStack {
                                Text("Instagram:")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("@\(instagram)")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 5)
                        } else {
                            Text("Instagram: Not set")
                                .foregroundColor(.gray)
                                .padding(.vertical, 5)
                        }
                        
                        if let twitter = userRecord["twitterHandle"] as? String, !twitter.isEmpty {
                            HStack {
                                Text("Twitter/X:")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("@\(twitter)")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 5)
                        } else {
                            Text("Twitter/X: Not set")
                                .foregroundColor(.gray)
                                .padding(.vertical, 5)
                        }
                    }
                    
                    Divider()
                        .background(Color.gray)
                    
                    // State of Mind
                    if let stateOfMind = userRecord["stateOfMind"] as? String, !stateOfMind.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Current State of Mind")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.bottom, 5)
                            
                            Text(stateOfMind)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            // Load profile image
            if let imageAsset = userRecord["profileImage"] as? CKAsset,
               let imageUrl = imageAsset.fileURL {
                
                do {
                    let imageData = try Data(contentsOf: imageUrl)
                    self.profileImage = UIImage(data: imageData)
                } catch {
                    print("Error loading profile image: \(error)")
                }
            }
        }
    }
}

// Add this extension if needed:
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// Add this class at the app level (outside any struct)
class ProfileViewHelper {
    static let shared = ProfileViewHelper()
    
    func showUserProfile(userId: String, from viewController: UIViewController? = nil) {
        print("Showing profile for user: \(userId)")
        
        // Create a loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.startAnimating()
        
        // Find top controller if not provided
        var topVC = viewController
        if topVC == nil {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                topVC = window.rootViewController
                while let presented = topVC?.presentedViewController {
                    topVC = presented
                }
            }
        }
        
        // Add loading indicator
        if let topVC = topVC {
            activityIndicator.center = topVC.view.center
            topVC.view.addSubview(activityIndicator)
        }
        
        // Fetch user profile
        fetchUserProfile(for: userId) { record in
            // Remove activity indicator
            DispatchQueue.main.async {
                activityIndicator.removeFromSuperview()
            }
            
            if let record = record {
                // Create profile details
                let details = self.createProfileDetailsFromRecord(record)
                
                DispatchQueue.main.async {
                    // Create profile view
                    let profileView = VideoLoadingProfileView(
                        userDetails: details,
                        userId: userId,
                        onClose: {
                            // Dismiss the controller
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootVC = window.rootViewController {
                                
                                var topVC = rootVC
                                while let presented = topVC.presentedViewController {
                                    topVC = presented
                                }
                                
                                // Only dismiss if it's not the main controller
                                if topVC != rootVC {
                                    topVC.dismiss(animated: true)
                                }
                            }
                        },
                        loadVideos: self.loadVideosForProfileView
                    )
                    
                    // Present in a new controller
                    let hostingController = UIHostingController(rootView: profileView)
                    hostingController.modalPresentationStyle = .overFullScreen
                    hostingController.view.backgroundColor = UIColor.clear
                    
                    // Present over current top controller
                    if let topVC = topVC {
                        topVC.present(hostingController, animated: true)
                    }
                }
            } else {
                print("Error: Could not fetch profile record for user \(userId)")
                
                // Show error alert
                DispatchQueue.main.async {
                    if let topVC = topVC {
                        let alert = UIAlertController(
                            title: "Profile Unavailable",
                            message: "Could not load this user's profile. Please try again later.",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        topVC.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func fetchUserProfile(for userId: String, completion: @escaping (CKRecord?) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                completion(records?.first)
            }
        }
    }
    
    private func createProfileDetailsFromRecord(_ record: CKRecord) -> UnifiedProfileDetails {
        var profileImage: UIImage? = nil
        
        // Try to get profile image
        if let imageAsset = record["profileImage"] as? CKAsset,
           let imageUrl = imageAsset.fileURL,
           let imageData = try? Data(contentsOf: imageUrl) {
            profileImage = UIImage(data: imageData)
        }
        
        // Get distance if location is available
        var distance: Double? = nil
        if let location = record["location"] as? CLLocation,
           let myLocation = CLLocationManager().location {
            let distanceMeters = myLocation.distance(from: location)
            distance = distanceMeters / 1609.34 // Convert to miles
        }
        
        // Create the profile details
        return UnifiedProfileDetails(
            id: record["identifier"] as? String ?? "",
            name: record["firstName"] as? String ?? "User",
            image: profileImage,
            gender: record["gender"] as? String ?? "Not specified",
            stateOfMind: record["stateOfMind"] as? String ?? "",
            religion: record["religion"] as? String ?? "",
            showReligion: record["showReligion"] as? Int == 1,
            jobTitle: record["jobTitle"] as? String ?? "",
            showJobTitle: record["showJobTitle"] as? Int == 1,
            school: record["school"] as? String ?? "",
            showSchool: record["showSchool"] as? Int == 1,
            hometown: record["hometown"] as? String ?? "",
            showHometown: record["showHometown"] as? Int == 1,
            instagramHandle: record["instagramHandle"] as? String ?? "",
            twitterHandle: record["twitterHandle"] as? String ?? "",
            likeCount: record["likeCount"] as? Int ?? 0,
            distanceMiles: distance,
            videos: [] // Videos will be loaded separately
        )
    }
    
    func loadVideosForProfileView(userId: String, completion: @escaping ([(id: UUID, title: String, url: URL?, views: Int)]) -> Void) {
        print("🎬 Loading videos for user profile: \(userId)")
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "owner == %@", userId)
        let query = CKQuery(recordType: "UserVideo", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("❌ Error loading videos: \(error.localizedDescription)")
                completion([])
                return
            }
            
            var videos: [(id: UUID, title: String, url: URL?, views: Int)] = []
            let group = DispatchGroup()
            
            if let videoRecords = records, !videoRecords.isEmpty {
                print("✅ Found \(videoRecords.count) videos for user \(userId)")
                
                for record in videoRecords {
                    group.enter()
                    
                    let title = record["title"] as? String ?? "Video"
                    let views = record["views"] as? Int ?? 0
                    let videoIdString = record["videoId"] as? String ?? UUID().uuidString
                    let videoId = UUID(uuidString: videoIdString) ?? UUID()
                    
                    if let videoAsset = record["videoFile"] as? CKAsset, let assetURL = videoAsset.fileURL {
                        // Create a local copy of the video for reliable access
                        if FileManager.default.fileExists(atPath: assetURL.path) {
                            // Create a unique file in the temp directory
                            let uniqueFileName = "\(UUID().uuidString)_\(videoIdString).mp4"
                            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFileName)
                            
                            do {
                                // Remove any existing file at the destination
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    try FileManager.default.removeItem(at: localURL)
                                }
                                
                                // Copy the file
                                try FileManager.default.copyItem(at: assetURL, to: localURL)
                                print("Added video: \(title)")
                                
                                // Verify the file was properly copied
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    do {
                                        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                                        if let fileSize = attributes[FileAttributeKey.size] as? NSNumber, fileSize.intValue > 100 {
                                            print("✅ Successfully copied video (\(fileSize.intValue) bytes): \(title)")
                                            videos.append((id: videoId, title: title, url: localURL, views: views))
                                        } else {
                                            print("⚠️ Video file appears too small or size attribute missing")
                                        }
                                    } catch {
                                        print("❌ Error checking file attributes: \(error.localizedDescription)")
                                    }
                                } else {
                                    print("⚠️ Copy failed - file doesn't exist at destination")
                                }
                            } catch {
                                print("❌ Error copying video file: \(error.localizedDescription)")
                            }
                        } else {
                            print("⚠️ Source video asset file not found: \(assetURL.path)")
                        }
                    }
                    
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    print("✅ Completed loading \(videos.count) videos")
                    completion(videos)
                }
            } else {
                print("No videos found for user \(userId)")
                completion([])
            }
        }
    }
}

// Make sure this is defined at the file level (outside any struct)
class TwitterPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    
    init(window: UIWindow) {
        self.window = window
        super.init()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window
    }
}

// Either remove it entirely or modify it to work with the new approach
class CameraPositionManager {
    static let shared = CameraPositionManager()
    
    private var isProcessingToggle = false
    
    init() {
        // Remove or update this notification handler to align with the new approach
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraToggle),
            name: NSNotification.Name("ToggleCameraPosition"),
            object: nil
        )
    }
    
    // Update this method to use the reconnect approach rather than trying to modify the existing session
    @objc private func handleCameraToggle() {
        // Implementation should be updated or removed
    }
}
