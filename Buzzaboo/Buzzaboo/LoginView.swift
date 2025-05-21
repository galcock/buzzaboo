// LoginView.swift

import os.log
private let logQueue = DispatchQueue(label: "com.buzzaboo.logging", attributes: [])

import SwiftUI
import AuthenticationServices
import CloudKit
import CoreLocation
import UIKit

// Add right after your imports
var appLogs: [String] = []
func logMessage(_ message: String) {
    // First log to console, which is safe
    print(message)
    
    // Then safely append to appLogs array
    logQueue.async {
        // Defensive programming - check if array exists
        if appLogs == nil {
            appLogs = []
        }
        
        // Add the log with safety checks
        if appLogs.count < 1000 {
            appLogs.append("[\(Date())] \(message)")
        } else if appLogs.count >= 1000 {
            // Remove oldest logs if we have too many
            appLogs.removeFirst(200)
            appLogs.append("[\(Date())] \(message)")
        }
    }
    
    // Also log to system log which is more reliable
    os_log("%{public}@", log: OSLog.default, type: .debug, message)
}

struct LoginView: View {
    @State private var userIdentifier: String?
    @State private var firstName: String?
    @AppStorage("userIdentifier") private var storedUserIdentifier: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showLogSharing = false
    @State private var debugTapCount = 0
    
    // Name prompt state variables
    @State private var showNamePrompt = false
    @State private var nameInput = ""
    @State private var readyToProceed = false
    
