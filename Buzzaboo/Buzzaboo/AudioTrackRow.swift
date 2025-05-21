// Create a file named AudioTrackRow.swift with the following content:

import SwiftUI
import AVFoundation

struct AudioTrackRow: View {
    let track: AudioTrack
    let isPlaying: Bool
    let onTap: () -> Void
    let onUse: () -> Void
    
    var body: some View {
        HStack {
            // Play/Pause button
            Button(action: onTap) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
            }
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("By \(track.creator) • \(formattedDuration)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Use button
            Button(action: onUse) {
                Text("Use")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.black)
    }
    
    private var formattedDuration: String {
        let minutes = Int(track.duration) / 60
        let seconds = Int(track.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
