// SignalingClient.swift
import Foundation
import LiveKit
import CommonCrypto
import os.log
import CloudKit  // Add this import
import AVFoundation

// Add operation lock to prevent multiple simultaneous operations
private let connectionLock = NSLock()
private let logger = OSLog(subsystem: "com.buzzaboo", category: "Signaling")

class VideoDebugger {
    static let shared = VideoDebugger()
    private var logMessages: [String] = []
    
    func log(_ message: String, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(message)"
        print("DEBUG: \(logMessage)")
        logMessages.append(logMessage)
    }
    
    func dumpLogs() -> String {
        return logMessages.joined(separator: "\n")
    }
    
    func checkVideoTrack(_ track: VideoTrack?) -> Bool {
        guard let track = track else {
            log("Video track is nil")
            return false
        }
        
        if let dimensions = track.dimensions {
            log("Video track dimensions: \(dimensions.width) x \(dimensions.height)")
        } else {
            log("Video track has no dimensions")
        }
        
        log("Video track stats: sid=\(track.sid?.stringValue)")
        return true
    }
    
    func checkVideoView(_ view: VideoView?) -> Bool {
        guard let view = view else {
            log("VideoView is nil")
            return false
        }
        
        log("VideoView stats: enabled=\(view.isEnabled), track=\(view.track != nil ? "set" : "nil")")
        
        // Check if the view is properly laid out
        if view.bounds.width < 10 || view.bounds.height < 10 {
            log("VideoView has invalid size: \(view.bounds)")
            return false
        }
        
        return view.isEnabled && view.track != nil
    }
}

class SignalingClient: ObservableObject {
    // Remove the static shared room
    static let sharedInstance = SignalingClient(userId: "temporary")
    
    @Published var room: Room
    @Published private(set) var userId: String
    private var isConnecting = false
    var activeSessionID: CKRecord.ID?
    
    init(userId: String) {
        self.userId = userId
        // Create a fresh Room instance for each client
        self.room = Room()
        self.room.add(delegate: self)
        os_log("SignalingClient initialized with user ID: %{public}@", log: logger, type: .default, userId)
        VideoDebugger.shared.log("SignalingClient initialized with user ID: \(userId)")
    }
    
