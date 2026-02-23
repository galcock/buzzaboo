# Buzzaboo Social Features & Database Integration

This document describes the new social features and database integration added to Buzzaboo.

## ✨ Features Added

### 1. Follow System
- ✅ Follow/unfollow streamers
- ✅ Follower counts on profiles
- ✅ Following list page (`/activity.html?tab=following`)
- ✅ "Go Live" notifications for followed streamers

### 2. Notifications
- ✅ In-app notification bell with dropdown
- ✅ Push notifications (Web Push API)
- ✅ Notification preferences in settings
- ✅ Types: stream live, new follower, subscription, chat mention, whisper
- ✅ Unread badge counter
- ✅ Sound effects (optional)

### 3. Database (Firestore)
- ✅ `js/database-service.js` - Complete Firestore wrapper
- ✅ Collections:
  - **users** - User profiles and stats
  - **streams** - Live stream data
  - **follows** - Follow relationships
  - **notifications** - All notifications
  - **clips** - User-created clips
  - **vods** - VOD archive
  - **whispers** - Private messages
  - **push_subscriptions** - Web Push subscriptions
- ✅ Real-time listeners for live data updates

### 4. Social Features
- ✅ Share stream (copy link, Twitter, Facebook, Reddit, Discord, Email)
- ✅ Clips saved to user profile
- ✅ VOD archive per streamer
- ✅ Chat mentions (@username) - ready for integration
- ✅ Whispers (private messages)

### 5. Activity Feed
- ✅ `/activity.html` - Recent activity from followed channels
- ✅ Tabs: All Activity, Clips, Streams, Following
- ✅ Shows clips, streams, and other activity from followed users

### 6. Discovery
- ✅ Recommended streams algorithm (basic)
- ✅ "Channels you might like" based on follower count
- ✅ Trending clips (most viewed in last 7 days)

### 7. Settings Page
- ✅ `/settings.html` - Comprehensive settings
- ✅ Profile editing (display name, username, bio, avatar)
- ✅ Notification preferences (granular controls)
- ✅ Privacy settings
- ✅ Test notification button

## 📁 New Files

### JavaScript Services
- `js/database-service.js` - Firestore wrapper with all CRUD operations
- `js/notifications-service.js` - Notification handling (in-app + push)
- `js/social-features.js` - Follow buttons, share menus, whispers, clips
- `js/firebase-config.js` - Firebase configuration (needs your credentials)
- `js/init.js` - Global initialization script

### HTML Pages
- `activity.html` - Activity feed page
- `settings.html` - Settings page with notification preferences

### CSS
- `css/social.css` - All social feature styles

### Updated Files
- `sw.js` - Enhanced service worker with push notification handling

## 🔧 Setup Instructions

### 1. Firebase Project Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project (or use existing)
3. Enable **Firestore Database**:
   - Go to Firestore Database > Create Database
   - Start in production mode
   - Choose a location
4. Enable **Authentication**:
   - Go to Authentication > Sign-in method
   - Enable Email/Password (or your preferred methods)
5. Get your Firebase config:
   - Project Settings > General > Your apps
   - Copy the configuration object

### 2. Configure Firebase

Edit `js/firebase-config.js` and replace with your actual config:

```javascript
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID"
};
```

### 3. Enable Web Push Notifications

1. In Firebase Console: Project Settings > Cloud Messaging
2. Under "Web Push certificates", click "Generate key pair"
3. Copy the VAPID public key
4. Update `js/firebase-config.js`:
```javascript
const vapidPublicKey = "YOUR_VAPID_PUBLIC_KEY";
```

### 4. Firestore Security Rules

