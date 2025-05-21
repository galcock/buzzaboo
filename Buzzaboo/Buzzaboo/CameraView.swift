import SwiftUI
import LiveKit
import LiveKitWebRTC
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var room: Room
    @Binding var matchedUserIdentifier: String?
    let userIdentifier: String
    private let id = UUID().uuidString // Unique ID to prevent recreation
    
    // Cache to track which views have which tracks to avoid redundant assignments
    private static var trackCache = [String: String]() // Use track ID string instead of VideoTrack
    
    init(matchedUserIdentifier: Binding<String?>, room: Room, userIdentifier: String) {
        self._matchedUserIdentifier = matchedUserIdentifier
        self._room = ObservedObject(wrappedValue: room)
        self.userIdentifier = userIdentifier
        print("Initializing CameraView with LiveKit for user: \(userIdentifier)")
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        print("Creating CameraView UI for instance \(id)")
        let controller = UIViewController()
        
        // Setup the UI elements first
        setupVideoUI(in: controller)
        
        // Setup the coordinator
        context.coordinator.controller = controller
        
        // Start camera setup after a short delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            setupVideoCapture(in: controller, coordinator: context.coordinator)
        }
        
        return controller
    }
    
    private func setupVideoUI(in controller: UIViewController) {
        print("Setting up video UI elements for \(id)")
        
        // Setup main view for remote video
        let mainView = UIView(frame: controller.view.bounds)
        mainView.backgroundColor = .black
        mainView.tag = 100
        controller.view.addSubview(mainView)
        mainView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: controller.view.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        
        let previewSize = CGSize(width: 100, height: 150)
        let previewFrame = CGRect(
            x: controller.view.bounds.width - previewSize.width - 20,
            y: controller.view.bounds.height - previewSize.height - 20,
            width: previewSize.width,
            height: previewSize.height)
        
        // Create the VideoView with a specific frame but don't set up track yet
        let previewView = VideoView(frame: previewFrame)
        previewView.tag = 200
               previewView.layoutMode = .fill // Use fill mode to ensure video content is visible
               previewView.backgroundColor = .gray
               previewView.layer.cornerRadius = 10
               previewView.clipsToBounds = true
               previewView.layer.borderWidth = 2
               previewView.layer.borderColor = UIColor.white.cgColor
               previewView.isEnabled = true // Ensure enabled
        previewView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
               
               // Add to view hierarchy
               controller.view.addSubview(previewView)
               controller.view.bringSubviewToFront(previewView)
               
               // Create debug label to show connection status
               let debugLabel = UILabel(frame: CGRect(x: 10, y: 30, width: 300, height: 30))
               debugLabel.textColor = .white
               debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
               debugLabel.text = "Initializing camera..."
               debugLabel.tag = 300
               controller.view.addSubview(debugLabel)
           }
           
    private func setupVideoCapture(in controller: UIViewController, coordinator: Coordinator) {
        print("Starting camera setup for \(id)")
        
        let localParticipant = room.localParticipant
        print("Local participant: \(localParticipant)")
        
        Task {
            do {
                print("Checking room connection for \(id)")
                if room.connectionState != .connected {
                    print("Room not connected, connecting...")
                    
                    // Generate token and connect
                    let signalingClient = SignalingClient(userId: userIdentifier)
                    let token = try signalingClient.generateToken(room: "test-room", identity: userIdentifier)
                    print("Token generated, connecting to room")
                    
                    let options = ConnectOptions(autoSubscribe: true)
                    try await room.connect(url: "wss://livekit.buzzaboo.com:443", token: token, connectOptions: options)
                    
                    print("✅ Connected to room with autoSubscribe")
                    DispatchQueue.main.async {
                        if let label = controller.view.viewWithTag(300) as? UILabel {
                            label.text = "Connected to room"
                        }
                    }
                }
                
                // Force the front camera here
                let cameraOptions = CameraCaptureOptions(position: .front)
                let videoTrack = LocalVideoTrack.createCameraTrack(options: cameraOptions)
                
                // Publish the track directly instead of using setCamera
                try await localParticipant.publish(videoTrack: videoTrack)
                print("Camera enabled for \(id) using front camera")
                
                // Wait for camera track to initialize
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                DispatchQueue.main.async {
                    attachLocalVideoTrack(to: controller)
                    
                    // Configure connection based on mode
                    if let matchedId = matchedUserIdentifier, !matchedId.isEmpty {
                        print("Configured for P2P mode with matched user: \(matchedId)")
                    }
                }
                
            } catch {
                print("Error in setupVideo for \(id): \(error.localizedDescription)")
                // Show error in debug label
                DispatchQueue.main.async {
                    if let label = controller.view.viewWithTag(300) as? UILabel {
                        label.text = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
           
           private func attachLocalVideoTrack(to controller: UIViewController) {
               print("Attempting to attach local video track")
               let publications = room.localParticipant.trackPublications.values
               
               guard let videoPub = publications.first(where: { $0.kind == .video }),
                     let videoTrack = videoPub.track as? VideoTrack,
                     let previewView = controller.view.viewWithTag(200) as? VideoView else {
                   print("❌ Unable to attach local video - will retry")
                   DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                       attachLocalVideoTrack(to: controller)
                   }
                   return
               }
               
               // Store in cache to track by ID string
               if let trackId = videoTrack.sid {
                   CameraView.trackCache[id] = trackId.stringValue
               }
               
               print("✅ Attaching local video track to preview view")
               DispatchQueue.main.async {
                   // First remove any existing track to ensure clean attachment
                   if let currentTrack = previewView.track as? VideoTrack {
                       currentTrack.remove(videoRenderer: previewView)
                   }
                   
                   previewView.track = videoTrack
                   previewView.isEnabled = true
                   previewView.setNeedsLayout()
               }
           }
           
           func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
               // Handle app lifecycle changes
               if scenePhase == .active {
                   print("App became active, refreshing video for \(id)")
                   
                   // Update local video
                   if let previewView = uiViewController.view.viewWithTag(200) as? VideoView {
                       let publications = room.localParticipant.trackPublications.values
                       
                       if let publication = publications.first(where: { $0.kind == .video }),
                          let videoTrack = publication.track as? VideoTrack {
                           
                           // Only update if track changed
                           let trackId = videoTrack.sid?.stringValue ?? ""
                           let cachedTrackId = CameraView.trackCache[id] ?? ""
                           
                           if trackId != cachedTrackId {
                               print("Updating local video track")
                               
                               // Remove any existing track
                               if let currentTrack = previewView.track as? VideoTrack {
                                   currentTrack.remove(videoRenderer: previewView)
                               }
                               
                               // Update cache and set track
                               CameraView.trackCache[id] = trackId
                               previewView.track = videoTrack
                               previewView.isEnabled = true
                               previewView.setNeedsLayout()
                               
                               // Update status label
                               if let label = uiViewController.view.viewWithTag(300) as? UILabel {
                                   label.text = "Local video connected"
                               }
                           }
                       }
                   }
                   
                   // Refresh remote video if necessary
                   context.coordinator.refreshRemoteVideo()
               } else if scenePhase == .inactive || scenePhase == .background {
                   print("App going to background, pausing video for \(id)")
                   pauseVideoTracks(in: uiViewController)
               }
           }
           
           private func pauseVideoTracks(in controller: UIViewController) {
               // Set VideoViews to not enabled to save resources
               if let previewView = controller.view.viewWithTag(200) as? VideoView {
                   previewView.isEnabled = false
               }
               
               // Also remove remote video if present
               if let mainView = controller.view.viewWithTag(100) {
                   for subview in mainView.subviews {
                       if let videoView = subview as? VideoView {
                           videoView.isEnabled = false
                       }
                   }
               }
           }
           
           private func displayRemoteVideo(_ videoTrack: VideoTrack, in controller: UIViewController) {
               DispatchQueue.main.async {
                   guard let mainView = controller.view.viewWithTag(100) else { return }

                   // Get any existing VideoView or create a new one
                   let remoteView: VideoView
                   if let existingView = mainView.subviews.first(where: { $0 is VideoView }) as? VideoView {
                       remoteView = existingView
                       
                       // Remove any existing track to ensure clean attachment
                       if let currentTrack = remoteView.track as? VideoTrack {
                           currentTrack.remove(videoRenderer: remoteView)
                       }
                   } else {
                       // Clear existing views first
                       for subview in mainView.subviews {
                           subview.removeFromSuperview()
                       }
                       
                       // Create new video view
                       remoteView = VideoView(frame: mainView.bounds)
                       remoteView.layoutMode = .fill // Use fill mode for better visibility
                       remoteView.backgroundColor = .black
                       mainView.addSubview(remoteView)

                       remoteView.translatesAutoresizingMaskIntoConstraints = false
                       NSLayoutConstraint.activate([
                           remoteView.topAnchor.constraint(equalTo: mainView.topAnchor),
                           remoteView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
                           remoteView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
                           remoteView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor)
                       ])
                   }

                   // Ensure view is ready before assigning track
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                       remoteView.track = videoTrack
                       remoteView.isEnabled = true
                       remoteView.setNeedsLayout()

                       if let label = controller.view.viewWithTag(300) as? UILabel {
                           label.text = "✅ Remote video connected"
                       }

                       // Make sure the local view stays on top
                       controller.view.bringSubviewToFront(controller.view.viewWithTag(200)!)
                       controller.view.bringSubviewToFront(controller.view.viewWithTag(300)!)
                   }
               }
           }
           
           func makeCoordinator() -> Coordinator {
               print("Making coordinator for \(id)")
               return Coordinator(room: room, parent: self)
           }
           
           class Coordinator: NSObject, RoomDelegate {
               private let room: Room
               private let parent: CameraView
               weak var controller: UIViewController?
               private var remoteVideoTrack: VideoTrack?
               private var trackMonitorTimer: Timer?
               
               init(room: Room, parent: CameraView) {
                   self.room = room
                   self.parent = parent
                   super.init()
                   
                   // Remove any existing delegates first
                   room.remove(delegate: self)
                   
                   // Add ourselves as a delegate
                   room.add(delegate: self)
                   print("✅ Room delegate explicitly set")
                   
                   // Start a timer to monitor tracks in case events are missed
                   self.trackMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                       self?.checkForTracks()
                   }
               }
               
               deinit {
                   trackMonitorTimer?.invalidate()
                   trackMonitorTimer = nil
                   
                   // Clean up by removing delegate reference
                   room.remove(delegate: self)
               }
               
               private func checkForTracks() {
                   // Check if we have any remote video tracks to display
                   for participant in room.remoteParticipants.values {
                       for (_, publication) in participant.trackPublications {
                           if publication.kind == .video,
                              let videoTrack = publication.track as? VideoTrack,
                              let controller = controller {
                               DispatchQueue.main.async {
                                   self.remoteVideoTrack = videoTrack
                                   self.parent.displayRemoteVideo(videoTrack, in: controller)
                               }
                           }
                       }
                   }
               }
               
               func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication, track: Track) {
                   print("✅ didSubscribeTrack called for kind: \(track.kind)")

                   guard track.kind == .video, let videoTrack = track as? VideoTrack else {
                       print("⚠️ didSubscribeTrack received non-video track.")
                       return
                   }

                   DispatchQueue.main.async { [weak self] in
                       guard let self = self, let controller = self.controller else {
                           print("❌ Controller reference lost.")
                           return
                       }
                       
                       // Store for refresh
                       self.remoteVideoTrack = videoTrack
                       
                       print("✅ Displaying remote video now.")
                       self.parent.displayRemoteVideo(videoTrack, in: controller)
                   }
               }
               
               func refreshRemoteVideo() {
                   guard let videoTrack = remoteVideoTrack, let controller = controller else { return }
                   parent.displayRemoteVideo(videoTrack, in: controller)
               }
               
               func room(_ room: Room, didConnect participant: RemoteParticipant) {
                   print("Remote participant connected: \(participant.identity?.stringValue ?? "unknown")")
                   
                   // Request subscriptions to any existing tracks
                   checkForTracks()
               }
               
               func room(_ room: Room, didFailToConnectWithError error: Error) {
                   print("Failed to connect to room: \(error.localizedDescription)")
                   
                   if let controller = controller, let label = controller.view.viewWithTag(300) as? UILabel {
                       DispatchQueue.main.async {
                           label.text = "Connection failed: \(error.localizedDescription)"
                       }
                   }
               }
               
               func room(_ room: Room, didDisconnectWithError error: Error?) {
                   if let error = error {
                       print("Room disconnected with error: \(error.localizedDescription)")
                   } else {
                       print("Room disconnected normally")
                   }
                   
                   if let controller = controller, let label = controller.view.viewWithTag(300) as? UILabel {
                       DispatchQueue.main.async {
                           label.text = "Disconnected from room"
                       }
                   }
               }
           }
        }