    func connectToLiveKit(completion: @escaping (Bool) -> Void) {
        // Use a lock to prevent multiple simultaneous connection attempts
        guard connectionLock.try() else {
            VideoDebugger.shared.log("Connection already in progress, ignoring duplicate request")
            completion(false)
            return
        }
        
        // Set flag to track connecting state
        isConnecting = true
        VideoDebugger.shared.log("Starting connection process")
        
        Task {
            defer {
                connectionLock.unlock()
                isConnecting = false
            }
            
            do {
                // Create a completely new room to avoid any stale state
                self.room = Room()
                self.room.add(delegate: self)
                VideoDebugger.shared.log("Created fresh Room instance")
                
                // Use a fixed room name for simplicity
                let roomName = "test-room"
                let token = try generateToken(room: roomName, identity: userId)
                
                let serverUrl = "wss://livekit.buzzaboo.com:443"
                VideoDebugger.shared.log("Connecting to LiveKit at \(serverUrl)")
                
                // Connect with standard options
                let options = ConnectOptions(autoSubscribe: true)
                // Only use the parameters your SDK version supports
                try await room.connect(url: serverUrl, token: token, connectOptions: options)
                
                VideoDebugger.shared.log("Connected to LiveKit room: \(roomName)")
                
                // IMPORTANT: Explicitly read camera position from UserDefaults
                let useBackCamera = UserDefaults.standard.bool(forKey: "useBackCamera")
                let cameraPosition: AVCaptureDevice.Position = useBackCamera ? .back : .front
                VideoDebugger.shared.log("Using camera position: \(cameraPosition == .back ? "back" : "front")")

                // First disable any existing camera
                try await room.localParticipant.setCamera(enabled: false)

                // Create the track with explicit camera position
                let cameraOptions = CameraCaptureOptions(position: cameraPosition)
                let videoTrack = LocalVideoTrack.createCameraTrack(options: cameraOptions)

                // Publish the track manually
                try await room.localParticipant.publish(videoTrack: videoTrack)
                VideoDebugger.shared.log("Published camera track with position: \(cameraPosition == .back ? "back" : "front")")
                
                // Just a short delay
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                VideoDebugger.shared.log("Failed to connect to LiveKit: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    private func handleParticipant(_ participant: RemoteParticipant) {
        os_log("Handling participant %{public}@", log: logger, type: .info, participant.identity?.description ?? "unknown")
        VideoDebugger.shared.log("Handling participant \(participant.identity?.description ?? "unknown")")
        
        if let matchedId = UserDefaults.standard.string(forKey: "matchedUserIdentifier"),
           let participantId = participant.identity?.description,
           participantId == matchedId {
            os_log("1:1 P2P connection established with %{public}@", log: logger, type: .info, matchedId)
            VideoDebugger.shared.log("1:1 P2P connection established with \(matchedId)")
        }
    }
    
    func generateToken(room: String, identity: String, canPublish: Bool = true, canSubscribe: Bool = true) throws -> String {
        let apiKey = "APILujeXtU8Y5ae"
        let apiSecret = "jXU2ffVOPJWIzkn8gHEihe9vQPoV6zFefsjHd0x6gAdA"
        
        // Clean the identity - use the provided identity if it's valid
        let validIdentity = identity.isEmpty || identity == "temporary" ?
            "user-\(UUID().uuidString)" : identity.replacingOccurrences(of: ".", with: "-")
        
        VideoDebugger.shared.log("Using identity: \(validIdentity)")
        
        // Create the JWT token manually
        let header = ["alg": "HS256", "typ": "JWT"]
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let headerBase64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let nowSeconds = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": apiKey,
            "sub": validIdentity,
            "nbf": nowSeconds,
            "exp": nowSeconds + 3600,
            "video": [
                "room": room,
                "roomJoin": true,
                "canPublish": canPublish,
                "canSubscribe": canSubscribe,
                "canPublishData": true,  // Make sure this is true!
                "canSubscribeData": true // Add this line!
            ]
        ]
    
        
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let toSign = headerBase64 + "." + payloadBase64
        
        guard let secretData = apiSecret.data(using: .utf8),
              let signatureInput = toSign.data(using: .utf8) else {
            throw NSError(domain: "JWT", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid data for signing"])
        }
        
        // Calculate HMAC-SHA256
        var digestBytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        secretData.withUnsafeBytes { secretBytes in
            signatureInput.withUnsafeBytes { inputBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                      secretBytes.baseAddress, secretData.count,
                      inputBytes.baseAddress, signatureInput.count,
                      &digestBytes)
            }
        }
        
        let signature = Data(digestBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let token = headerBase64 + "." + payloadBase64 + "." + signature
        return token
    }
    
    func createActiveSession(roomId: String, participant1: String, participant2: String) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Create a new ActiveSession record
        let record = CKRecord(recordType: "ActiveSession")
        record["roomId"] = roomId
        record["participant1"] = participant1
        record["participant2"] = participant2
        record["status"] = "active"
        record["startTime"] = Date()
        
        // Save the record to CloudKit
        database.save(record) { savedRecord, error in
            if let error = error {
                print("Failed to create ActiveSession: \(error.localizedDescription)")
            } else {
                print("✅ Created ActiveSession for room: \(roomId)")
                
                // Store the session ID for later cleanup
                if let recordID = savedRecord?.recordID {
                    self.activeSessionID = recordID
                }
            }
        }
    }
    
    func endActiveSession() {
        guard let sessionID = activeSessionID else {
            return
        }
        
        let database = CKContainer.default().publicCloudDatabase
        
        // Delete the record
        database.delete(withRecordID: sessionID) { _, error in
            if let error = error {
                print("Failed to delete ActiveSession: \(error.localizedDescription)")
            } else {
                print("✅ Deleted ActiveSession")
                self.activeSessionID = nil
            }
        }
    }
    
    func disconnect() {
        Task {
            VideoDebugger.shared.log("Disconnecting from LiveKit room for user \(userId)")
            
            // End any active sessions first
            endActiveSession()
            
            // Disable camera and microphone before disconnecting
            do {
                try await room.localParticipant.setCamera(enabled: false)
                try await room.localParticipant.setMicrophone(enabled: false)
            } catch {
                VideoDebugger.shared.log("Error disabling media: \(error)")
            }
            
            // Now disconnect
            await room.disconnect()
            
            // Additional cleanup
            room.remove(delegate: self)
            
            os_log("Disconnected from LiveKit room for user %{public}@", log: logger, type: .info, userId)
        }
    }
}

extension SignalingClient: RoomDelegate {
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication, track: Track) {
        os_log("Track subscribed: %{public}@", log: logger, type: .info, String(describing: track.kind))
        VideoDebugger.shared.log("Track subscribed: \(String(describing: track.kind))")
    }
    
    func room(_ room: Room, didConnect participant: RemoteParticipant) {
        handleParticipant(participant)
        VideoDebugger.shared.log("Room did connect participant: \(participant.identity?.stringValue ?? "unknown")")
    }
    
    func room(_ room: Room, didFailToConnectWithError error: Error) {
        os_log("Failed to connect to room: %{public}@", log: logger, type: .error, error.localizedDescription)
        VideoDebugger.shared.log("Failed to connect to room: \(error.localizedDescription)")
    }
    
    func room(_ room: Room, didDisconnectWithError error: Error?) {
        if let error = error {
            os_log("Room disconnected with error: %{public}@", log: logger, type: .error, error.localizedDescription)
            VideoDebugger.shared.log("Room disconnected with error: \(error.localizedDescription)")
        } else {
            os_log("Room disconnected normally", log: logger, type: .info)
            VideoDebugger.shared.log("Room disconnected normally")
        }
        
        // Make sure to end the active session when disconnected
        endActiveSession()
    }
}
