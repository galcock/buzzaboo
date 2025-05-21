import SwiftUI
import AVFoundation

struct AudioRecorderView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var recordingURL: URL?
    @State private var recordingTitle: String
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @Binding var selectedAudioTrack: AudioTrack?
    @Environment(\.presentationMode) var presentationMode
    let creatorName: String
    
    // Add an audio session property to maintain throughout the view lifecycle
    @State private var audioSession = AVAudioSession.sharedInstance()
    
    init(selectedAudioTrack: Binding<AudioTrack?>, creatorName: String, initialTitle: String = "") {
        self._selectedAudioTrack = selectedAudioTrack
        self.creatorName = creatorName
        self._recordingTitle = State(initialValue: initialTitle.isEmpty ? "My Recording" : "Sound - \(initialTitle)")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Spacer()
                    
                    // Visual feedback for recording/playback
                    ZStack {
                        Circle()
                            .stroke(isRecording || isPlaying ? Color.red : Color.gray, lineWidth: 4)
                            .frame(width: 150, height: 150)
                        
                        if isRecording {
                            // Recording animation
                            ForEach(0..<3) { i in
                                Circle()
                                    .stroke(Color.red.opacity(0.8), lineWidth: 2)
                                    .frame(width: CGFloat(80 + i * 30), height: CGFloat(80 + i * 30))
                                    .scaleEffect(isRecording ? 1.2 : 0.8)
                                    .opacity(isRecording ? 0.2 : 0.8)
                                    .animation(Animation.easeInOut(duration: 1).repeatForever().delay(Double(i) * 0.2), value: isRecording)
                            }
                        }
                        
                        // Record/Play button
                        Button(action: {
                            if recordingURL == nil {
                                toggleRecording()
                            } else {
                                togglePlayback()
                            }
                        }) {
                            Image(systemName: recordingURL == nil ?
                                  (isRecording ? "stop.fill" : "mic.fill") :
                                  (isPlaying ? "stop.fill" : "play.fill"))
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .frame(width: 80, height: 80)
                        }
                    }
                    
                    // Time display
                    Text(timeString(from: elapsedTime))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    if recordingURL != nil {
                        // Title input
                        TextField("Name your sound", text: $recordingTitle)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Control buttons
                    if recordingURL != nil {
                        HStack(spacing: 30) {
                            Button("Discard") {
                                discardRecording()
                            }
                            .foregroundColor(.red)
                            
                            Button("Save") {
                                saveRecording()
                            }
                            .foregroundColor(.blue)
                            .disabled(recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationBarTitle("Record Sound", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    cleanupAndDismiss()
                }
            )
        }
        .onAppear {
            setupAudioSession()
        }
        .onDisappear {
            // Clean up all audio resources
            stopRecording()
            stopPlayback()
            deactivateAudioSession()
        }
    }
    
    private func setupAudioSession() {
        do {
            // Configure the audio session for recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Set up recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        
        // Set up recorder with better settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            // Make sure audio session is active
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }
            
            // Create the recorder
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            // Start timer
            startTimer()
            
            isRecording = true
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        
        if let url = audioRecorder?.url, FileManager.default.fileExists(atPath: url.path) {
            recordingURL = url
        }
        
        stopTimer()
        isRecording = false
        
        // Cleanup the recorder
        audioRecorder = nil
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let url = recordingURL else { return }
        
        do {
            // Configure session for playback
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            // Start timer
            elapsedTime = 0
            startTimer()
            isPlaying = true
        } catch {
            print("Could not start playback: \(error)")
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        stopTimer()
        isPlaying = false
        
        // Cleanup the player
        audioPlayer = nil
        
        // Reset session to recording
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        } catch {
            print("Could not reset audio session: \(error)")
        }
    }
    
    private func discardRecording() {
        if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        recordingURL = nil
        elapsedTime = 0
    }
    
    private func saveRecording() {
        guard let url = recordingURL else { return }
        
        // Make a local copy to ensure it persists
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let permanentURL = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        
        do {
            try FileManager.default.copyItem(at: url, to: permanentURL)
            
            // Get duration
            let asset = AVAsset(url: permanentURL)
            let duration = asset.duration.seconds
            
            // Use a title that isn't empty
            let finalTitle = recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                             "Sound - \(creatorName)" : recordingTitle
            
            // Save to AudioLibraryManager
            AudioLibraryManager.shared.saveAudioTrack(
                title: finalTitle,
                creator: creatorName,
                duration: duration,
                audioURL: permanentURL,
                isOriginalAudio: true,
                sourceVideoId: nil
            ) { audioTrack in
                DispatchQueue.main.async {
                    if let audioTrack = audioTrack {
                        self.selectedAudioTrack = audioTrack
                        self.cleanupAndDismiss()
                    }
                }
            }
        } catch {
            print("Error saving recording: \(error)")
        }
    }
    
    private func cleanupAndDismiss() {
        stopRecording()
        stopPlayback()
        deactivateAudioSession()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func startTimer() {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if isRecording {
                elapsedTime = audioRecorder?.currentTime ?? 0
            } else if isPlaying {
                elapsedTime = audioPlayer?.currentTime ?? 0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}
