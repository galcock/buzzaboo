# Buzzaboo Firebase Authentication Setup Guide

This guide will walk you through setting up Firebase Authentication for Buzzaboo.

## Prerequisites

- A Google account
- Access to the [Firebase Console](https://console.firebase.google.com/)

---

## Step 1: Create a Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"** (or create one if you haven't)
3. Enter your project name (e.g., "Buzzaboo")
4. **Optional**: Enable Google Analytics (recommended for tracking)
5. Click **Create project**
6. Wait for the project to be created, then click **Continue**

---

## Step 2: Register Your Web App

1. In your Firebase project, click the **Web icon** (`</>`) to add a web app
2. Enter an app nickname (e.g., "Buzzaboo Web")
3. **Check** "Also set up Firebase Hosting" if you plan to use it
4. Click **Register app**
5. You'll see your Firebase configuration. **Copy these values!**

```javascript
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abc123",
  measurementId: "G-XXXXXXX"
};
```

6. Click **Continue to console**

---

## Step 3: Update Buzzaboo Configuration

1. Open `js/firebase-config.js` in your code editor
2. Replace the placeholder values with your Firebase config:

```javascript
const firebaseConfig = {
  apiKey: "YOUR_ACTUAL_API_KEY",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID",
  measurementId: "YOUR_MEASUREMENT_ID"
};
```

---

## Step 4: Enable Authentication Providers

### Email/Password Authentication

1. In Firebase Console, go to **Authentication** → **Sign-in method**
2. Click **Email/Password**
3. Toggle **Enable** on
4. Click **Save**

### Google Sign-In

1. In **Sign-in method**, click **Google**
2. Toggle **Enable** on
3. Enter your **Project support email**
4. Click **Save**

### Apple Sign-In

Apple Sign-In requires additional setup:

1. **Prerequisites**:
   - Apple Developer Account ($99/year)
   - App registered in Apple Developer Portal

2. **In Apple Developer Portal**:
   - Go to **Certificates, Identifiers & Profiles**
   - Create a **Services ID** for Sign in with Apple
   - Configure your domain and return URLs
   - Domain: `your-project.firebaseapp.com`
   - Return URL: `https://your-project.firebaseapp.com/__/auth/handler`

3. **In Firebase Console**:
   - Go to **Authentication** → **Sign-in method** → **Apple**
   - Toggle **Enable** on
   - Enter your **Services ID**
   - Download the **OAuth code flow** configuration
   - Create a **Key** in Apple Developer Portal
   - Upload the key to Firebase
   - Click **Save**

> **Note**: Apple Sign-In can be complex. See [Firebase Apple Auth Docs](https://firebase.google.com/docs/auth/web/apple) for detailed instructions.

---

## Step 5: Set Up Cloud Firestore

1. In Firebase Console, go to **Firestore Database**
2. Click **Create database**
3. Choose **Start in production mode** (we'll add rules)
4. Select your preferred location (closest to your users)
5. Click **Enable**

### Firestore Security Rules

Replace the default rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection - users can only read/write their own profile
    match /users/{userId} {
      allow read: if true; // Anyone can read public profiles
      allow create: if request.auth != null && request.auth.uid == userId;
      allow update, delete: if request.auth != null && request.auth.uid == userId;
    }
    
    // User followers - readable by anyone, writable by authenticated users
    match /followers/{docId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow delete: if request.auth != null && 
        (resource.data.followerId == request.auth.uid || 
         resource.data.followedId == request.auth.uid);
    }
    
    // Streams - readable by anyone, writable by stream owner
    match /streams/{streamId} {
      allow read: if true;
      allow write: if request.auth != null && 
        request.resource.data.userId == request.auth.uid;
    }
    
    // Chat messages - readable by anyone, writable by authenticated users
    match /chatMessages/{messageId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        resource.data.userId == request.auth.uid;
    }
    
    // User preferences - private
    match /userPreferences/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## Step 6: Set Up Firebase Storage (Optional)

For avatar uploads and media storage:

1. Go to **Storage** in Firebase Console
2. Click **Get started**
3. Start in production mode
4. Select your location
5. Click **Done**

### Storage Security Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Avatars - users can upload their own, anyone can read
    match /avatars/{userId}.{extension} {
      allow read: if true;
      allow write: if request.auth != null && 
        request.auth.uid == userId &&
        request.resource.size < 2 * 1024 * 1024 && // 2MB max
        request.resource.contentType.matches('image/.*');
    }
    
    // Stream thumbnails
    match /thumbnails/{streamId}.{extension} {
      allow read: if true;
      allow write: if request.auth != null &&
        request.resource.size < 5 * 1024 * 1024 && // 5MB max
        request.resource.contentType.matches('image/.*');
    }
  }
}
```

---

## Step 7: Configure Authorized Domains

1. Go to **Authentication** → **Settings** → **Authorized domains**
2. Add your custom domains:
   - `localhost` (for development)
   - `buzzaboo.tv` (your production domain)
   - Any staging/preview domains

---

## Step 8: Email Templates (Optional but Recommended)

Customize your authentication emails:

1. Go to **Authentication** → **Templates**
2. Customize each template:
   - **Email address verification**
   - **Password reset**

Example customization:
- Change the sender name to "Buzzaboo"
- Update the project name displayed
- Customize the action URL if needed

---

## Step 9: Testing

1. Open Buzzaboo in your browser
2. Click **Sign Up** or **Login**
3. Test each authentication method:
   - ✅ Email/Password signup
   - ✅ Email/Password login
   - ✅ Google Sign-In
   - ✅ Apple Sign-In (if configured)
   - ✅ Password reset
   - ✅ Email verification

4. Check Firestore to verify user profile creation

---

## Troubleshooting

### "Firebase App not initialized"
- Make sure `firebase-config.js` is loaded before `auth-service.js`
- Check that your config values are correct

### Google Sign-In not working
- Verify authorized domains in Firebase Console
- Check browser console for CORS errors

### Apple Sign-In issues
- Verify your Services ID matches
- Check that return URL is correct
- Ensure domain verification is complete

### Users not appearing in Firestore
- Check Firestore rules allow user creation
- Look for errors in browser console
- Verify Firestore is enabled

---

## Security Checklist

Before going to production:

- [ ] Replace all placeholder API keys
- [ ] Set proper Firestore rules
- [ ] Set proper Storage rules
- [ ] Add all production domains to authorized domains
- [ ] Enable App Check (recommended)
- [ ] Set up Firebase Security Rules Simulator to test
- [ ] Review Authentication settings
- [ ] Test all auth flows on production domain

---

## LiveKit Integration

Buzzaboo uses Firebase UID as the LiveKit identity for authenticated users. This ensures:

1. **Consistent Identity**: Same user ID across auth and streaming
2. **Profile Integration**: Display names and avatars sync automatically
3. **Moderation**: Easy to identify users for moderation

The integration happens automatically in `auth-service.js` and `livekit-service.js`.

---

## Support

- [Firebase Documentation](https://firebase.google.com/docs)
- [Firebase Auth Web](https://firebase.google.com/docs/auth/web/start)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Firebase Support](https://firebase.google.com/support)

---

## File Structure Reference

```
buzzaboo/
├── js/
│   ├── firebase-config.js    # Your Firebase configuration
│   ├── auth-service.js       # Authentication service
│   ├── auth-modal.js         # Auth modal component
│   ├── livekit-service.js    # LiveKit integration (uses Firebase UID)
│   └── app.js                # Main application
├── css/
│   ├── auth.css              # Auth pages styling
│   └── settings.css          # Settings page styling
├── login.html                # Login page
├── signup.html               # Signup page
├── forgot-password.html      # Password reset page
├── settings.html             # User settings page
└── SETUP.md                  # This file
```

---

Happy streaming! 🐝
