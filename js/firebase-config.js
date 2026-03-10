/* ============================================
   BUZZABOO - Firebase Configuration
   Replace with your actual Firebase project credentials
   ============================================ */

const firebaseConfig = {
  apiKey: "AIzaSyD-Eor7mUGYaLZ-c8Nven4oNrfWQQDB_E8",
  authDomain: "buzzaboo-6161f.firebaseapp.com",
  projectId: "buzzaboo-6161f",
  storageBucket: "buzzaboo-6161f.firebasestorage.app",
  messagingSenderId: "1042177420898",
  appId: "1:1042177420898:web:a47e7ba6dd7603a9f7eb3b",
  measurementId: "G-T3KTFMP0HH"
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