Go to Firestore Database > Rules and set up security rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Follows collection
    match /follows/{followId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow delete: if request.auth != null && 
        request.auth.uid == resource.data.followerId;
    }
    
    // Streams collection
    match /streams/{streamId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Notifications collection
    match /notifications/{notificationId} {
      allow read: if request.auth != null && 
        request.auth.uid == resource.data.userId;
      allow write: if request.auth != null;
    }
    
    // Clips collection
    match /clips/{clipId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // VODs collection
    match /vods/{vodId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Whispers collection
    match /whispers/{whisperId} {
      allow read, write: if request.auth != null && 
        (request.auth.uid == resource.data.from || 
         request.auth.uid == resource.data.to);
    }
    
    // Push subscriptions
    match /push_subscriptions/{userId} {
      allow read, write: if request.auth != null && 
        request.auth.uid == userId;
    }
  }
}
```

### 5. Update HTML Files

Add these scripts to ALL HTML pages (before closing `</body>`):

```html
<!-- Firebase -->
<script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore-compat.js"></script>

<!-- Social Features CSS -->
<link rel="stylesheet" href="css/social.css">

<!-- Buzzaboo Social Scripts -->
<script src="js/firebase-config.js"></script>
<script src="js/database-service.js"></script>
<script src="js/notifications-service.js"></script>
<script src="js/social-features.js"></script>
<script src="js/init.js"></script>
```

Add notification bell container in header:
```html
<div class="header-actions">
  <!-- ... other header items ... -->
  <div id="notification-bell-container"></div>
  <!-- ... rest of header ... -->
</div>
```

## 🎨 UI Components Usage

### Follow Button
```javascript
const followBtn = new FollowButton(targetUserId, {
  size: 'md',  // sm, md, lg
  showCount: true
});
await followBtn.render(container);
```

### Share Menu
```javascript
const shareMenu = new ShareMenu({
  url: window.location.href,
  title: 'Check out this stream!',
  text: 'Watching live on Buzzaboo'
});
shareMenu.render(container);
```

### Clip Creator
```javascript
const clipCreator = new ClipCreator(streamId, {
  duration: 30  // seconds
});
await clipCreator.createClip();
```

### Notification Bell
```javascript
const bell = new NotificationBell('notification-bell-container');
await bell.refresh();
```

### Whisper Box
```javascript
const whisper = new WhisperBox(recipientId, recipientName);
whisper.render(document.body);
```

## 📊 Database Methods

### Users
```javascript
// Create user
await databaseService.createUser(uid, { username, displayName, email });

// Get user
const user = await databaseService.getUser(uid);

// Update user
await databaseService.updateUser(uid, { bio: 'New bio' });
```

### Follows
```javascript
// Follow user
await databaseService.followUser(followerId, followingId);

// Unfollow user
await databaseService.unfollowUser(followerId, followingId);

// Check if following
const isFollowing = await databaseService.isFollowing(followerId, followingId);

// Get followers/following
const followers = await databaseService.getFollowers(userId);
const following = await databaseService.getFollowing(userId);
```

### Notifications
```javascript
// Create notification
await databaseService.createNotification(userId, {
  type: 'stream_live',
  message: 'Your favorite streamer is live!',
  link: '/stream.html?room=xyz'
});

// Get notifications
const notifications = await databaseService.getNotifications(userId);

// Mark as read
await databaseService.markNotificationRead(notificationId);
await databaseService.markAllNotificationsRead(userId);

// Listen to notifications (real-time)
const unsubscribe = databaseService.listenToNotifications(userId, (notifications) => {
  console.log('New notifications:', notifications);
});
```

### Streams
```javascript
// Create stream
const stream = await databaseService.createStream(userId, {
  title: 'My Stream',
  category: 'Gaming',
  tags: ['fps', 'competitive'],
  roomName: 'my-room',
  thumbnail: 'url-to-thumbnail'
});

// Update stream
await databaseService.updateStream(streamId, { viewers: 100 });

// End stream
await databaseService.endStream(streamId);

// Get live streams
const liveStreams = await databaseService.getLiveStreams(50);

// Listen to stream (real-time)
const unsubscribe = databaseService.listenToStream(streamId, (stream) => {
  console.log('Stream updated:', stream);
});
```

### Clips
```javascript
// Create clip
const clip = await databaseService.createClip(userId, {
  title: 'Epic Moment',
  thumbnail: 'url',
  videoUrl: 'url',
  duration: 30,
  tags: ['epic', 'highlight']
});

// Get user clips
const clips = await databaseService.getClips(userId);

// Get trending clips
const trending = await databaseService.getTrendingClips(50);

// Like/unlike clip
await databaseService.likeClip(clipId, userId);
await databaseService.unlikeClip(clipId, userId);
```

## 🎯 Integration Points

### Chat Mentions
In your chat component, detect `@username` mentions:
```javascript
async function handleChatMessage(message) {
  const mentions = message.match(/@(\w+)/g);
  if (mentions) {
    for (const mention of mentions) {
      const username = mention.substring(1);
      // Look up user and notify
      await databaseService.createNotification(userId, {
        type: 'chat_mention',
        message: `${senderName} mentioned you in chat`,
        link: '#chat'
      });
    }
  }
}
```

### Stream Live Notifications
When starting a stream:
```javascript
const stream = await databaseService.createStream(userId, streamData);
// This automatically notifies all followers via notifyFollowers()
```

## 🔐 Testing

1. Create a test user account
2. Test follow/unfollow functionality
3. Request notification permissions
4. Test sending test notification from settings
5. Create a test clip
6. Check activity feed updates
7. Test whispers between users

## 📱 Mobile Support

All components are responsive and work on mobile devices:
- Notification dropdown adapts to screen size
- Whisper boxes go full-width on mobile
- Toast notifications stack properly
- Touch-friendly interactive elements

## 🚀 Production Checklist

- [ ] Replace Firebase config with production credentials
- [ ] Set up proper Firestore security rules
- [ ] Generate VAPID keys for Web Push
- [ ] Configure Firebase Authentication methods
- [ ] Test push notifications on multiple browsers
- [ ] Set up proper error tracking
- [ ] Add rate limiting for API calls
- [ ] Implement proper user onboarding
- [ ] Add privacy policy and terms of service
- [ ] Test offline functionality

## 🐛 Troubleshooting

### Notifications not appearing
1. Check browser notification permissions
2. Verify VAPID key is correct
3. Check service worker registration
4. Verify Firebase config is correct

### Real-time updates not working
1. Check Firestore security rules
2. Verify user is authenticated
3. Check browser console for errors
4. Ensure listeners are properly set up

### Follow button not working
1. Verify user is logged in
2. Check Firestore permissions
3. Check browser console for errors
4. Verify target user exists in database

## 📖 Resources

- [Firebase Documentation](https://firebase.google.com/docs)
- [Web Push API](https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
- [Firestore Best Practices](https://firebase.google.com/docs/firestore/best-practices)
- [Service Workers](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)

## 🎉 What's Next?

Future enhancements to consider:
- Emotes and badges system
- Advanced recommendation algorithm using ML
- Video clip editing tools
- Channel points and rewards
- Subscriptions and tipping
- Advanced analytics dashboard
- Moderation tools
- Multi-language support
- Mobile apps (React Native)
