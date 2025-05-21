// BuzzabooApp.swift
import SwiftUI
import CloudKit
import UIKit
import AuthenticationServices
import AVFoundation
import Vision
import CoreImage
import AudioToolbox

@main
struct BuzzabooApp: App {
    // Use this to track the app state
    @State private var isShowingSplash = true
    
    // Add delegate adaptor for URL handling
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    // Initialize a global listener for chat messages
    init() {
        // Force front camera as default
        UserDefaults.standard.set(false, forKey: "useBackCamera")
        print("Setting default camera to front camera")
        
        setupGlobalChatListener()
        
        // Apply subtle beauty enhancement to the camera
        configureCameraForBeauty()
        
        // Configure our beauty filter settings
        BeautyFilter.shared.configure(
            skinSmoothing: 0.35,   // Adjust for less/more skin smoothing
            brightness: 0.15,      // Adjust for less/more brightness
            contrast: 0.10,        // Adjust for less/more contrast
            saturation: 0.15       // Adjust for less/more vibrant colors
        )
    }
    
    var body: some Scene {
        WindowGroup {
            // This is the key change - split content based on app state
            Group {
                if isShowingSplash {
                    // ONLY show the splash initially
                    SplashScreenView()
                        .onAppear {
                            // Verify CloudKit setup in the background while splash is showing
                            verifyCloudKitSetup()
                            
                            // After showing splash, THEN load the main app
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation {
                                    isShowingSplash = false
                                }
                            }
                        }
                } else {
                    // Only initialize LoginView after splash is shown
                    LoginView()
                }
            }
            // Add URL handling for Twitter OAuth callback
            .onOpenURL { url in
                if url.scheme == "buzzaboo" {
                    print("Received callback URL: \(url)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TwitterAuthCallback"),
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
            }
        }
    }
    
    private func configureCameraForBeauty() {
        // Adjust these parameters to control the strength of the beauty effect
        let exposureBoost: Float = 0.8   // Range: 0.0 to 0.5 (higher = brighter skin)
        
        // Find the front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            // 1. Boost exposure for brightness (adjustable)
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                let currentBias = device.exposureTargetBias
                let beautyBias = min(currentBias + exposureBoost, device.maxExposureTargetBias)
                device.setExposureTargetBias(beautyBias)
                print("Applied exposure enhancement: \(exposureBoost)")
            }
            
