import SwiftUI
import CloudKit

// Define available tabs
enum TabItem {
    case live
    case videos
    case upload
    case inbox
    case profile
}

struct MainAppView: View {
    let userIdentifier: String
    let firstName: String
    @State private var selectedTab: TabItem = .live
    @State private var previousTab: TabItem = .live
    @StateObject private var locationManager: LocationManager
    @State private var profileImage: UIImage?
    @State private var showProfileEditor = false
    
    // Video upload states
    @State private var isShowingVideoSourceSheet = false
    @State private var isShowingCamera = false
    @State private var videoPickerShowing = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isVideoUploading = false
    
    init(userIdentifier: String, firstName: String) {
        self.userIdentifier = userIdentifier
        self.firstName = firstName
        _locationManager = StateObject(wrappedValue: LocationManager(userIdentifier: userIdentifier))
    }
    
    var body: some View {
        ZStack {
            // Background view layer
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Main content layer - changes based on selected tab
            VStack(spacing: 0) {
                // Main tab content
                ZStack {
                    // LIVE tab - existing 1:1 match functionality
                    if selectedTab == .live {
                        MainView(
                            userIdentifier: userIdentifier,
                            firstName: firstName
                        )
                    }
                
                    // Videos tab - popular videos feed
                    if selectedTab == .videos {
                        PopularVideosFeedView(userIdentifier: userIdentifier)
                    }
                    
                    // Inbox tab
                    if selectedTab == .inbox {
                        InboxView(userIdentifier: userIdentifier, firstName: firstName)
                    }
                    
                    // Profile tab - show profile editor
                    if selectedTab == .profile {
                        ProfileView(
                            userIdentifier: userIdentifier,
                            firstName: firstName,
                            returnToTab: $previousTab,
                            onDismiss: {
                                selectedTab = previousTab
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                // Custom navigation bar
                NavigationBar(selectedTab: $selectedTab, userIdentifier: userIdentifier)
            }
            
            // Show profile editor if needed
            if showProfileEditor {
                ProfileEditorView(
                    firstName: firstName,
                    userIdentifier: userIdentifier,
                    stateOfMind: .constant(""),
                    onSave: { _, _, _, _, _, _, _, _, _, _ in
                        showProfileEditor = false
                    },
                    onCancel: {
                        showProfileEditor = false
                    }
                )
                .background(Color.black.opacity(0.7))
                .edgesIgnoringSafeArea(.all)
            }
            
            // Show loading indicator when uploading
            if isVideoUploading {
                ZStack {
                    Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)
                    VStack {
                        PulsingLoaderView()
                        Text("Uploading video...")
                            .font(.appHeadline)
                            .foregroundColor(.white)
                            .padding(.top, 20)
                    }
                }
            }
        }
        .sheet(isPresented: $videoPickerShowing) {
            VideoCaptureView(isCamera: false) { videoURL, title in
                if let url = videoURL {
                    uploadVideo(url: url, title: title, audioTrackId: nil)  // Add nil for audioTrackId
                }
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            VideoCaptureView(isCamera: true) { videoURL, title in
                if let url = videoURL {
                    uploadVideo(url: url, title: title, audioTrackId: nil)  // Add nil for audioTrackId
                }
            }
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
        .onAppear {
            loadProfileImage()
        }
        .onChange(of: selectedTab) { newValue in
            // Save previous tab when changing, but only if we're not going to or from profile
            if newValue != .profile && selectedTab != .profile {
                previousTab = selectedTab
            }
            
            // Handle upload tab - activate video source sheet directly
            if newValue == .upload {
                isShowingVideoSourceSheet = true
                // Set the tab back to previous tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedTab = previousTab
                }
            }
        }
    }
    
    // Upload video function
    // In MainAppView.swift, modify the uploadVideo function

    private func uploadVideo(url: URL, title: String, audioTrackId: String? = nil) {
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
            record["owner"] = userIdentifier
            record["videoFile"] = asset
            record["dateUploaded"] = Date()
            record["views"] = 0
            record["likes"] = 0
            record["videoId"] = videoId.uuidString
            record["localPath"] = "Videos/\(videoId.uuidString).mp4"
            
            // Add audio track ID if available
            if let audioTrackId = audioTrackId {
                record["audioTrackId"] = audioTrackId
            }
            
            print("Saving UserVideo to CloudKit with identifier: \(userIdentifier), title: \(title)")
            let database = CKContainer.default().publicCloudDatabase
            database.save(record) { savedRecord, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error uploading video: \(error.localizedDescription)")
                    } else {
                        print("✅ Video uploaded successfully")
                        
                        // For UI refresh - send a notification that videos were updated
                        // Include the videoId so we can highlight this specific video
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UserVideosUpdated"),
                            object: nil,
                            userInfo: [
                                "userId": self.userIdentifier,
                                "videoId": videoId.uuidString,
                                "showMyVideo": true  // Flag to indicate we should show the user's video first
                            ]
                        )
                        
                        // Switch to videos tab to see the newly uploaded video
                        self.selectedTab = .videos
                    }
                    
                    self.isVideoUploading = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                print("Error preparing video file: \(error.localizedDescription)")
                self.isVideoUploading = false
            }
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
}

struct ProfileView: View {
    let userIdentifier: String
    let firstName: String
    @Binding var returnToTab: TabItem
    var onDismiss: () -> Void
    @State private var stateOfMind: String = ""
    
    var body: some View {
        ProfileEditorView(
            firstName: firstName,
            userIdentifier: userIdentifier,
            stateOfMind: $stateOfMind,
            onSave: { newStateOfMind, religion, showJobTitle, showSchool, showReligion, showHometown, gender, jobTitle, school, hometown in
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
                
                onDismiss()
            },
            onCancel: {
                onDismiss()
            }
        )
        .onAppear {
            self.stateOfMind = UserDefaults.standard.string(forKey: "userStateOfMind_\(userIdentifier)") ?? ""
        }
    }
}
