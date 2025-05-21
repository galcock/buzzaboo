// AudioTrack.swift
import Foundation
import CloudKit
import AVFoundation  // Add this import for AVAsset and AVAssetExportSession

struct AudioTrack: Identifiable {
    let id: UUID
    let title: String
    let creator: String
    let duration: TimeInterval
    let usageCount: Int
    let audioId: String
    let fileURL: URL?
    let isOriginalAudio: Bool // True if extracted from a video
    let sourceVideoId: String? // Reference to video if extracted
    
    // CloudKit record ID for updates
    var recordId: CKRecord.ID?
}

class AudioLibraryManager {
    static let shared = AudioLibraryManager()
    
    // Fetch popular audio tracks
    func fetchPopularAudioTracks(completion: @escaping ([AudioTrack]) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        
        // Query for audio tracks ordered by usage count
        let query = CKQuery(recordType: "AudioTrack", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "usageCount", ascending: false)]
        
        print("Starting audio tracks fetch query...")
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 50
        
        var tracks: [AudioTrack] = []
        
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let record):
                print("Found audio track record: \(record.recordID.recordName)")
                if let title = record["title"] as? String,
                   let creator = record["creator"] as? String,
                   let duration = record["duration"] as? TimeInterval,
                   let usageCount = record["usageCount"] as? Int,
                   let audioId = record["audioId"] as? String,
                   let isOriginalAudio = record["isOriginalAudio"] as? Bool {
                    
                    var fileURL: URL? = nil
                    
                    // Get audio file URL
                    if let audioAsset = record["audioFile"] as? CKAsset,
                       let assetURL = audioAsset.fileURL {
                        
                        // Verify file exists
                        if FileManager.default.fileExists(atPath: assetURL.path) {
                            print("Audio file exists at path: \(assetURL.path)")
                            
                            // Create local copy in temp directory
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(audioId).m4a")
                            
                            do {
                                if FileManager.default.fileExists(atPath: tempURL.path) {
                                    try FileManager.default.removeItem(at: tempURL)
                                }
                                
                                try FileManager.default.copyItem(at: assetURL, to: tempURL)
                                fileURL = tempURL
                                print("Successfully copied audio to: \(tempURL.path)")
                            } catch {
                                print("Error creating local audio copy: \(error)")
                            }
                        } else {
                            print("Audio file does NOT exist at path: \(assetURL.path)")
                        }
                    } else {
                        print("No audio asset found in record")
                    }
                    
                    let sourceVideoId = record["sourceVideoId"] as? String
                    
                    let audioTrack = AudioTrack(
                        id: UUID(),
                        title: title,
                        creator: creator,
                        duration: duration,
                        usageCount: usageCount,
                        audioId: audioId,
                        fileURL: fileURL,
                        isOriginalAudio: isOriginalAudio,
                        sourceVideoId: sourceVideoId,
                        recordId: record.recordID
                    )
                    
                    tracks.append(audioTrack)
                    print("Added audio track to results: \(title)")
                } else {
                    print("Record missing required fields")
                }
            case .failure(let error):
                print("Error fetching audio track: \(error)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                print("Audio track query completed successfully with \(tracks.count) tracks")
            case .failure(let error):
                print("Audio track query failed: \(error.localizedDescription)")
            }
            completion(tracks)
        }
        
        database.add(operation)
    }
    
    // Extract audio from video and save as an audio track
    func extractAudioFromVideo(videoURL: URL, title: String, creator: String, completion: @escaping (AudioTrack?) -> Void) {
        let audioId = UUID().uuidString
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(audioId).m4a")
        
        // Use AVAssetExportSession to extract audio
        let asset = AVAsset(url: videoURL)
        
        // Check if the asset has an audio track
        guard asset.tracks(withMediaType: .audio).count > 0 else {
            print("No audio track in video")
            completion(nil)
            return
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            print("Failed to create export session")
            completion(nil)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Extract just the audio
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                // Get duration
                let audioDuration = asset.duration.seconds
                
                // Save to CloudKit
                self.saveAudioTrack(
                    title: title,
                    creator: creator,
                    duration: audioDuration,
                    audioURL: outputURL,
                    isOriginalAudio: true,
                    sourceVideoId: nil
                ) { audioTrack in
                    completion(audioTrack)
                }
                
            case .failed, .cancelled:
                print("Export failed: \(String(describing: exportSession.error))")
                completion(nil)
            default:
                completion(nil)
            }
        }
    }
    
    // Save audio track to CloudKit
    func saveAudioTrack(
        title: String,
        creator: String,
        duration: TimeInterval,
        audioURL: URL,
        isOriginalAudio: Bool,
        sourceVideoId: String?,
        completion: @escaping (AudioTrack?) -> Void
    ) {
        let database = CKContainer.default().publicCloudDatabase
        let record = CKRecord(recordType: "AudioTrack")
        
        // Generate a unique ID
        let audioId = UUID().uuidString
        
        record["title"] = title
        record["creator"] = creator
        record["duration"] = duration
        record["usageCount"] = 1
        record["audioId"] = audioId
        record["isOriginalAudio"] = isOriginalAudio
        
        if let sourceVideoId = sourceVideoId {
            record["sourceVideoId"] = sourceVideoId
        }
        
        // Create asset from audio file
        let asset = CKAsset(fileURL: audioURL)
        record["audioFile"] = asset
        
        database.save(record) { savedRecord, error in
            if let error = error {
                print("Error saving audio track: \(error)")
                completion(nil)
                return
            }
            
            guard let savedRecord = savedRecord else {
                completion(nil)
                return
            }
            
            let audioTrack = AudioTrack(
                id: UUID(),
                title: title,
                creator: creator,
                duration: duration,
                usageCount: 1,
                audioId: audioId,
                fileURL: audioURL,
                isOriginalAudio: isOriginalAudio,
                sourceVideoId: sourceVideoId,
                recordId: savedRecord.recordID
            )
            
            completion(audioTrack)
        }
    }
    
    // Increment usage count for an audio track
    func incrementUsageCount(for audioTrack: AudioTrack, completion: @escaping (Bool) -> Void) {
        guard let recordId = audioTrack.recordId else {
            completion(false)
            return
        }
        
        let database = CKContainer.default().publicCloudDatabase
        
        database.fetch(withRecordID: recordId) { record, error in
            if let error = error {
                print("Error fetching audio track record: \(error)")
                completion(false)
                return
            }
            
            guard let record = record else {
                completion(false)
                return
            }
            
            let currentCount = record["usageCount"] as? Int ?? 0
            record["usageCount"] = currentCount + 1
            
            database.save(record) { _, error in
                if let error = error {
                    print("Error updating usage count: \(error)")
                    completion(false)
                    return
                }
                
                completion(true)
            }
        }
    }
}