    var body: some View {
        ZStack {
            // Main app flow
            VStack {
                if userIdentifier == nil && storedUserIdentifier.isEmpty {
                    Text("Welcome to Buzzaboo")
                        .font(.title)
                        .padding()
                    
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    let userId = appleIDCredential.user
                                    print("Apple ID credential received: \(userId)")
                                    
                                    // Store the user ID
                                    userIdentifier = userId
                                    storedUserIdentifier = userId
                                    
                                    // Get name with fallback
                                    if let givenName = appleIDCredential.fullName?.givenName, !givenName.isEmpty {
                                        // Validate name even if it comes from Apple
                                        let validationResult = validateAndFormatName(givenName)
                                        if validationResult.isValid {
                                            firstName = validationResult.formattedName
                                            print("Got validated name from Apple: \(validationResult.formattedName)")
                                            readyToProceed = true
                                            
                                            // Create profile with validated name from Apple
                                            createProfile(identifier: userId, name: validationResult.formattedName)
                                        } else {
                                            print("Apple provided name failed validation: \(givenName)")
                                            // Ask for name input instead
                                            showNamePrompt = true
                                        }
                                    } else {
                                        print("No name components provided by Apple, using default")
                                        print("FullName details: \(String(describing: appleIDCredential.fullName))")
                                        
                                        // Check if we already have a profile with this ID
                                        checkForExistingProfile(identifier: userId) { existingName in
                                            if let name = existingName, name != "User" {
                                                // Use existing custom name
                                                firstName = name
                                                readyToProceed = true
                                            } else {
                                                // Ask for name input - wait for user to enter name
                                                showNamePrompt = true
                                                // Don't proceed until name is provided
                                            }
                                        }
                                    }
                                }
                            case .failure(let error):
                                print("Sign In failed: \(error.localizedDescription)")
                                alertMessage = "Sign in failed: \(error.localizedDescription)"
                                showingAlert = true
                            }
                        }
                    )
                    .frame(width: 280, height: 45)
                    .padding()
                } else if readyToProceed || !showNamePrompt {
                    // Only show MainAppView when ready or if we don't need to prompt for name
                    MainAppView(
                        userIdentifier: userIdentifier ?? storedUserIdentifier,
                        firstName: firstName ?? "User"
                    )
                } else {
                    // Show a placeholder while waiting for name
                    Color.appBackground.edgesIgnoringSafeArea(.all)
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Sign In Issue"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            
            .alert("Debug Menu", isPresented: $showLogSharing) {
                Button("Share Logs") {
                    shareAppLogs()
                }
                Button("Check iCloud") {
                    CKContainer.default().accountStatus { status, error in
                        logMessage("iCloud status: \(status.rawValue), error: \(error?.localizedDescription ?? "none")")
                        showLogSharing = true // Show alert again to see the log
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            
            // Name input prompt - styled to match app
            if showNamePrompt {
                // Semi-transparent background
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 25) {
                    Text("What's your first name?")
                        .font(.appHeadline)
                        .fontWeight(.bold)
                        .foregroundColor(.appForeground)
                    
                    TextField("Enter your first name", text: $nameInput)
                        .font(.appBody)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    
                    Button(action: {
                        if nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Use "User" if they don't enter anything
                            firstName = "User"
                            createProfile(identifier: userIdentifier ?? storedUserIdentifier, name: "User")
                            showNamePrompt = false
                            readyToProceed = true
                        } else {
                            // Validate and format the input name
                            let validationResult = validateAndFormatName(nameInput)
                            
                            if validationResult.isValid {
                                // Use the validated name
                                firstName = validationResult.formattedName
                                createProfile(identifier: userIdentifier ?? storedUserIdentifier, name: validationResult.formattedName)
                                showNamePrompt = false
                                readyToProceed = true
                            } else {
                                // Show error for invalid name
                                alertMessage = validationResult.error ?? "Invalid name"
                                showingAlert = true
                            }
                        }
                    }) {
                        Text("Continue")
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 200)
                            .background(Color.appAccent)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                    }
                }
                .padding(30)
                .background(Color.gray.opacity(0.9))
                .cornerRadius(20)
                .shadow(radius: 15)
                .padding(30)
            }
            // Add this at the end of your main ZStack in the body
            // Invisible touch area in bottom right corner
            Color.clear
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                .onTapGesture {
                    debugTapCount += 1
                    if debugTapCount >= 5 {
                        showLogSharing = true
                        debugTapCount = 0
                    }
                }
                .position(x: UIScreen.main.bounds.width - 25, y: UIScreen.main.bounds.height - 25)
        }
        .onAppear {
            if !storedUserIdentifier.isEmpty {
                userIdentifier = storedUserIdentifier
                
                // Try to fetch the name from CloudKit for returning users
                fetchUserName(identifier: storedUserIdentifier) { fetchedName in
                    if let name = fetchedName {
                        firstName = name
                        readyToProceed = true
                    } else {
                        // Show name prompt if we don't have a name
                        showNamePrompt = true
                    }
                }
            }
        }
    }
    
    // Name validation function
    func validateAndFormatName(_ input: String) -> (isValid: Bool, formattedName: String, error: String?) {
        // Trim whitespace
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if empty
        if trimmed.isEmpty {
            return (false, "", "Please enter your name")
        }
        
        // Check length
        if trimmed.count < 2 {
            return (false, "", "Name is too short")
        }
        
        if trimmed.count > 30 {
            return (false, "", "Name is too long (maximum 30 characters)")
        }
        
        // Check for valid characters - allow letters, spaces, hyphens, apostrophes
        // This includes international characters
        let nameRegex = "^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ \\-']*$"
        let nameTest = NSPredicate(format: "SELF MATCHES %@", nameRegex)
        if !nameTest.evaluate(with: trimmed) {
            return (false, "", "Name can only contain letters, spaces, hyphens and apostrophes")
        }
        
        // Check for profanity and inappropriate terms
        let lowercaseName = trimmed.lowercased()
        
        // Comprehensive inappropriate word list for production use
        let inappropriateTerms = [
            // Common profanity
            "ass", "asshole", "bastard", "bitch", "bullshit", "cunt", "damn", "dick", "dickhead",
            "fuck", "fucker", "fucking", "piss", "pussy", "shit", "tits", "twat",
            
            // Sexual terms
            "anal", "blowjob", "boner", "boob", "cock", "cum", "dildo", "erotic", "fap",
            "handjob", "horny", "incest", "jizz", "kink", "milf", "nipple", "nude", "oral",
            "orgasm", "penis", "porn", "prostitute", "rimjob", "sex", "slut", "vagina", "whore", "xxx",
            
            // Hate speech/slurs
            "beaner", "chink", "fag", "faggot", "dyke", "gook", "jew", "kike", "nazi", "negro",
            "nigger", "nigga", "paki", "queer", "raghead", "retard", "spic", "wetback", "tranny",
            
            // Drug references
            "cocaine", "heroin", "junkie", "meth", "weed",
            
            // Other inappropriate terms
            "admin", "administrator", "buzzaboo", "cancer", "covid", "hitler", "holocaust", "jihad",
            "kill", "murder", "rape", "suicide", "terrorist", "torture", "trump", "virus"
        ]
        
        // Test for exact matches or substrings that could form inappropriate words
        for term in inappropriateTerms {
            if lowercaseName == term || lowercaseName.contains(term) {
                return (false, "", "Please enter an appropriate name")
            }
        }
        
        // Format the name properly - capitalize first letter of each word
        var formattedName = ""
        let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
        for (index, component) in components.enumerated() {
            if !component.isEmpty {
                formattedName += component.prefix(1).uppercased() + component.dropFirst().lowercased()
                if index < components.count - 1 {
                    formattedName += " "
                }
            }
        }
        
        return (true, formattedName, nil)
    }
    
    func checkForExistingProfile(identifier: String, completion: @escaping (String?) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first, let name = record["firstName"] as? String {
                print("Found existing profile with name: \(name)")
                DispatchQueue.main.async {
                    completion(name)
                }
            } else {
                print("No existing profile found")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    func fetchUserName(identifier: String, completion: @escaping (String?) -> Void) {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching user name: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                if let record = records?.first, let name = record["firstName"] as? String {
                    print("Found existing profile for \(identifier) with name: \(name)")
                    completion(name)
                } else {
                    print("No profile found for \(identifier)")
                    completion(nil)
                }
            }
        }
    }
    
    func createProfile(identifier: String, name: String) {
        print("Creating UserProfile for: \(identifier)")
        
        // Check iCloud status first with better error handling
        CKContainer.default().accountStatus { status, error in
            if status != .available {
                print("⚠️ iCloud not available: \(status.rawValue), error: \(error?.localizedDescription ?? "none")")
                DispatchQueue.main.async {
                    self.alertMessage = "iCloud account not available. Please sign in to iCloud in Settings."
                    self.showingAlert = true
                }
                return
            }
            
            // Get the database
            let database = CKContainer.default().publicCloudDatabase
            
            // First check if record already exists with safer error handling
            let predicate = NSPredicate(format: "identifier == %@", identifier)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            
            database.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    print("Error checking for existing profile: \(error.localizedDescription)")
                    // Show a user-friendly error message
                    DispatchQueue.main.async {
                        self.alertMessage = "Could not connect to iCloud. Please check your connection and try again."
                        self.showingAlert = true
                    }
                    return
                }
                
                if let existingRecords = records, !existingRecords.isEmpty {
                    print("UserProfile already exists for \(identifier), updating name to: \(name)")
                    
                    // Update existing record with new name
                    let record = existingRecords[0]
                    record["firstName"] = name
                    
                    database.save(record) { savedRecord, error in
                        if let error = error {
                            print("Error updating name: \(error.localizedDescription)")
                        } else {
                            print("✅ Successfully updated name to: \(name)")
                        }
                    }
                    
                    return
                }
                
                // Create a new record with error handling
                let record = CKRecord(recordType: "UserProfile")
                
                // Set fields explicitly
                record["identifier"] = identifier
                record["firstName"] = name
                record["likeCount"] = 0
                record["reportCount"] = 0
                
                // Add other essential fields with defaults
                record["lastActiveTime"] = Date()
                record["likedUsers"] = [String]()
                record["matches"] = [String]()
                
                // Use location if available
                let locationManager = CLLocationManager()
                if let location = locationManager.location {
                    record["location"] = location
                } else {
                    record["location"] = CLLocation(latitude: 34.0522, longitude: -118.2437)
                }
                
                print("Saving UserProfile to CloudKit with identifier: \(identifier), name: \(name)")
                database.save(record) { savedRecord, error in
                    if let error = error {
                        print("Error saving UserProfile: \(error.localizedDescription)")
                        
                        // Add more specific error handling based on CKError codes
                        if let ckError = error as? CKError {
                            switch ckError.code {
                            case .networkFailure, .networkUnavailable:
                                DispatchQueue.main.async {
                                    self.alertMessage = "Network connection unavailable. Please check your connection."
                                    self.showingAlert = true
                                }
                            case .serverResponseLost, .serviceUnavailable:
                                DispatchQueue.main.async {
                                    self.alertMessage = "iCloud service is currently unavailable. Please try again later."
                                    self.showingAlert = true
                                }
                            default:
                                DispatchQueue.main.async {
                                    self.alertMessage = "Could not create profile. Please try again."
                                    self.showingAlert = true
                                }
                            }
                        }
                    } else {
                        print("✅ Successfully created UserProfile for \(name) with ID \(identifier)")
                    }
                }
            }
        }
    }
    // Add this function inside the struct
    func shareAppLogs() {
        let logs = appLogs.joined(separator: "\n")
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("BuzzabooLogs.txt")
        
        do {
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let controller = windowScene.windows.first?.rootViewController {
                controller.present(activityVC, animated: true)
            }
        } catch {
            print("Error creating log file: \(error)")
        }
    }
}
