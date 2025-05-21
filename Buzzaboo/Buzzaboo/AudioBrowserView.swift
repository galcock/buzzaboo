// Updated AudioBrowserView.swift
import SwiftUI
import AVFoundation

struct AudioBrowserView: View {
    @State private var audioTracks: [AudioTrack] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var currentlyPlaying: UUID?
    @State private var audioPlayer: AVAudioPlayer?
    @Binding var selectedAudioTrack: AudioTrack?
    @State private var showAudioRecorder = false
    @Environment(\.presentationMode) var presentationMode
    
    // Current user name for audio credits
    let userName = UserDefaults.standard.string(forKey: "firstName") ?? "User"
    
    var filteredTracks: [AudioTrack] {
        if searchText.isEmpty {
            return audioTracks
        } else {
            return audioTracks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.creator.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search sounds", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                    .padding()
                    
                    if isLoading {
                        Spacer()
                        PulsingLoaderView()
                        Spacer()
                    } else if audioTracks.isEmpty {
                        Spacer()
                        Text("No audio tracks available")
                            .foregroundColor(.white)
                        Spacer()
                    } else {
                        // Audio tracks list
                        List {
                            ForEach(filteredTracks) { track in
                                AudioTrackRow(
                                    track: track,
                                    isPlaying: currentlyPlaying == track.id,
                                    onTap: {
                                        togglePlayback(for: track)
                                    },
                                    onUse: {
                                        selectedAudioTrack = track
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                )
                            }
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.black)
                    }
                }
            }
            .navigationBarTitle("Select Sound", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Original") {
                    // Now properly opens the audio recorder
                    showAudioRecorder = true
                }
            )
            .sheet(isPresented: $showAudioRecorder) {
                AudioRecorderView(
                    selectedAudioTrack: $selectedAudioTrack,
                    creatorName: userName
                )
                .onDisappear {
                    if selectedAudioTrack != nil {
                        // If recording was successful, dismiss the browser
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadAudioTracks()
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // In AudioBrowserView
    private func loadAudioTracks() {
        isLoading = true
        
        // Print debugging info
        print("Starting to load audio tracks...")
        
        AudioLibraryManager.shared.fetchPopularAudioTracks { tracks in
            DispatchQueue.main.async {
                print("Received \(tracks.count) audio tracks from manager")
                // Add debugging info for any track with non-nil URL
                for track in tracks {
                    if let url = track.fileURL {
                        print("Track: \(track.title) has URL: \(url.path)")
                        // Check if file exists
                        if FileManager.default.fileExists(atPath: url.path) {
                            print("✅ File exists at path")
                        } else {
                            print("❌ File does NOT exist at path")
                        }
                    } else {
                        print("Track: \(track.title) has no URL")
                    }
                }
                
                self.audioTracks = tracks
                self.isLoading = false
            }
        }
    }
    
    private func togglePlayback(for track: AudioTrack) {
        // Stop current playback if any
        stopPlayback()
        
        // If we're tapping on the currently playing track, just stop playback
        if currentlyPlaying == track.id {
            currentlyPlaying = nil
            return
        }
        
        // Start playing the selected track
        guard let url = track.fileURL else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            currentlyPlaying = track.id
        } catch {
            print("Error playing audio: \(error)")
        }
    }
    
    private func stopPlayback() {
        if audioPlayer?.isPlaying ?? false {
            audioPlayer?.stop()
        }
        audioPlayer = nil
        currentlyPlaying = nil
    }
}