            // 2. Enhance skin tones with better white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("Applied enhanced white balance")
            }
            
            // 3. Enable auto-focus with face detection if available
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }
                
                print("Applied enhanced auto-focus")
            }
            
            device.unlockForConfiguration()
            print("Camera beauty filter applied with exposureBoost: \(exposureBoost)")
            
        } catch {
            print("Could not configure camera: \(error)")
        }
    }

    // Advanced face beauty processing
    private func setupFaceBeautyProcessor(
        skinSmoothingLevel: Float,
        faceSlimmingLevel: Float,
        eyeEnhancementLevel: Float,
        eyebrowDefinitionLevel: Float
    ) {
        // Create a shared instance of our beauty processor
        BeautyFilterProcessor.shared.configure(
            skinSmoothingLevel: skinSmoothingLevel,
            faceSlimmingLevel: faceSlimmingLevel,
            eyeEnhancementLevel: eyeEnhancementLevel,
            eyebrowDefinitionLevel: eyebrowDefinitionLevel
        )
        
        // Register for notifications when LiveKit camera is initialized
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LiveKitCameraInitialized"),
            object: nil,
            queue: .main
        ) { notification in
            if let captureSession = notification.object as? AVCaptureSession {
                BeautyFilterProcessor.shared.attachToSession(captureSession)
            }
        }
        
        print("Advanced beauty filter processor registered")
    }
    
    // Setup a global listener for chat messages that will work regardless of UI state
    private func setupGlobalChatListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GlobalChatMessageReceived"),
            object: nil,
            queue: .main
        ) { notification in
            if let message = notification.userInfo?["message"] as? ChatMessage {
                print("🌎 GLOBAL RECEIVED MESSAGE: \(message.sender): \(message.message)")
                
                // Show a global toast notification
                showMessageToast(message: "\(message.sender): \(message.message)")
            } else if let sender = notification.userInfo?["sender"] as? String,
                      let messageText = notification.userInfo?["message"] as? String {
                print("🌎 GLOBAL RECEIVED MESSAGE COMPONENTS: \(sender): \(messageText)")
                
                // Show a global toast notification
                showMessageToast(message: "\(sender): \(messageText)")
            }
        }
        
        // Also listen for the app-specific notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ReceivedChatMessage"),
            object: nil,
            queue: .main
        ) { notification in
            if let sender = notification.userInfo?["sender"] as? String,
               let messageText = notification.userInfo?["message"] as? String {
                print("🌎 APP-SPECIFIC MESSAGE: \(sender): \(messageText)")
                
                // Show a global toast notification
                showMessageToast(message: "\(sender): \(messageText)")
            }
        }
    }
    
    // Helper function to show a toast message over any UI
    private func showMessageToast(message: String) {
        // Find the key window and controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return
        }
        
        // Find the top-most presented controller
        var topController = rootVC
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        // Create a toast view
        let toastContainer = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastContainer.layer.cornerRadius = 10
        
        let messageLabel = UILabel(frame: CGRect(x: 10, y: 10, width: 280, height: 60))
        messageLabel.textColor = .white
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        
        toastContainer.addSubview(messageLabel)
        toastContainer.center = topController.view.center
        toastContainer.alpha = 0
        
        // Add to view and animate
        DispatchQueue.main.async {
            topController.view.addSubview(toastContainer)
            
            UIView.animate(withDuration: 0.3, animations: {
                toastContainer.alpha = 1
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                    toastContainer.alpha = 0
                }) { _ in
                    toastContainer.removeFromSuperview()
                }
            }
        }
    }
    
    func verifyCloudKitSetup() {
        // Check iCloud status first
        CKContainer.default().accountStatus { status, error in
            logMessage("iCloud status: \(status.rawValue), error: \(error?.localizedDescription ?? "none")")
            
            // If iCloud is not available, don't continue with schema checks
            guard status == .available else {
                logMessage("⚠️ iCloud is not available, skipping schema verification")
                return
            }
            
            // Get the database
            let database = CKContainer.default().publicCloudDatabase
            
            // Use a dispatch group to track all operations
            let group = DispatchGroup()
            
            // Check UserProfile schema with better error handling
            group.enter()
            let profileQuery = CKQuery(recordType: "UserProfile", predicate: NSPredicate(value: true))
            let profileOperation = CKQueryOperation(query: profileQuery)
            profileOperation.resultsLimit = 1
            
            profileOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking record: \(error.localizedDescription)")
                }
            }
            
            profileOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("UserProfile schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("UserProfile schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema if possible
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create UserProfile schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "UserProfile")
                        templateRecord["identifier"] = "template"
                        templateRecord["firstName"] = "Template User"
                        templateRecord["likeCount"] = 0
                        templateRecord["reportCount"] = 0
                        templateRecord["lastActiveTime"] = Date()
                        templateRecord["likedUsers"] = [String]()
                        templateRecord["matches"] = [String]()
                        
                        database.save(templateRecord) { _, _ in
                            // Just trying to create schema, result doesn't matter
                        }
                    }
                }
            }
            
            database.add(profileOperation)
            
            // Check UserVideo schema
            group.enter()
            let videoQuery = CKQuery(recordType: "UserVideo", predicate: NSPredicate(value: true))
            let videoOperation = CKQueryOperation(query: videoQuery)
            videoOperation.resultsLimit = 1
            
            videoOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking video record: \(error.localizedDescription)")
                }
            }
            
            videoOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("UserVideo schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("UserVideo schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema if possible
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create UserVideo schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "UserVideo")
                        templateRecord["owner"] = "template"
                        templateRecord["title"] = "Template Video"
                        templateRecord["views"] = 0
                        templateRecord["likes"] = 0
                        templateRecord["dateUploaded"] = Date()
                        templateRecord["videoId"] = UUID().uuidString
                        
                        database.save(templateRecord) { _, _ in
                            // Just trying to create schema, result doesn't matter
                        }
                    }
                }
            }
            
            database.add(videoOperation)
            
            // Add AudioTrack schema check
            group.enter()
            let audioTrackQuery = CKQuery(recordType: "AudioTrack", predicate: NSPredicate(value: true))
            let audioTrackOperation = CKQueryOperation(query: audioTrackQuery)
            audioTrackOperation.resultsLimit = 1

            audioTrackOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking audio track record: \(error.localizedDescription)")
                }
            }

            audioTrackOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("AudioTrack schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("AudioTrack schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema more forcefully
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create AudioTrack schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "AudioTrack")
                        templateRecord["title"] = "Template Audio Track"
                        templateRecord["creator"] = "System"
                        templateRecord["duration"] = 30.0
                        templateRecord["usageCount"] = 0
                        templateRecord["audioId"] = UUID().uuidString
                        templateRecord["isOriginalAudio"] = true
                        
                        // Create a temporary audio file
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("template.m4a")
                        let dummyData = Data([0, 0, 0, 0]) // Minimal valid data
                        try? dummyData.write(to: tempURL)
                        let asset = CKAsset(fileURL: tempURL)
                        templateRecord["audioFile"] = asset
                        
                        database.save(templateRecord) { savedRecord, saveError in
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                            
                            if let saveError = saveError {
                                logMessage("Failed to create AudioTrack schema: \(saveError.localizedDescription)")
                            } else {
                                logMessage("Successfully created AudioTrack schema")
                            }
                        }
                    }
                }
            }

            database.add(audioTrackOperation)
            
            // Check ActiveSession schema
            group.enter()
            let sessionQuery = CKQuery(recordType: "ActiveSession", predicate: NSPredicate(value: true))
            let sessionOperation = CKQueryOperation(query: sessionQuery)
            sessionOperation.resultsLimit = 1
            
            sessionOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking session record: \(error.localizedDescription)")
                }
            }
            
            sessionOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("ActiveSession schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("ActiveSession schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema if possible
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create ActiveSession schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "ActiveSession")
                        templateRecord["roomId"] = "template-room"
                        templateRecord["participant1"] = "template-user-1"
                        templateRecord["participant2"] = "template-user-2"
                        templateRecord["status"] = "inactive"
                        templateRecord["startTime"] = Date()
                        
                        database.save(templateRecord) { _, _ in
                            // Just trying to create schema, result doesn't matter
                        }
                    }
                }
            }
            
            database.add(sessionOperation)
            
            // Check CallRequest schema
            group.enter()
            let callRequestQuery = CKQuery(recordType: "CallRequest", predicate: NSPredicate(value: true))
            let callRequestOperation = CKQueryOperation(query: callRequestQuery)
            callRequestOperation.resultsLimit = 1
            
            callRequestOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking call request record: \(error.localizedDescription)")
                }
            }
            
            callRequestOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("CallRequest schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("CallRequest schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema if possible
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create CallRequest schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "CallRequest")
                        templateRecord["senderId"] = "template-sender"
                        templateRecord["senderName"] = "Template Sender"
                        templateRecord["receiverId"] = "template-receiver"
                        templateRecord["status"] = "inactive"
                        templateRecord["timestamp"] = Date()
                        templateRecord["requestId"] = UUID().uuidString
                        
                        database.save(templateRecord) { _, _ in
                            // Just trying to create schema, result doesn't matter
                        }
                    }
                }
            }
            
            database.add(callRequestOperation)
            
            // Check ChatMessage schema
            group.enter()
            let chatMessageQuery = CKQuery(recordType: "ChatMessage", predicate: NSPredicate(value: true))
            let chatMessageOperation = CKQueryOperation(query: chatMessageQuery)
            chatMessageOperation.resultsLimit = 1
            
            chatMessageOperation.recordMatchedBlock = { (recordID, result) in
                // Just counting records
                switch result {
                case .success(_):
                    break // Found a record
                case .failure(let error):
                    logMessage("Error checking chat message record: \(error.localizedDescription)")
                }
            }
            
            chatMessageOperation.queryResultBlock = { result in
                defer { group.leave() }
                
                switch result {
                case .success:
                    logMessage("ChatMessage schema confirmed")
                case .failure(let error):
                    // Log error but don't crash
                    logMessage("ChatMessage schema check failed: \(error.localizedDescription)")
                    
                    // Try to create the schema if possible
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        logMessage("Attempting to create ChatMessage schema with first record")
                        
                        // Create a template record to establish schema
                        let templateRecord = CKRecord(recordType: "ChatMessage")
                        templateRecord["senderID"] = "template-sender"
                        templateRecord["senderName"] = "Template User"
                        templateRecord["receiverID"] = "template-receiver"
                        templateRecord["roomID"] = "template-room"
                        templateRecord["message"] = "Template message"
                        templateRecord["timestamp"] = Date()
                        templateRecord["messageID"] = UUID().uuidString
                        
                        database.save(templateRecord) { _, _ in
                            // Just trying to create schema, result doesn't matter
                        }
                    }
                }
            }
            
            database.add(chatMessageOperation)
            
            // After all checks, wait for completion
            group.notify(queue: .main) {
                logMessage("CloudKit schema verification complete")
            }
        }
    }
}

