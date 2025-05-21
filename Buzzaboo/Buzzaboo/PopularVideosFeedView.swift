import SwiftUI
import CloudKit
import AVKit
import SwiftUI
import AVFoundation

private let safeTop =
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }
        .first ?? 0

private let safeBottom =
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom }
        .first ?? 0

struct PopularVideosFeedView: View {
    let userIdentifier: String
    @State private var popularVideos: [(userId: String, videoId: String, url: URL, title: String, views: Int)] = []
    @State private var currentVideoIndex: Int = 0
    @State private var isLoading = true
    @State private var userRecords: [String: CKRecord] = [:]
    @State private var hasLikedVideos: Set<String> = []
    @State private var dragOffset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var justUploadedVideoId: String? = nil
    
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isLoading {
                PulsingLoaderView()
            } else if popularVideos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("No videos available")
                        .font(.appHeadline)
                        .foregroundColor(.white)
                    
                    Text("Try again later or upload your own!")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                        
                    Button(action: {
                        isRefreshing = true
                        fetchPopularVideos()
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
            } else {
                // Video player with swipe gesture
                // In PopularVideosFeedView, instead of having just one video showing at a time,
                // we need to stack the current video and the next one
                GeometryReader { geometry in
                    ZStack {
                        // Current video
                        if currentVideoIndex < popularVideos.count,
                           let userRecord = userRecords[popularVideos[currentVideoIndex].userId] {
                            
                            VideoFeedItem(
                                video: popularVideos[currentVideoIndex],
                                userRecord: userRecord,
                                hasLiked: hasLikedVideos.contains(popularVideos[currentVideoIndex].videoId),
                                onLike: { likeVideo(popularVideos[currentVideoIndex].videoId,
                                                    ownerId: popularVideos[currentVideoIndex].userId) },
                                onUnlike: { unlikeVideo(popularVideos[currentVideoIndex].videoId,
                                                        ownerId: popularVideos[currentVideoIndex].userId) },
                                onUserProfile: showUserProfile,
                                isActive: true
                            )
                            .id("\(popularVideos[currentVideoIndex].videoId)_\(popularVideos[currentVideoIndex].userId)")
                            .frame(width: UIScreen.main.bounds.width,
                                   height: UIScreen.main.bounds.height)
                            .edgesIgnoringSafeArea(.all)
                            .clipped()
                            .ignoresSafeArea()
                            .offset(y: dragOffset)
                        }
                        
                        // Next video (positioned below current video)
                        if currentVideoIndex + 1 < popularVideos.count,
                           let nextUserRecord = userRecords[popularVideos[currentVideoIndex + 1].userId] {
                            
                            VideoFeedItem(
                                video: popularVideos[currentVideoIndex + 1],
                                userRecord: nextUserRecord,
                                hasLiked: hasLikedVideos.contains(popularVideos[currentVideoIndex + 1].videoId),
                                onLike: {
                                    likeVideo(popularVideos[currentVideoIndex + 1].videoId,
                                              ownerId: popularVideos[currentVideoIndex + 1].userId)
                                },
                                onUnlike: {
                                    unlikeVideo(popularVideos[currentVideoIndex + 1].videoId,
                                                ownerId: popularVideos[currentVideoIndex + 1].userId)
                                },
                                onUserProfile: { userId in
                                    showUserProfile(userId: userId)
                                },
                                isActive: false
                            )
                            .id("\(popularVideos[currentVideoIndex + 1].videoId)_\(popularVideos[currentVideoIndex + 1].userId)")
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height)
                            .ignoresSafeArea()
                            .offset(y: geometry.size.height + dragOffset)
                        }
                        
                        // Previous video (positioned above current video)
                        if currentVideoIndex > 0,
                           let prevUserRecord = userRecords[popularVideos[currentVideoIndex - 1].userId] {
                            
                            VideoFeedItem(
                                video: popularVideos[currentVideoIndex - 1],
                                userRecord: prevUserRecord,
                                hasLiked: hasLikedVideos.contains(popularVideos[currentVideoIndex - 1].videoId),
                                onLike: {
                                    likeVideo(popularVideos[currentVideoIndex - 1].videoId,
                                              ownerId: popularVideos[currentVideoIndex - 1].userId)
                                },
                                onUnlike: {
                                    unlikeVideo(popularVideos[currentVideoIndex - 1].videoId,
                                                ownerId: popularVideos[currentVideoIndex - 1].userId)
                                },
                                onUserProfile: { userId in
                                    showUserProfile(userId: userId)
                                },
                                isActive: false
                            )
                            .id("\(popularVideos[currentVideoIndex - 1].videoId)_\(popularVideos[currentVideoIndex - 1].userId)")
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height)
                            .ignoresSafeArea()
                            .offset(y: geometry.size.height + dragOffset)
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if (value.translation.height < 0 && currentVideoIndex < popularVideos.count - 1) ||
                                   (value.translation.height > 0 && currentVideoIndex > 0) {
                                    // Allow dragging only if there's a next or previous video
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -50 && currentVideoIndex < popularVideos.count - 1 {
                                    // Swipe up to next video with a faster animation
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                        dragOffset = -geometry.size.height
                                    }
                                    
                                    // Use a shorter delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        currentVideoIndex += 1
                                        dragOffset = 0
                                    }
                                } else if value.translation.height > 50 && currentVideoIndex > 0 {
                                    // Swipe down to previous video with a faster animation
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        dragOffset = geometry.size.height
                                    }
                                    
                                    // Use a shorter delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        currentVideoIndex -= 1
                                        dragOffset = 0
                                    }
                                } else {
                                    // Reset if swipe not far enough
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
            }
            
