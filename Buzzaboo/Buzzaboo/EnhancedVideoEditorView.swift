// EnhancedVideoEditorView.swift - Fixed version
import SwiftUI
import AVFoundation

struct EnhancedVideoEditorView: View {
    let videoURL: URL
    let onComplete: (URL?, String) -> Void
    
    @State private var title = "My Video"
    @State private var selectedAudioTrack: AudioTrack?
    @State private var showAudioBrowser = false
    @State private var showAudioRecorder = false
    @State private var extractingOwnAudio = false
    @State private var isProcessing = false
    @State private var audioVolume: Double = 1.0
    @State private var originalVideoVolume: Double = 1.0
    @State private var previewPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var previewSize: CGSize = .zero
    
    @Environment(\.presentationMode) var presentationMode
    
    // Current user name for audio credits
    let userName = UserDefaults.standard.string(forKey: "firstName") ?? "User"
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Video preview
                ZStack {
                    if let player = previewPlayer {
                        VideoPlayerPreview(player: player)
                            .aspectRatio(9/16, contentMode: .fit)
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay(
                                Button(action: {
                                    togglePlayback()
                                }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            )
                            .clipped()
                            .background(
                                GeometryReader { geo -> Color in
                                    DispatchQueue.main.async {
                                        previewSize = geo.size
                                    }
                                    return Color.clear
                                }
                            )
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .aspectRatio(9/16, contentMode: .fit)
                            .overlay(
                                Text("Loading preview...")
                                    .foregroundColor(.white)
                            )
                    }
                }
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Title input
                TextField("Video title", text: $title)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                // Audio track selection
                Section {
                    if selectedAudioTrack != nil {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Sound:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Text(selectedAudioTrack?.title ?? "")
                                    .font(.body)
                                    .foregroundColor(.white)
                                
                                Text("By \(selectedAudioTrack?.creator ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showAudioBrowser = true
                            }) {
                                Text("Change")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        
                        // Volume sliders
                        VStack(alignment: .leading) {
                            Text("Audio Volume: \(Int(audioVolume * 100))%")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Slider(value: $audioVolume, in: 0...1, step: 0.05)
                                .accentColor(.blue)
                            
                            Text("Original Video Volume: \(Int(originalVideoVolume * 100))%")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Slider(value: $originalVideoVolume, in: 0...1, step: 0.05)
                                .accentColor(.blue)
                        }
                        .padding(.horizontal)
                    } else {
                        HStack {
                            Button(action: {
                                showAudioBrowser = true
                            }) {
                                HStack {
                                    Image(systemName: "music.note")
                                    Text("Add Sound")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Button(action: {
                                showAudioRecorder = true
                            }) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Record")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Button(action: {
                                extractOwnAudio()
                            }) {
                                HStack {
                                    Image(systemName: "waveform")
                                    Text("Extract")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(extractingOwnAudio)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Save/Cancel buttons
                HStack {
                    Button("Cancel") {
                        stopPlayback()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Save") {
                        saveVideoWithAudio()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isProcessing)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            
            // Loading overlay
            if isProcessing {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    PulsingLoaderView()
                    Text("Processing video...")
                        .foregroundColor(.white)
                        .padding(.top, 20)
                }
            }
            
            if extractingOwnAudio {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    PulsingLoaderView()
                    Text("Extracting audio...")
                        .foregroundColor(.white)
                        .padding(.top, 20)
                }
            }
        }
        .onAppear {
            setupPreviewPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
        .sheet(isPresented: $showAudioBrowser) {
            AudioBrowserView(selectedAudioTrack: $selectedAudioTrack)
                .onDisappear {
                    if selectedAudioTrack != nil {
                        updatePreviewWithAudio()
                    }
                }
        }
        .sheet(isPresented: $showAudioRecorder) {
            AudioRecorderView(
                selectedAudioTrack: $selectedAudioTrack,
                creatorName: userName,
                // Pass video title as default recording title
                initialTitle: title
            )
            .onDisappear {
                if selectedAudioTrack != nil {
                    updatePreviewWithAudio()
                }
            }
        }
    }
    
    // In EnhancedVideoEditorView.swift, modify the setupPreviewPlayer method:
    private func setupPreviewPlayer() {
        // Verify the video URL is valid and file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("Video file not found at path: \(videoURL.path)")
            return
        }
        
        // First stop any existing playback
        stopPlayback()
        
        do {
            // Create AVAsset first to validate the URL
            let asset = AVAsset(url: videoURL)
            
            // Create the player item
            let playerItem = AVPlayerItem(asset: asset)
            
            // Create the player
            let player = AVPlayer(playerItem: playerItem)
            
            // Add observer to restart when finished
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            
            // Assign to previewPlayer and start playback
            self.previewPlayer = player
            player.play()
            self.isPlaying = true
            
            print("Video preview successfully initialized with URL: \(videoURL.path)")
        } catch {
            print("Error setting up preview player: \(error.localizedDescription)")
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            previewPlayer?.pause()
        } else {
            previewPlayer?.play()
        }
        isPlaying = !isPlaying
    }
    
    private func stopPlayback() {
        previewPlayer?.pause()
        previewPlayer = nil
        isPlaying = false
        
        // Remove observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // Replace this line:
    private func extractOwnAudio() {
        guard !extractingOwnAudio else { return }
        
        extractingOwnAudio = true
        stopPlayback() // Stop playback during extraction
        
        // Create image picker configured for videos
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.movie"]
        imagePicker.delegate = makeCoordinator()
        imagePicker.allowsEditing = false
        
        // Present the image picker
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            topVC.present(imagePicker, animated: true)
        } else {
            // If we can't present the picker, fall back to extracting from the current video
            extractAudioFromCurrentVideo()
        }
    }

    // Add this helper method to extract from the current video
    private func extractAudioFromCurrentVideo() {
        // Define the audioTitle using video title
        let audioTitle = "Original Sound - \(title)"
        
        // Use proper extraction method
        AudioLibraryManager.shared.extractAudioFromVideo(
            videoURL: videoURL,
            title: audioTitle,
            creator: userName
        ) { audioTrack in
            DispatchQueue.main.async {
                if let audioTrack = audioTrack {
                    self.selectedAudioTrack = audioTrack
                    // Restart preview with new audio
                    self.setupPreviewPlayer()
                }
                
                self.extractingOwnAudio = false
            }
        }
    }
    
    private func updatePreviewWithAudio() {
        // Stop current playback
        stopPlayback()
        
        // Restart with new preview that will include the audio
        setupPreviewPlayer()
    }
    
    private func saveVideoWithAudio() {
        guard !isProcessing else { return }
        
        // Set isProcessing on the main thread
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        // If no audio track selected, just save the original video
        if selectedAudioTrack == nil {
            let filteredTitle = title.isEmpty ? "My Video" : title
            DispatchQueue.main.async {
                self.onComplete(self.videoURL, filteredTitle)
                self.presentationMode.wrappedValue.dismiss()
            }
            return
        }
        
        // Get the audio URL
        guard let audioTrack = selectedAudioTrack,
              let audioURL = audioTrack.fileURL else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        
        // Create a composition of video and audio
        let asset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        // Create composition
        let composition = AVMutableComposition()
        
        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        
        // Add audio tracks
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        let compositionOriginalAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        // Get original tracks
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        
        // Video time range
        let videoTimeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        do {
            // Add video track
            try compositionVideoTrack.insertTimeRange(
                videoTimeRange,
                of: videoTrack,
                at: .zero
            )
            
            // Add original audio if available
            if let originalAudioTrack = asset.tracks(withMediaType: .audio).first,
               let compositionOriginalAudioTrack = compositionOriginalAudioTrack {
                
                try compositionOriginalAudioTrack.insertTimeRange(
                    videoTimeRange,
                    of: originalAudioTrack,
                    at: .zero
                )
                
                // Set volume for original audio
                let originalAudioMix = AVMutableAudioMix()
                let originalAudioParams = AVMutableAudioMixInputParameters(
                    track: compositionOriginalAudioTrack
                )
                originalAudioParams.setVolume(Float(originalVideoVolume), at: .zero)
                originalAudioMix.inputParameters = [originalAudioParams]
            }
            
            // Add selected audio track
            if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = compositionAudioTrack {
                
                let audioTimeRange = CMTimeRange(
                    start: .zero,
                    duration: min(audioAsset.duration, asset.duration)
                )
                
                try compositionAudioTrack.insertTimeRange(
                    audioTimeRange,
                    of: audioTrack,
                    at: .zero
                )
                
                // Set volume for added audio
                let audioMix = AVMutableAudioMix()
                let audioParams = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                audioParams.setVolume(Float(audioVolume), at: .zero)
                audioMix.inputParameters = [audioParams]
            }
            
            // Create export session
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mp4")
            
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            
            // Export the final video
            exportSession.exportAsynchronously {
                // This completion handler runs on a background thread
                // So we need to dispatch UI updates to the main thread
                DispatchQueue.main.async {
                    self.isProcessing = false
                    
                    switch exportSession.status {
                    case .completed:
                        // Increment usage count for the audio track
                        AudioLibraryManager.shared.incrementUsageCount(
                            for: audioTrack
                        ) { success in
                            // Complete regardless of increment success
                            // This callback might also be on a background thread
                            DispatchQueue.main.async {
                                let filteredTitle = self.title.isEmpty ? "My Video" : self.title
                                self.onComplete(outputURL, filteredTitle)
                                self.presentationMode.wrappedValue.dismiss()
                            }
                        }
                        
                    case .failed, .cancelled:
                        print("Export failed: \(String(describing: exportSession.error))")
                        
                    default:
                        break
                    }
                }
            }
            
        } catch {
            print("Error creating composition: \(error)")
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    // Add this to the EnhancedVideoEditorView
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: EnhancedVideoEditorView
        
        init(_ parent: EnhancedVideoEditorView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Dismiss the picker
            picker.dismiss(animated: true)
            
            // Get the video URL
            guard let videoURL = info[.mediaURL] as? URL else {
                DispatchQueue.main.async {
                    self.parent.extractingOwnAudio = false
                }
                return
            }
            
            // Define the audioTitle using video title
            let audioTitle = "Original Sound - \(self.parent.title)"
            
            // Extract audio from selected video
            AudioLibraryManager.shared.extractAudioFromVideo(
                videoURL: videoURL,
                title: audioTitle,
                creator: self.parent.userName
            ) { audioTrack in
                DispatchQueue.main.async {
                    if let audioTrack = audioTrack {
                        self.parent.selectedAudioTrack = audioTrack
                        // Restart preview
                        self.parent.setupPreviewPlayer()
                    }
                    
                    self.parent.extractingOwnAudio = false
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            DispatchQueue.main.async {
                self.parent.extractingOwnAudio = false
            }
        }
    }
}

struct VideoPlayerPreview: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        
        // Tag the player layer to find it easily later
        playerLayer.name = "playerLayer"
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Get existing player layer or create a new one
        let playerLayer: AVPlayerLayer
        if let existingLayer = uiView.layer.sublayers?.first(where: { $0.name == "playerLayer" }) as? AVPlayerLayer {
            playerLayer = existingLayer
        } else {
            playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.name = "playerLayer"
            uiView.layer.addSublayer(playerLayer)
        }
        
        // Always update the frame to match view bounds
        playerLayer.frame = uiView.bounds
        
        // Ensure player is still connected
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }
}