// Add this class for URL handling
class AppDelegate: NSObject, UIApplicationDelegate {
    // Add to AppDelegate
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        return true
    }
    
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "buzzaboo" {
            print("AppDelegate received URL: \(url)")
            NotificationCenter.default.post(
                name: NSNotification.Name("TwitterAuthCallback"),
                object: nil,
                userInfo: ["url": url]
            )
            return true
        }
        return false
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}


struct SplashScreenView: View {
    // MARK: ‑ Tunables
    private let buzzDuration: Double = 0.5      // 20 shakes × 0.025 s each
    
    // MARK: ‑ State
    @State private var buzzing = false
    @State private var wiggle  = false
    @State private var player: AVAudioPlayer?    // sound player
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image("logo15_500")
                .resizable()
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(buzzing ? (wiggle ? 3 : -3) : 0))
                .offset(x: buzzing ? (wiggle ? 2 : -2) : 0)
                .scaleEffect(buzzing ? 1.03 : 1)
        }
        .onAppear {
            playBuzzSound()                                   // 🔊 new
            buzzing = true
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            
            withAnimation(.easeInOut(duration: 0.025)
                            .repeatCount(20, autoreverses: true)) {
                wiggle.toggle()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + buzzDuration) {
                buzzing = false
                wiggle  = false
            }
        }
    }
    
    // MARK: ‑ Private
    private func playBuzzSound() {
        guard let url = Bundle.main.url(forResource: "buzzaboo", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("⚠️  Couldn’t load buzzaboo.mp3: \(error.localizedDescription)")
        }
    }
}

class BeautyFilterProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = BeautyFilterProcessor()
    
    private var skinSmoothingLevel: Float = 0.4
    private var faceSlimmingLevel: Float = 0.3
    private var eyeEnhancementLevel: Float = 0.3
    private var eyebrowDefinitionLevel: Float = 0.3
    
    private let context = CIContext()
    private var faceDetectionRequest: VNDetectFaceLandmarksRequest?
    private var attachedSession: AVCaptureSession?
    
    private override init() {
        super.init()
        setupFaceDetection()
    }
    
    func configure(
        skinSmoothingLevel: Float,
        faceSlimmingLevel: Float,
        eyeEnhancementLevel: Float,
        eyebrowDefinitionLevel: Float
    ) {
        self.skinSmoothingLevel = skinSmoothingLevel
        self.faceSlimmingLevel = faceSlimmingLevel
        self.eyeEnhancementLevel = eyeEnhancementLevel
        self.eyebrowDefinitionLevel = eyebrowDefinitionLevel
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            if let error = error {
                print("Face detection error: \(error)")
                return
            }
            
            // Face landmarks will be processed when applying filters
        }
    }
    
    func attachToSession(_ session: AVCaptureSession) {
        // Avoid attaching more than once
        guard attachedSession == nil else { return }
        
        // Only attach if session is running
        guard session.isRunning else {
            print("Cannot attach to non-running session")
            return
        }
        
        // Find existing video output or create a new one
        let videoOutput: AVCaptureVideoDataOutput
        
        if let existingOutput = session.outputs.first(where: { $0 is AVCaptureVideoDataOutput }) as? AVCaptureVideoDataOutput {
            videoOutput = existingOutput
        } else {
            videoOutput = AVCaptureVideoDataOutput()
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                print("Cannot add video output to session")
                return
            }
        }
        
        // Configure video output
        let processingQueue = DispatchQueue(label: "com.buzzaboo.videoBeautyProcessing")
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        attachedSession = session
        print("Beauty filter attached to AVCaptureSession")
    }
    
    // This method is called for each video frame
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process the video frame with our beauty filter
        let enhancedBuffer = applyBeautyFilters(to: pixelBuffer)
        
        // The enhanced buffer is automatically used by the video pipeline
    }
    
    private func applyBeautyFilters(to pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        // Create a CIImage from the pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 1. Apply skin smoothing (bilateral filter is good for skin)
        var outputImage = applySkinSmoothing(to: ciImage)
        
        // 2. Apply face slimming if face is detected
        outputImage = applyFaceSlimming(to: outputImage, originalImage: ciImage)
        
        // 3. Apply eye enhancement
        outputImage = applyEyeEnhancement(to: outputImage, originalImage: ciImage)
        
        // 4. Apply eyebrow enhancement
        outputImage = applyEyebrowEnhancement(to: outputImage, originalImage: ciImage)
        
        // Render back to the original pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        context.render(outputImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    private func applySkinSmoothing(to image: CIImage) -> CIImage {
        // Use bilateral filter for skin smoothing (preserves edges while smoothing flat areas)
        guard let filter = CIFilter(name: "CIBilateralFilter") else { return image }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(skinSmoothingLevel * 8.0, forKey: "inputSpatialRadius")
        filter.setValue(skinSmoothingLevel * 3.0, forKey: "inputIntensity")
        
        return filter.outputImage ?? image
    }
    
    private func applyFaceSlimming(to image: CIImage, originalImage: CIImage) -> CIImage {
        // Apply face slimming effect if needed
        if faceSlimmingLevel > 0.01 {
            // Apply subtle face stretching effect
            let faceTransform = CGAffineTransform(
                a: 1.0 - (CGFloat(faceSlimmingLevel) * 0.1),  // Horizontal scaling (slimming)
                b: 0.0,
                c: 0.0,
                d: 1.0,                                       // No vertical scaling
                tx: image.extent.width * (CGFloat(faceSlimmingLevel) * 0.05), // Compensate position
                ty: 0.0
            )
            
            return image.transformed(by: faceTransform)
        }
        
        return image
    }
    
    private func applyEyeEnhancement(to image: CIImage, originalImage: CIImage) -> CIImage {
        // In a real implementation, this would:
        // 1. Detect eye landmarks
        // 2. Apply local contrast enhancement around eyes
        // 3. Subtly enlarge eyes
        
        // For now, we'll simply apply a subtle local contrast boost to the image
        if eyeEnhancementLevel > 0.01 {
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return image }
            
            contrastFilter.setValue(image, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.0 + (eyeEnhancementLevel * 0.2), forKey: kCIInputContrastKey)
            
            return contrastFilter.outputImage ?? image
        }
        
        return image
    }
    
    private func applyEyebrowEnhancement(to image: CIImage, originalImage: CIImage) -> CIImage {
        // Similar to eye enhancement, this would require facial landmark detection
        // to isolate and enhance eyebrow regions
        
        // Simplified placeholder that enhances overall definition subtly
        if eyebrowDefinitionLevel > 0.01 {
            guard let sharpenFilter = CIFilter(name: "CISharpenLuminance") else { return image }
            
            sharpenFilter.setValue(image, forKey: kCIInputImageKey)
            sharpenFilter.setValue(eyebrowDefinitionLevel * 0.4, forKey: kCIInputSharpnessKey)
            
            return sharpenFilter.outputImage ?? image
        }
        
        return image
    }
}