            // Refresh indicator
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
            fetchPopularVideos()
            fetchLikedVideos()
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("VideoViewCountUpdated"),
                object: nil,
                queue: .main
            ) { notification in
                if let videoId = notification.userInfo?["videoId"] as? String,
                   let newViewCount = notification.userInfo?["newViewCount"] as? Int {
                    
                    // Update the view count in our local array
                    for i in 0..<self.popularVideos.count {
                        if self.popularVideos[i].videoId == videoId {
                            let video = self.popularVideos[i]
                            self.popularVideos[i] = (
                                userId: video.userId,
                                videoId: video.videoId,
                                url: video.url,
                                title: video.title,
                                views: newViewCount
                            )
                        }
                    }
                }
            }
               
            // Add notification observer for new video uploads
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UserVideosUpdated"),
                object: nil,
                queue: .main
            ) { notification in
                // Check if we should show the user's newly uploaded video
                if let showMyVideo = notification.userInfo?["showMyVideo"] as? Bool,
                   showMyVideo,
                   let videoId = notification.userInfo?["videoId"] as? String {
                    
                    self.justUploadedVideoId = videoId
                }
                
                // Refresh the videos list
                self.isRefreshing = true
                self.fetchPopularVideos()
            }
            
            // Set up timer to refresh data periodically
            Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
                fetchLikedVideos()
                
                // Only refresh video data if the user hasn't interacted with a video
                if !isRefreshing {
                    fetchPopularVideos(silent: true)
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("UserVideosUpdated"),
                object: nil
            )
        }
    }
    
    private func fetchPopularVideos(silent: Bool = false) {
        if !silent {
            isLoading = true
        }
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Query for videos ordered by views (most popular first)
        let query = CKQuery(recordType: "UserVideo", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "views", ascending: false)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 20
        
        var videos: [(userId: String, videoId: String, url: URL, title: String, views: Int)] = []
        var userIds = Set<String>()
        
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let record):
                if let owner = record["owner"] as? String,
                   let videoId = record["videoId"] as? String,
                   let videoAsset = record["videoFile"] as? CKAsset,
                   let fileURL = videoAsset.fileURL {
                    
                    // Add user ID to set for fetching user details
                    userIds.insert(owner)
                    
                    // Make a unique local copy of the video
                    let uniqueID = UUID().uuidString
                    let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(uniqueID)_\(videoId).mp4")
                    
                    do {
                        // Remove existing if needed
                        if FileManager.default.fileExists(atPath: localURL.path) {
                            try FileManager.default.removeItem(at: localURL)
                        }
                        
                        try FileManager.default.copyItem(at: fileURL, to: localURL)
                        let title = record["title"] as? String ?? "Video"
                        let views = record["views"] as? Int ?? 0
                        
                        videos.append((userId: owner, videoId: videoId, url: localURL, title: title, views: views))
                    } catch {
                        print("Error copying video file: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                print("Error fetching popular video: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                // Now fetch user records for all videos
                if !userIds.isEmpty {
                    fetchUserRecords(Array(userIds)) { success in
                        DispatchQueue.main.async {
                            // Check if we need to prioritize a newly uploaded video
                            if let justUploadedId = self.justUploadedVideoId,
                               let index = videos.firstIndex(where: { $0.videoId == justUploadedId }) {
                                
                                // Move this video to the top of the list
                                let uploadedVideo = videos.remove(at: index)
                                videos.insert(uploadedVideo, at: 0)
                                
                                // Clear the flag since we've handled it
                                self.justUploadedVideoId = nil
                            }
                            
                            // Update views for existing videos if needed
                            if !self.popularVideos.isEmpty && !videos.isEmpty {
                                // Find videos that were updated
                                for (i, newVideo) in videos.enumerated() {
                                    if let existingIndex = self.popularVideos.firstIndex(where: { $0.videoId == newVideo.videoId }) {
                                        let existingVideo = self.popularVideos[existingIndex]
                                        // If views changed, update the model
                                        if existingVideo.views != newVideo.views {
                                            videos[i] = (userId: newVideo.userId, videoId: newVideo.videoId, url: newVideo.url, title: newVideo.title, views: newVideo.views)
                                        }
                                    }
                                }
                            }
                            
                            self.popularVideos = videos
                            self.isLoading = false
                            self.isRefreshing = false
                            
                            // Reset to first video if needed
                            if !videos.isEmpty && self.currentVideoIndex >= videos.count {
                                self.currentVideoIndex = 0
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.popularVideos = videos
                        self.isLoading = false
                        self.isRefreshing = false
                    }
                }
            case .failure(let error):
                print("Error in popular videos query: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isRefreshing = false
                }
            }
        }
        
        database.add(operation)
    }
    
    private func fetchUserRecords(_ userIds: [String], completion: @escaping (Bool) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Create a predicate to fetch all user records in one query
        let predicate = NSPredicate(format: "identifier IN %@", userIds)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching user records: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let records = records {
                var userRecordsMap = [String: CKRecord]()
                
                for record in records {
                    if let userId = record["identifier"] as? String {
                        userRecordsMap[userId] = record
                    }
                }
                
                DispatchQueue.main.async {
                    self.userRecords = userRecordsMap
                    completion(true)
                }
            } else {
                completion(false)
            }
        }
    }
    
    private func fetchLikedVideos() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first,
               let likedVideos = record["likedVideos"] as? [String] {
                
                DispatchQueue.main.async {
                    self.hasLikedVideos = Set(likedVideos)
                }
            }
        }
    }
    
    // In PopularVideosFeedView, modify the likeVideo function:
    private func likeVideo(_ videoId: String, ownerId: String) {
        print("Liking video: \(videoId)")
        
        // Add to local state immediately for better UI feedback
        hasLikedVideos.insert(videoId)
        
        let database = CKContainer.default().publicCloudDatabase
        
        // First, update the video's like count
        let videoPredicate = NSPredicate(format: "videoId == %@", videoId)
        let videoQuery = CKQuery(recordType: "UserVideo", predicate: videoPredicate)
        
        database.perform(videoQuery, inZoneWith: nil) { records, error in
            if let videoRecord = records?.first {
                let currentLikes = videoRecord["likes"] as? Int ?? 0
                videoRecord["likes"] = currentLikes + 1
                
                database.save(videoRecord) { _, error in
                    if let error = error {
                        print("Error updating video likes: \(error.localizedDescription)")
                    } else {
                        print("✅ Video like count updated")
                    }
                }
            }
        }
        
        // Then update the user's liked videos list
        let userPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let userQuery = CKQuery(recordType: "UserProfile", predicate: userPredicate)
        
        database.perform(userQuery, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                var likedVideos = userRecord["likedVideos"] as? [String] ?? []
                
                if !likedVideos.contains(videoId) {
                    likedVideos.append(videoId)
                    userRecord["likedVideos"] = likedVideos
                    
                    database.save(userRecord) { _, error in
                        if let error = error {
                            print("Error updating liked videos: \(error.localizedDescription)")
                        } else {
                            print("✅ User's liked videos list updated")
                        }
                    }
                }
            }
        }
        
        // Also increment owner's like count for notifications
        let ownerPredicate = NSPredicate(format: "identifier == %@", ownerId)
        let ownerQuery = CKQuery(recordType: "UserProfile", predicate: ownerPredicate)
        
        database.perform(ownerQuery, inZoneWith: nil) { records, error in
            if let ownerRecord = records?.first {
                let likeCount = ownerRecord["likeCount"] as? Int ?? 0
                ownerRecord["likeCount"] = likeCount + 1
                
                database.save(ownerRecord) { _, error in
                    if let error = error {
                        print("Error updating owner like count: \(error.localizedDescription)")
                    } else {
                        print("✅ Owner's like count incremented")
                        
                        // Play a haptic feedback for successful like
                        DispatchQueue.main.async {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    }
                }
            }
        }
    }
    
    private func unlikeVideo(_ videoId: String, ownerId: String) {
        // Remove from local state
        hasLikedVideos.remove(videoId)
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Update the video's like count
        let videoPredicate = NSPredicate(format: "videoId == %@", videoId)
        let videoQuery = CKQuery(recordType: "UserVideo", predicate: videoPredicate)
        
        database.perform(videoQuery, inZoneWith: nil) { records, error in
            if let videoRecord = records?.first {
                let currentLikes = videoRecord["likes"] as? Int ?? 0
                videoRecord["likes"] = max(0, currentLikes - 1)
                
                database.save(videoRecord) { _, error in
                    if let error = error {
                        print("Error updating video likes: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Update the user's liked videos list
        let userPredicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let userQuery = CKQuery(recordType: "UserProfile", predicate: userPredicate)
        
        database.perform(userQuery, inZoneWith: nil) { records, error in
            if let userRecord = records?.first {
                var likedVideos = userRecord["likedVideos"] as? [String] ?? []
                
                likedVideos.removeAll(where: { $0 == videoId })
                userRecord["likedVideos"] = likedVideos
                
                database.save(userRecord) { _, error in
                    if let error = error {
                        print("Error updating liked videos: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Also decrement owner's like count
        let ownerPredicate = NSPredicate(format: "identifier == %@", ownerId)
        let ownerQuery = CKQuery(recordType: "UserProfile", predicate: ownerPredicate)
        
        database.perform(ownerQuery, inZoneWith: nil) { records, error in
            if let ownerRecord = records?.first {
                let likeCount = ownerRecord["likeCount"] as? Int ?? 0
                ownerRecord["likeCount"] = max(0, likeCount - 1)
                
                database.save(ownerRecord) { _, error in
                    if let error = error {
                        print("Error updating owner like count: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showUserProfile(userId: String) {
        ProfileViewHelper.shared.showUserProfile(userId: userId)
    }
}

struct VideoFeedItem: View {
    let video: (userId: String, videoId: String, url: URL, title: String, views: Int)
    let userRecord: CKRecord
    let hasLiked: Bool
    let onLike: () -> Void
    let onUnlike: () -> Void
    let onUserProfile: (String) -> Void
    var isActive: Bool = true // Add this with a default value
    
    // IMPORTANT - Add id to force view recreation when video changes
    var id: String { video.videoId }
    
    @State private var isPlaying = true
    @State private var isLikeAnimating = false
    @State private var showOptions = false
    @State private var profileImage: UIImage?
    @State private var audioTrackName: String = ""
    @State private var audioCreator: String = ""
    
    var body: some View {
        ZStack {
            // Reset isPlaying when video changes
            Color.clear.onAppear {
                // Force video to play when the item appears
                isPlaying = true
                // Load profile image
                loadProfileImage()
            }
            
            // Video player
            if isPlaying {
                VideoPlayerLoopView(url: video.url, isPlaying: $isPlaying, isActive: isActive)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isPlaying.toggle()
                    }
            } else {
                // Show thumbnail when paused with ONLY ONE play button
                if !isPlaying && isActive {
                    VideoThumbnailView(videoURL: video.url)
                        .ignoresSafeArea()
                        .overlay(
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundColor(.white.opacity(0.8))
                        )
                        .onTapGesture { isPlaying = true }
                }
            }
            
            // Controls overlay
            VStack {
                // Top bar with user info
                HStack {
                    Button(action: {
                        onUserProfile(video.userId)
                    }) {
                        HStack(spacing: 8) {
                            // Profile image
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(getUserName().prefix(1))
                                            .foregroundColor(.white)
                                            .font(.appHeadline)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(getUserName())
                                    .font(.appHeadline)
                                    .foregroundColor(.white)
                                
                                Text(video.title)
                                    .font(.appCaption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Options button
                    Menu {
                        Button("View \(getUserName())'s Profile") {
                            onUserProfile(video.userId)
                        }
                        Button("Share Video") {
                            shareVideo()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
                .padding(.top, safeTop)
                .padding(.horizontal, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Bottom info and controls
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Video info
                        Text(video.title)
                            .font(.appHeadline)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        if !audioTrackName.isEmpty {
                                   HStack {
                                       Image(systemName: "music.note")
                                           .font(.appTiny)
                                           .foregroundColor(.white.opacity(0.8))
                                       
                                       Text("\(audioTrackName) - \(audioCreator)")
                                           .font(.appTiny)
                                           .foregroundColor(.white.opacity(0.8))
                                           .lineLimit(1)
                                   }
                               }
                        
                        HStack {
                            Image(systemName: "eye.fill")
                                .font(.appCaption)
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("\(video.views) views")
                                .font(.appCaption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // Right side controls
                    VStack(spacing: 20) {
                        // Like button
                        Button(action: {
                            if hasLiked {
                                onUnlike()
                            } else {
                                onLike()
                                isLikeAnimating = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isLikeAnimating = false
                                }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: hasLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 30))
                                    .foregroundColor(hasLiked ? .red : .white)
                                    .scaleEffect(isLikeAnimating ? 1.3 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLikeAnimating)
                            }
                        }
                        
                        // Share button
                        Button(action: {
                            shareVideo()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                        
                        // Profile button
                        Button(action: {
                            onUserProfile(video.userId)
                        }) {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            } else {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(getUserName().prefix(1))
                                            .foregroundColor(.black)
                                            .font(.appHeadline)
                                    )
                            }
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, safeBottom + 60)
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
        .onChange(of: isActive) { nowActive in
            if nowActive { isPlaying = true }
        }
        .transaction { $0.disablesAnimations = true }
        .onAppear {
            // Ensure we load the profile image when the view appears
            loadProfileImage()
            if isActive { incrementViewCount() }
            loadAudioInfo()
        }
        .onChange(of: isActive) { newValue in
            //  sync play state whenever card becomes active or inactive
            isPlaying = newValue
        }
    }
    
    private func loadAudioInfo() {
            // Query for the audio info from the video
            let database = CKContainer.default().publicCloudDatabase
            let predicate = NSPredicate(format: "videoId == %@", video.videoId)
            let query = CKQuery(recordType: "UserVideo", predicate: predicate)
            
            database.perform(query, inZoneWith: nil) { records, error in
                if let record = records?.first,
                   let audioId = record["audioTrackId"] as? String {
                    
                    // Look up the audio track
                    let audioQuery = CKQuery(
                        recordType: "AudioTrack",
                        predicate: NSPredicate(format: "audioId == %@", audioId)
                    )
                    
                    database.perform(audioQuery, inZoneWith: nil) { audioRecords, audioError in
                        if let audioRecord = audioRecords?.first {
                            DispatchQueue.main.async {
                                self.audioTrackName = audioRecord["title"] as? String ?? ""
                                self.audioCreator = audioRecord["creator"] as? String ?? ""
                            }
                        }
                    }
                }
            }
        }
    
    private func getUserName() -> String {
        return userRecord["firstName"] as? String ?? "User"
    }
    
    // In VideoFeedItem struct
    private func loadProfileImage() {
        // Reset the profile image when loading a new one
        self.profileImage = nil
        
        // Carefully load the image for this specific userRecord
        if let imageAsset = userRecord["profileImage"] as? CKAsset,
           let imageUrl = imageAsset.fileURL,
           FileManager.default.fileExists(atPath: imageUrl.path) {
            
            do {
                let imageData = try Data(contentsOf: imageUrl)
                if let image = UIImage(data: imageData) {
                    DispatchQueue.main.async {
                        self.profileImage = image
                        print("Successfully loaded profile image for \(self.getUserName())")
                    }
                }
            } catch {
                print("Error loading profile image: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.profileImage = nil
                }
            }
        } else {
            // Ensure we clear the image if there isn't one for this user
            DispatchQueue.main.async {
                self.profileImage = nil
            }
            print("No profile image asset available for user: \(getUserName())")
        }
    }
    
    private func incrementViewCount() {
        let database = CKContainer.default().publicCloudDatabase
        
        // Only increment views for videos by other users, not your own videos
        if video.userId != UserDefaults.standard.string(forKey: "userIdentifier") {
            // Query for the video record
            let predicate = NSPredicate(format: "videoId == %@", video.videoId)
            let query = CKQuery(recordType: "UserVideo", predicate: predicate)
            
            database.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    print("Error finding video to increment view: \(error.localizedDescription)")
                    return
                }
                
                guard let videoRecord = records?.first else {
                    print("Video record not found for ID: \(self.video.videoId)")
                    return
                }
                
                // Increment the view count
                let currentViews = videoRecord["views"] as? Int ?? 0
                videoRecord["views"] = currentViews + 1
                
                // Save the updated record
                database.save(videoRecord) { _, saveError in
                    if let saveError = saveError {
                        print("Error updating view count: \(saveError.localizedDescription)")
                    } else {
                        print("✅ View count incremented for video: \(self.video.title)")
                        // Post notification to refresh video list
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("VideoViewCountUpdated"),
                                object: nil,
                                userInfo: [
                                    "videoId": self.video.videoId,
                                    "newViewCount": currentViews + 1
                                ]
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func shareVideo() {
        // Create a temporary file from the video URL
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("shared_video.mp4")
        
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            try FileManager.default.copyItem(at: video.url, to: tempURL)
            
            // Show share sheet
            let activityViewController = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                
                // Find the top-most controller
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }
                
                // Present the share sheet
                topVC.present(activityViewController, animated: true)
            }
        } catch {
            print("Error sharing video: \(error.localizedDescription)")
        }
    }
}

// Add this to PopularVideosFeedView.swift:
struct VideoPlayerLoopView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    var isActive: Bool = true
    
    // Add an id to force recreation of the view controller
    var id: String { url.absoluteString }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("Creating new AVPlayerViewController for \(url.lastPathComponent)")
        
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false  // Hide default controls
        controller.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        // Set up observation of playback status
        context.coordinator.player = player
        context.coordinator.setupObservers()
        
        // Start playing automatically
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiVC: AVPlayerViewController,
                                context: Context) {

        if isActive {
            isPlaying ? uiVC.player?.play()
                      : uiVC.player?.pause()
        } else {
            uiVC.player?.pause()
        }
    }



    
    // Add this to ensure view is recreated when URL changes
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        print("Dismantling AVPlayerViewController")
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: VideoPlayerLoopView
        var player: AVPlayer?
        private var timeObserver: Any?
        
        init(_ parent: VideoPlayerLoopView) {
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
            if parent.isPlaying {
                player?.play()
            }
        }
        
        deinit {
            if let timeObserver = timeObserver, let player = player {
                player.removeTimeObserver(timeObserver)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
}
