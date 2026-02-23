/* ============================================
   BUZZABOO - Firebase Configuration
   Replace with your actual Firebase project credentials
   ============================================ */

const firebaseConfig = {
  apiKey: "AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  authDomain: "buzzaboo-xxxxx.firebaseapp.com",
  projectId: "buzzaboo-xxxxx",
  storageBucket: "buzzaboo-xxxxx.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef1234567890",
  measurementId: "G-XXXXXXXXXX"
};

// VAPID public key for Web Push (generate at Firebase Console > Project Settings > Cloud Messaging)
const vapidPublicKey = "BAbCdEfGhIjKlMnOpQrStUvWxYz0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// Initialize Firebase
if (!firebase.apps.length) {
  firebase.initializeApp(firebaseConfig);
}

// Initialize services
window.firebaseConfig = firebaseConfig;
window.vapidPublicKey = vapidPublicKey;

console.log('✓ Firebase configured');
