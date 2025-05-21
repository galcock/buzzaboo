// ChatView.swift
import SwiftUI
import CloudKit
import AVFoundation

// Rename to avoid conflict with existing ChatMessage
struct MessageItem: Identifiable, Equatable {
    let id: UUID
    var recordId: CKRecord.ID?
    let sender: String
    let message: String
    let timestamp: Date
    let isSystem: Bool
    var image: UIImage?
    var reaction: String?
    var replyTo: String?
    var cloudKitMessageId: String?  // Add this to store the messageID from CloudKit
    
    init(id: UUID = UUID(), recordId: CKRecord.ID? = nil, sender: String, message: String, timestamp: Date = Date(), isSystem: Bool = false, image: UIImage? = nil, reaction: String? = nil, replyTo: String? = nil, cloudKitMessageId: String? = nil) {
        self.id = id
        self.recordId = recordId
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
        self.isSystem = isSystem
        self.image = image
        self.reaction = reaction
        self.replyTo = replyTo
        self.cloudKitMessageId = cloudKitMessageId
    }
    
    static func == (lhs: MessageItem, rhs: MessageItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// Rename to avoid conflict with existing ChatBubbleView
struct MessageBubbleView: View {
    let message: MessageItem
    let isFromCurrentUser: Bool
    let onLongPress: () -> Void
    let onImageTap: ((UIImage) -> Void)? // Add callback for image tap
    
    private let maxImageSize: CGFloat = 240
    
    var body: some View {
        VStack {
            if message.isSystem {
                // System messages are centered
                Text(message.message)
                    .font(.caption)
                    .padding(8)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack {
                    if isFromCurrentUser { Spacer() }
                    
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                        if !isFromCurrentUser {
                            Text(message.sender)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                        }
                        
                        // Reply preview if this is a reply
                        if let replyText = message.replyTo {
                            Text("Replying to: \(replyText.prefix(20))...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.top, 2)
                        }
                        
                        // Message content - either text or image
                        if let image = message.image {
                            // Use resizable with aspectRatio to ensure image displays properly
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: maxImageSize, maxHeight: maxImageSize)
                                .cornerRadius(12)
                                // Add debug border to see image bounds
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                // Add tap gesture for fullscreen view
                                .onTapGesture {
                                    if let onImageTap = onImageTap {
                                        onImageTap(image)
                                    }
                                }
                        } else {
                            Text(message.message)
                                .padding(10)
                                .background(isFromCurrentUser ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // Timestamp
                        Text(formatTime(message.timestamp))
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                        
                        // Reaction display
                        if let reaction = message.reaction {
                            Text(reaction)
                                .font(.title3)
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                                .offset(y: -5)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle()) // Make entire area tappable
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onLongPress()
                    }
                    
                    if !isFromCurrentUser { Spacer() }
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            
            if Calendar.current.isDateInToday(date) {
                formatter.dateFormat = "h:mm a"
                return formatter.string(from: date)
            } else if Calendar.current.isDateInYesterday(date) {
                return "Yesterday " + formatter.string(from: date)
            } else {
                formatter.dateFormat = "MM/dd/yy h:mm a"
                return formatter.string(from: date)
            }
        }
    }

struct FullscreenImageView: View {
    let image: UIImage
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Solid black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Simple image view with fit aspect ratio
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black) // Add background color to image view as well
            
            // Back button (<) in top-left corner
            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(.top, 64) // Positioned 20px lower
                .padding(.leading, 16)
                
                Spacer()
            }
        }
    }
}

// Add ImageViewer for zoom and pan functionality
struct ImageViewer: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> UIScrollView {
        // Create scroll view for zooming
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.backgroundColor = .black
        
        // Create image view
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tag = 100 // Tag for finding in coordinator
        
        // Add double tap gesture for zooming
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(doubleTapGesture)
        
        scrollView.addSubview(imageView)
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Update the image view frame to fill the scroll view
        if let imageView = scrollView.viewWithTag(100) as? UIImageView {
            let size = scrollView.frame.size
            
            // Calculate the scale to fit the image to the scroll view
            let widthScale = size.width / image.size.width
            let heightScale = size.height / image.size.height
            let minScale = min(widthScale, heightScale)
            
            scrollView.minimumZoomScale = minScale
            if scrollView.zoomScale < minScale {
                scrollView.zoomScale = minScale
            }
            
            // Set the content size to image size
            scrollView.contentSize = image.size
            
            // Center the image
            imageView.frame = CGRect(origin: .zero, size: image.size)
            context.coordinator.centerImage(in: scrollView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ImageViewer
        
        init(_ parent: ImageViewer) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return scrollView.viewWithTag(100)
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Center the image when zooming
            centerImage(in: scrollView)
        }
        
        func centerImage(in scrollView: UIScrollView) {
            guard let imageView = scrollView.viewWithTag(100) else { return }
            
            let offsetX = max((scrollView.bounds.width - imageView.frame.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) * 0.5, 0)
            
            scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
        }
        
        @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let scrollView = gestureRecognizer.view?.superview as? UIScrollView else { return }
            
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                // Zoom out if currently zoomed in
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in to where the user tapped
                let point = gestureRecognizer.location(in: gestureRecognizer.view)
                let zoomRect = CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

// Custom image picker for chat
struct ChatImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false // Changed from true to false to disable forced cropping
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatImagePicker
        
        init(_ parent: ChatImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Use originalImage instead of editedImage since we're not editing anymore
            if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Share sheet for sharing messages and images
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ChatView: View {
    let userIdentifier: String
    let userName: String
    let matchId: String
    let matchName: String
    var onClose: () -> Void
    
    @State private var messages: [MessageItem] = []
    @State private var messageText = ""
    @State private var isLoading = true
    @State private var matchProfileImage: UIImage?
    @State private var isOnline = false
    @State private var messageListener: Timer?
    @State private var scrollToBottom = true
    @State private var longPressedMessage: MessageItem?
    @State private var showReactionMenu = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showCallRequestSent = false
    @State private var showingShare = false
    @State private var shareMessage: MessageItem?
    @State private var replyingTo: MessageItem?
    @State private var selectedFullscreenImage: UIImage?
    @State private var showingFullscreenImage = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Chat header
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    
                    // Match profile image
                    if let profileImage = matchProfileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(matchName.prefix(1))
                                    .foregroundColor(.white)
                                    .font(.appCaption)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchName)
                            .font(.appHeadline)
                            .foregroundColor(.white)
                        
                        if isOnline {
                            Text("Online")
                                .font(.appTiny)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        sendCallRequest()
                    }) {
                        Image(systemName: "video")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black)
                
                // Messages list
                ScrollViewReader { scrollView in
                    ScrollView {
                        if isLoading {
                            HStack {
                                Spacer()
                                PulsingLoaderView()
                                    .frame(width: 50, height: 50)
                                Spacer()
                            }
                            .padding(.top, 100)
                        } else if messages.isEmpty {
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 100)
                                
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text("No messages yet")
                                    .font(.appBody)
                                    .foregroundColor(.gray)
                                
                                Text("Say hi to \(matchName)!")
                                    .font(.appCaption)
                                    .foregroundColor(.gray.opacity(0.8))
                                
                                Spacer()
                            }
                            .padding(.top, 50)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(messages) { message in
                                    MessageBubbleView(
                                        message: message,
                                        isFromCurrentUser: message.sender == "You" || message.sender == userName,
                                        onLongPress: {
                                            longPressedMessage = message
                                            showReactionMenu = true
                                        },
                                        onImageTap: { image in
                                            selectedFullscreenImage = image
                                            showingFullscreenImage = true
                                        }
                                    )
                                    .id(message.id)
                                }
                                
                                // Invisible element at the bottom for scrolling
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottomMessage")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                    }
                    .onChange(of: messages) { _ in
                        if scrollToBottom {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollView.scrollTo("bottomMessage", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onAppear {
                        // Initial scroll to bottom
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                scrollView.scrollTo("bottomMessage", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Reply preview if user is replying
                if let replyMessage = replyingTo {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replying to \(replyMessage.sender)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text(replyMessage.message.prefix(30) + (replyMessage.message.count > 30 ? "..." : ""))
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            replyingTo = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                }
                
                // Message input
                HStack(spacing: 12) {
                    // Media attachment button
                    Button(action: {
                        showImagePicker = true
                    }) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    
                    TextField("Message...", text: $messageText)
                        .padding(12)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    
                    Button(action: {
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                            .gray : .blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color.black)
            }
            
            // Call request sent notification
            if showCallRequestSent {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 18))
                        
                        Text("Call request sent")
                            .font(.appCaption)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCallRequestSent = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadChatHistory()
            loadMatchProfile()
            setupMessageListener()
            markMessagesAsRead()
        }
        .onDisappear {
            messageListener?.invalidate()
            messageListener = nil
        }
        .sheet(isPresented: $showImagePicker) {
            ChatImagePicker(selectedImage: $selectedImage)
                .onDisappear {
                    if let image = selectedImage {
                        sendImageMessage(image)
                        selectedImage = nil
                    }
                }
        }
        .actionSheet(isPresented: $showReactionMenu) {
            if let message = longPressedMessage {
                return ActionSheet(
                    title: Text("Message Options"),
                    message: nil,
                    buttons: [
                        .default(Text("❤️")) { addReaction(message, reaction: "❤️") },
                        .default(Text("👍")) { addReaction(message, reaction: "👍") },
                        .default(Text("😂")) { addReaction(message, reaction: "😂") },
                        .default(Text("😮")) { addReaction(message, reaction: "😮") },
                        .default(Text("Reply")) { replyingTo = message },
                        .default(Text("Share")) {
                            shareMessage = message
                            showingShare = true
                        },
                        .destructive(Text("Delete")) { deleteMessage(message) },
                        .cancel()
                    ]
                )
            } else {
                return ActionSheet(title: Text("Error"), message: Text("No message selected"), buttons: [.cancel()])
            }
        }
        .sheet(isPresented: $showingShare) {
            if let message = shareMessage {
                if let image = message.image {
                    ShareSheet(items: [image])
                } else {
                    ShareSheet(items: [message.message])
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullscreenImage) {
                    if let image = selectedFullscreenImage {
                        FullscreenImageView(image: image, onDismiss: {
                            showingFullscreenImage = false
                        })
                    }
                }
    }
    
    private func loadChatHistory() {
        // Create a consistent room ID
        let roomId = [userIdentifier, matchId].sorted().joined(separator: "-")
        
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "roomID == %@", roomId)
        let query = CKQuery(recordType: "ChatMessage", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        database.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let records = records {
                    var loadedMessages: [MessageItem] = []
                    
                    for record in records {
                        if let sender = record["senderName"] as? String,
                           let message = record["message"] as? String,
                           let timestamp = record["timestamp"] as? Date {
                            
                            // Get CloudKit messageID
                            let cloudKitMessageId = record["messageID"] as? String
                            
                            // Determine if this message is from current user
                            let displaySender = (record["senderID"] as? String) == self.userIdentifier ? "You" : sender
                            
                            // Handle image messages
                            var messageImage: UIImage? = nil
                            if let imageAsset = record["messageImage"] as? CKAsset,
                               let imageUrl = imageAsset.fileURL,
                               FileManager.default.fileExists(atPath: imageUrl.path) {
                                do {
                                    let imageData = try Data(contentsOf: imageUrl)
                                    messageImage = UIImage(data: imageData)
                                    print("Loaded image for message: \(message), data size: \(imageData.count) bytes")
                                } catch {
                                    print("Error loading message image: \(error.localizedDescription)")
                                }
                            }
                            
                            // Handle reactions
                            var reaction: String? = nil
                            if let reactionText = record["reaction"] as? String, !reactionText.isEmpty {
                                reaction = reactionText
                            }
                            
                            // Handle reply info
                            var replyTo: String? = nil
                            if let replyToId = record["replyToId"] as? String,
                               let replyToText = record["replyToText"] as? String,
                               !replyToId.isEmpty {
                                replyTo = replyToText
                            }
                            
                            // Create message with Cloud record ID for easier updates
                            let chatMessage = MessageItem(
                                id: UUID(),
                                recordId: record.recordID,
                                sender: displaySender,
                                message: message,
                                timestamp: timestamp,
                                isSystem: false,
                                image: messageImage,
                                reaction: reaction,
                                replyTo: replyTo,
                                cloudKitMessageId: cloudKitMessageId
                            )
                            
                            loadedMessages.append(chatMessage)
                        }
                    }
                    
                    self.messages = loadedMessages.sorted { $0.timestamp < $1.timestamp }
                    self.scrollToBottom = true
                }
                
                if let error = error {
                    print("Error loading chat history: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupMessageListener() {
        // Set up a timer to periodically check for new messages
        messageListener = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.checkForNewMessages()
            self.checkMatchOnlineStatus()
        }
    }
    
    private func checkForNewMessages() {
        // Create a consistent room ID
        let roomId = [userIdentifier, matchId].sorted().joined(separator: "-")
        
        // Get the timestamp of the last message we have
        let lastTimestamp = messages.last?.timestamp ?? Date.distantPast
        
        // Create sets for more efficient lookups
        let localRecordIds = Set(messages.compactMap { $0.recordId?.recordName })
        let localUUIDs = Set(messages.map { $0.id.uuidString })
        let localCloudKitMessageIds = Set(messages.compactMap { $0.cloudKitMessageId })
        
        // Debug log
        print("📃 Looking for messages after: \(lastTimestamp)")
        print("📃 Current message count: \(messages.count)")
        
        // Query for newer messages
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "roomID == %@ AND timestamp > %@",
                                   roomId, lastTimestamp as NSDate)
        let query = CKQuery(recordType: "ChatMessage", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let operation = CKQueryOperation(query: query)
        var newMessages: [MessageItem] = []
        
        operation.recordMatchedBlock = { (recordID: CKRecord.ID, result: Result<CKRecord, Error>) in
            switch result {
            case .success(let record):
                // Get messageID if it exists
                let cloudKitMessageId = record["messageID"] as? String
                
                // Check for duplicates in multiple ways:
                
                // 1. By record ID
                if localRecordIds.contains(record.recordID.recordName) {
                    print("⚠️ Skipping duplicate by recordID: \(record.recordID.recordName)")
                    return
                }
                
                // 2. By CloudKit messageID
                if let messageId = cloudKitMessageId, localCloudKitMessageIds.contains(messageId) {
                    print("⚠️ Skipping duplicate by messageID: \(messageId)")
                    return
                }
                
                // 3. For messages from current user, do an additional check on timestamp
                // to catch local messages that might not have CloudKit IDs yet
                if (record["senderID"] as? String) == self.userIdentifier {
                    let recordTimestamp = record["timestamp"] as? Date ?? Date()
                    
                    // Look for messages within 5 seconds from the same sender
                    let possibleDuplicates = self.messages.filter {
                        $0.sender == "You" &&
                        abs($0.timestamp.timeIntervalSince(recordTimestamp)) < 5.0
                    }
                    
                    // If we find a message with same content and similar timestamp, skip it
                    if let message = record["message"] as? String, !possibleDuplicates.isEmpty {
                        if possibleDuplicates.contains(where: { $0.message == message }) {
                            print("⚠️ Skipping likely duplicate sent by current user")
                            return
                        }
                    }
                }
                
                // Proceed with message parsing
                if let sender = record["senderName"] as? String,
                   let message = record["message"] as? String,
                   let timestamp = record["timestamp"] as? Date {
                    
                    // Determine if this message is from current user
                    let displaySender = (record["senderID"] as? String) == self.userIdentifier ? "You" : sender
                    
                    // Handle image messages
                    var messageImage: UIImage? = nil
                    if let imageAsset = record["messageImage"] as? CKAsset,
                       let imageUrl = imageAsset.fileURL {
                        do {
                            // Make sure the file exists
                            if FileManager.default.fileExists(atPath: imageUrl.path) {
                                let imageData = try Data(contentsOf: imageUrl)
                                messageImage = UIImage(data: imageData)
                                print("✅ Successfully loaded image for message: \(imageData.count) bytes")
                            } else {
                                print("❌ Image file doesn't exist at path: \(imageUrl.path)")
                            }
                        } catch {
                            print("❌ Error loading image: \(error.localizedDescription)")
                        }
                    }
                    
                    // Handle reactions
                    var reaction: String? = nil
                    if let reactionText = record["reaction"] as? String, !reactionText.isEmpty {
                        reaction = reactionText
                    }
                    
                    // Handle reply info
                    var replyTo: String? = nil
                    if let replyToId = record["replyToId"] as? String,
                       let replyToText = record["replyToText"] as? String,
                       !replyToId.isEmpty {
                        replyTo = replyToText
                    }
                    
                    // Create message with Cloud record ID for easier updates
                    let chatMessage = MessageItem(
                        id: UUID(),
                        recordId: record.recordID,
                        sender: displaySender,
                        message: message,
                        timestamp: timestamp,
                        isSystem: false,
                        image: messageImage,
                        reaction: reaction,
                        replyTo: replyTo,
                        cloudKitMessageId: cloudKitMessageId
                    )
                    
                    print("📩 Adding new message from \(displaySender)")
                    newMessages.append(chatMessage)
                    
                    // Mark as read if it's from the other user
                    if (record["senderID"] as? String) == self.matchId && (record["isRead"] as? Bool) == false {
                        record["isRead"] = true
                        database.save(record) { _, _ in }
                    }
                }
            case .failure(let error):
                print("Error fetching new message: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { result in
            if !newMessages.isEmpty {
                DispatchQueue.main.async {
                    print("📬 Adding \(newMessages.count) new messages to UI")
                    self.messages.append(contentsOf: newMessages)
                    
                    // Play sound for new messages from others
                    if newMessages.contains(where: { $0.sender != "You" && $0.sender != self.userName }) {
                        self.playMessageSound()
                    }
                }
            }
        }
        
        database.add(operation)
    }
    
    private func checkMatchOnlineStatus() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", matchId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first,
               let lastActive = record["lastActiveTime"] as? Date {
                
                let twoMinutesAgo = Date().addingTimeInterval(-120)
                let isOnlineNow = lastActive > twoMinutesAgo
                
                DispatchQueue.main.async {
                    if self.isOnline != isOnlineNow {
                        self.isOnline = isOnlineNow
                    }
                }
            }
        }
    }
    
    private func markMessagesAsRead() {
        // Create a consistent room ID
        let roomId = [userIdentifier, matchId].sorted().joined(separator: "-")
        
        // Query for unread messages from the match
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "roomID == %@ AND senderID == %@ AND receiverID == %@ AND isRead == %@",
                                   roomId, matchId, userIdentifier, NSNumber(value: false))
        let query = CKQuery(recordType: "ChatMessage", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error querying unread messages: \(error.localizedDescription)")
                return
            }
            
            if let records = records, !records.isEmpty {
                print("Found \(records.count) unread messages to mark as read")
                
                // Use a batch operation instead of individual saves
                let recordsToSave = records.map { record -> CKRecord in
                    record["isRead"] = true
                    return record
                }
                
                let modifyOperation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
                modifyOperation.savePolicy = .changedKeys
                
                modifyOperation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        print("✅ Successfully marked \(records.count) messages as read")
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .permissionFailure {
                            print("❌ Permission error marking messages as read - likely trying to modify another user's records")
                            
                            // Fall back to marking one by one to identify which ones we can update
                            for record in records {
                                record["isRead"] = true
                                database.save(record) { _, saveError in
                                    if let saveError = saveError {
                                        print("❌ Error marking message as read: \(saveError.localizedDescription)")
                                    } else {
                                        print("✅ Successfully marked individual message as read")
                                    }
                                }
                            }
                        } else {
                            print("❌ Error marking messages as read: \(error.localizedDescription)")
                        }
                    }
                }
                
                database.add(modifyOperation)
            } else {
                print("No unread messages to mark as read")
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Create a consistent room ID
        let roomId = [userIdentifier, matchId].sorted().joined(separator: "-")
        
        // Prepare reply data if replying to a message
        var replyData: (String, String)? = nil
        if let reply = replyingTo {
            replyData = (reply.id.uuidString, reply.message)
        }
        
        // Add message locally immediately for better UX
        let newMessage = MessageItem(
            sender: "You",
            message: messageText.trimmingCharacters(in: .whitespacesAndNewlines),
            replyTo: replyData?.1
        )
        messages.append(newMessage)
        
        // Reset input field and reply state
        let sentMessage = messageText
        messageText = ""
        let replyInfo = replyingTo
        replyingTo = nil
        
        // Send to CloudKit
        let database = CKContainer.default().publicCloudDatabase
        let record = CKRecord(recordType: "ChatMessage")
        
        // Generate a unique message ID to help with deduplication
        let messageId = UUID().uuidString
        
        record["senderID"] = userIdentifier
        record["senderName"] = userName
        record["receiverID"] = matchId
        record["roomID"] = roomId
        record["message"] = sentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        record["timestamp"] = Date()
        record["messageID"] = messageId
        record["isRead"] = false
        
        // Add reply data if replying
        if let (replyId, replyText) = replyData {
            record["replyToId"] = replyId
            record["replyToText"] = replyText
        }
        
        database.save(record) { savedRecord, error in
            if let error = error {
                print("Error sending message: \(error.localizedDescription)")
            } else if let savedRecord = savedRecord {
                // Update the local message with the CloudKit record ID
                DispatchQueue.main.async {
                    if let index = self.messages.firstIndex(where: { $0.id == newMessage.id }) {
                        self.messages[index].recordId = savedRecord.recordID
                    }
                }
            }
        }
        
        // Play send sound
        playSendSound()
    }
    
    private func sendImageMessage(_ image: UIImage) {
        // Create a consistent room ID
        let roomId = [userIdentifier, matchId].sorted().joined(separator: "-")
        
        // Generate a UNIQUE MESSAGE ID that will be used both locally and in CloudKit
        let messageId = UUID().uuidString
        
        // Prepare reply data if replying to a message
        var replyData: (String, String)? = nil
        if let reply = replyingTo {
            replyData = (reply.id.uuidString, reply.message)
        }
        
        // Create a temporary file for the image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        
        do {
            try imageData.write(to: tempUrl)
            
            // Add message locally with the SAME ID that will be used in CloudKit
            let localMessageId = UUID(uuidString: messageId) ?? UUID()
            let newMessage = MessageItem(
                id: localMessageId,
                sender: "You",
                message: "Photo",
                timestamp: Date(),
                isSystem: false,
                image: image,
                replyTo: replyData?.1,
                cloudKitMessageId: messageId  // Store the CloudKit messageID locally too
            )
            
            // Add to messages array - this comes BEFORE the CloudKit save to prevent race conditions
            messages.append(newMessage)
            
            // Reset reply state
            replyingTo = nil
            
            // Create CloudKit record
            let database = CKContainer.default().publicCloudDatabase
            let record = CKRecord(recordType: "ChatMessage")
            
            record["senderID"] = userIdentifier
            record["senderName"] = userName
            record["receiverID"] = matchId
            record["roomID"] = roomId
            record["message"] = "Photo"
            record["timestamp"] = Date()
            record["messageID"] = messageId
            record["isRead"] = false
            record["messageImage"] = CKAsset(fileURL: tempUrl)
            
            // Add reply data if replying
            if let (replyId, replyText) = replyData {
                record["replyToId"] = replyId
                record["replyToText"] = replyText
            }
            
            // Log for debugging
            print("📤 Sending image with messageID: \(messageId)")
            
            database.save(record) { savedRecord, error in
                // Clean up temp file regardless of result
                try? FileManager.default.removeItem(at: tempUrl)
                
                if let error = error {
                    print("Error sending image message: \(error.localizedDescription)")
                } else if let savedRecord = savedRecord {
                    // Update the local message with the CloudKit record ID
                    DispatchQueue.main.async {
                        if let index = self.messages.firstIndex(where: { $0.id == localMessageId }) {
                            self.messages[index].recordId = savedRecord.recordID
                            print("✅ Updated local message with CloudKit record ID: \(savedRecord.recordID.recordName)")
                        }
                    }
                }
            }
            
            // Play send sound
            playSendSound()
        } catch {
            print("Error preparing image: \(error.localizedDescription)")
        }
    }
    
    private func addReaction(_ message: MessageItem, reaction: String) {
        // Find message in array
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            // Update locally
            messages[index].reaction = reaction
            
            // Update in CloudKit if we have a record ID
            if let recordId = message.recordId {
                let database = CKContainer.default().publicCloudDatabase
                
                database.fetch(withRecordID: recordId) { record, error in
                    if let record = record {
                        record["reaction"] = reaction
                        
                        database.save(record) { _, error in
                            if let error = error {
                                print("Error saving reaction: \(error.localizedDescription)")
                            }
                        }
                    } else if let error = error {
                        print("Error fetching message record: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func deleteMessage(_ message: MessageItem) {
        // Remove from local array
        messages.removeAll(where: { $0.id == message.id })
        
        // Delete from CloudKit if we have a record ID
        if let recordId = message.recordId {
            let database = CKContainer.default().publicCloudDatabase
            
            database.delete(withRecordID: recordId) { _, error in
                if let error = error {
                    print("Error deleting message: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadMatchProfile() {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", matchId)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let record = records?.first {
                DispatchQueue.main.async {
                    // Check if online (active in last 2 minutes)
                    if let lastActive = record["lastActiveTime"] as? Date {
                        let twoMinutesAgo = Date().addingTimeInterval(-120)
                        self.isOnline = lastActive > twoMinutesAgo
                    }
                    
                    if let imageAsset = record["profileImage"] as? CKAsset,
                       let imageUrl = imageAsset.fileURL {
                        
                        do {
                            let imageData = try Data(contentsOf: imageUrl)
                            self.matchProfileImage = UIImage(data: imageData)
                        } catch {
                            print("Error loading match profile image: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func sendCallRequest() {
        // Create a call request in CloudKit
        let database = CKContainer.default().publicCloudDatabase
        let record = CKRecord(recordType: "CallRequest")
        
        record["senderId"] = userIdentifier
        record["senderName"] = userName
        record["receiverId"] = matchId
        record["status"] = "pending"
        record["timestamp"] = Date()
        record["requestId"] = UUID().uuidString
        
        // Save the call request
        database.save(record) { savedRecord, error in
            if let error = error {
                print("Error sending call request: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    // Show confirmation toast
                    withAnimation {
                        self.showCallRequestSent = true
                    }
                }
            }
        }
    }
    
    private func playMessageSound() {
        // Play message received sound
        let systemSoundID: SystemSoundID = 1003 // Standard notification sound
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    private func playSendSound() {
        // Play message sent sound
        let systemSoundID: SystemSoundID = 1004 // Standard sent sound
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