// Add this class to your BuzzabooApp.swift
class BeautyFilter {
    static let shared = BeautyFilter()
    
    // Adjust the strength of effects (0.0 to 1.0)
    private var skinSmoothingStrength: CGFloat = 0.35
    private var brightnessBoost: CGFloat = 0.15
    private var contrastEnhancement: CGFloat = 0.10
    private var saturationBoost: CGFloat = 0.15
    
    // Set up Core Image context for processing
    private let context = CIContext()
    
    // Method to configure the filter strength
    func configure(
        skinSmoothing: CGFloat = 0.35,
        brightness: CGFloat = 0.15,
        contrast: CGFloat = 0.10,
        saturation: CGFloat = 0.15
    ) {
        skinSmoothingStrength = skinSmoothing
        brightnessBoost = brightness
        contrastEnhancement = contrast
        saturationBoost = saturation
    }
    
    // Apply beauty effects to an image
    func applyBeautyEffects(to image: CIImage) -> CIImage {
        var result = image
        
        // 1. Skin smoothing (with bilateral filter to preserve edges)
        if let smoothFilter = CIFilter(name: "CIBilateralFilter") {
            smoothFilter.setValue(result, forKey: kCIInputImageKey)
            smoothFilter.setValue(skinSmoothingStrength * 8.0, forKey: "inputSpatialRadius")
            smoothFilter.setValue(skinSmoothingStrength * 3.0, forKey: "inputIntensity")
            
            if let output = smoothFilter.outputImage {
                result = output
            }
        }
        
        // 2. Brightness, contrast and saturation enhancement
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(result, forKey: kCIInputImageKey)
            colorFilter.setValue(brightnessBoost, forKey: kCIInputBrightnessKey)
            colorFilter.setValue(1.0 + contrastEnhancement, forKey: kCIInputContrastKey)
            colorFilter.setValue(1.0 + saturationBoost, forKey: kCIInputSaturationKey)
            
            if let output = colorFilter.outputImage {
                result = output
            }
        }
        
        // 3. Add very subtle glow (for the "Hollywood" look)
        if let glowFilter = CIFilter(name: "CIGloom") {
            glowFilter.setValue(result, forKey: kCIInputImageKey)
            glowFilter.setValue(0.2, forKey: kCIInputIntensityKey)
            glowFilter.setValue(5.0, forKey: kCIInputRadiusKey)
            
            if let output = glowFilter.outputImage {
                // Blend original with glowed version (25% glow, 75% original)
                result = output.composited(over: result).applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: result]
                )
            }
        }
        
        return result
    }
}
