/**
 * Buzzaboo Authentication Service
 * Complete Firebase Auth integration with Firestore profiles
 */

class BuzzabooAuth {
  constructor() {
    this.user = null;
    this.profile = null;
    this.initialized = false;
    this.eventHandlers = new Map();
    this.unsubscribeAuth = null;
    this.unsubscribeProfile = null;
  }

  /**
   * Initialize Firebase and Auth
   */
  async init() {
    if (this.initialized) return;

    // Check if Firebase SDK is loaded
    if (typeof firebase === 'undefined') {
      console.error('Firebase SDK not loaded');
      return false;
    }

    // Initialize Firebase if not already done
    if (!firebase.apps.length) {
      firebase.initializeApp(window.FIREBASE_CONFIG);
    }

    this.auth = firebase.auth();
    this.db = firebase.firestore();
    this.storage = firebase.storage ? firebase.storage() : null;
    this.googleProvider = new firebase.auth.GoogleAuthProvider();
    this.appleProvider = new firebase.auth.OAuthProvider('apple.com');

    // Configure Google provider
    this.googleProvider.addScope('profile');
    this.googleProvider.addScope('email');

    // Configure Apple provider
    this.appleProvider.addScope('email');
    this.appleProvider.addScope('name');

    // Set up auth state persistence based on "remember me"
    const rememberMe = localStorage.getItem('buzzaboo-remember-me') === 'true';
    await this.auth.setPersistence(
      rememberMe 
        ? firebase.auth.Auth.Persistence.LOCAL 
        : firebase.auth.Auth.Persistence.SESSION
    );

    // Listen for auth state changes
    this.unsubscribeAuth = this.auth.onAuthStateChanged(async (user) => {
      this.user = user;
      
      if (user) {
        // User is signed in
        await this.loadUserProfile();
        this.emit('authStateChanged', { user: this.user, profile: this.profile });
        this.updateUI(true);
      } else {
        // User is signed out
        this.profile = null;
        if (this.unsubscribeProfile) {
          this.unsubscribeProfile();
          this.unsubscribeProfile = null;
        }
        this.emit('authStateChanged', { user: null, profile: null });
        this.updateUI(false);
      }
    });

    this.initialized = true;
    console.log('Buzzaboo Auth initialized');
    return true;
  }

  /**
   * Load user profile from Firestore
   */
  async loadUserProfile() {
    if (!this.user) return null;

    try {
      // Unsubscribe from previous profile listener
      if (this.unsubscribeProfile) {
        this.unsubscribeProfile();
      }

      // Real-time profile listener
      this.unsubscribeProfile = this.db
        .collection('users')
        .doc(this.user.uid)
        .onSnapshot((doc) => {
          if (doc.exists) {
            this.profile = { id: doc.id, ...doc.data() };
          } else {
            // Create initial profile if doesn't exist
            this.createInitialProfile();
          }
          this.emit('profileUpdated', this.profile);
        });

      // Initial load
      const doc = await this.db.collection('users').doc(this.user.uid).get();
      if (doc.exists) {
        this.profile = { id: doc.id, ...doc.data() };
      } else {
        await this.createInitialProfile();
      }

      return this.profile;
    } catch (error) {
      console.error('Error loading profile:', error);
      return null;
    }
  }

  /**
   * Create initial user profile in Firestore
   */
  async createInitialProfile() {
    if (!this.user) return null;

    const profile = {
      uid: this.user.uid,
      email: this.user.email,
      displayName: this.user.displayName || this.generateUsername(),
      username: this.generateUsername(),
      avatar: this.user.photoURL || this.generateAvatarUrl(),
      bio: '',
      followers: 0,
      following: 0,
      totalViews: 0,
      isVerified: false,
      isPartner: false,
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      preferences: {
        theme: 'dark',
        quality: '720p',
        notifications: {
          email: true,
          push: true,
          newFollower: true,
          goLive: true,
          mentions: true
        },
        privacy: {
          showOnline: true,
          allowDMs: true
        }
      },
      socials: {},
      badges: ['early-adopter']
    };

    try {
      await this.db.collection('users').doc(this.user.uid).set(profile);
      this.profile = { id: this.user.uid, ...profile };
      return this.profile;
    } catch (error) {
      console.error('Error creating profile:', error);
      return null;
    }
  }

  /**
   * Generate random username
   */
  generateUsername() {
    const adjectives = ['Swift', 'Cool', 'Epic', 'Pro', 'Star', 'Cosmic', 'Neon', 'Cyber', 'Ultra', 'Mega'];
    const nouns = ['Gamer', 'Streamer', 'Player', 'Creator', 'Bee', 'Buzz', 'Wave', 'Storm', 'Fire', 'Ice'];
    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    const num = Math.floor(Math.random() * 9999);
    return `${adj}${noun}${num}`;
  }

  /**
   * Generate avatar URL
   */
  generateAvatarUrl() {
    const id = Math.floor(Math.random() * 70) + 1;
    return `https://i.pravatar.cc/150?img=${id}`;
  }

  // ============================================
  // EMAIL/PASSWORD AUTHENTICATION
  // ============================================

  /**
   * Sign up with email and password
   */
  async signUpWithEmail(email, password, displayName = null) {
    try {
      this.emit('loading', { action: 'signup', loading: true });

      const result = await this.auth.createUserWithEmailAndPassword(email, password);

      // Update display name if provided
      if (displayName) {
        await result.user.updateProfile({ displayName });
      }

      // Send email verification
      await result.user.sendEmailVerification({
        url: window.location.origin + '/login.html?verified=true'
      });

      this.emit('loading', { action: 'signup', loading: false });
      this.emit('signupSuccess', { user: result.user });

      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'signup', loading: false });
      this.emit('error', { action: 'signup', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Sign in with email and password
   */
  async signInWithEmail(email, password, rememberMe = true) {
    try {
      this.emit('loading', { action: 'login', loading: true });

      // Set persistence based on remember me
      localStorage.setItem('buzzaboo-remember-me', rememberMe.toString());
      await this.auth.setPersistence(
        rememberMe 
          ? firebase.auth.Auth.Persistence.LOCAL 
          : firebase.auth.Auth.Persistence.SESSION
      );

      const result = await this.auth.signInWithEmailAndPassword(email, password);

      this.emit('loading', { action: 'login', loading: false });
      this.emit('loginSuccess', { user: result.user });

      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'login', loading: false });
      this.emit('error', { action: 'login', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Send password reset email
   */
  async sendPasswordReset(email) {
    try {
      this.emit('loading', { action: 'resetPassword', loading: true });

      await this.auth.sendPasswordResetEmail(email, {
        url: window.location.origin + '/login.html?reset=true'
      });

      this.emit('loading', { action: 'resetPassword', loading: false });
      return { success: true };
    } catch (error) {
      this.emit('loading', { action: 'resetPassword', loading: false });
      this.emit('error', { action: 'resetPassword', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Resend email verification
   */
  async resendVerificationEmail() {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      await this.user.sendEmailVerification({
        url: window.location.origin + '/login.html?verified=true'
      });
      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  // ============================================
  // SOCIAL AUTHENTICATION
  // ============================================

  /**
   * Sign in with Google
   */
  async signInWithGoogle() {
    try {
      this.emit('loading', { action: 'google', loading: true });

      const result = await this.auth.signInWithPopup(this.googleProvider);

      this.emit('loading', { action: 'google', loading: false });
      this.emit('loginSuccess', { user: result.user, provider: 'google' });

      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'google', loading: false });
      
      // Handle popup closed by user
      if (error.code === 'auth/popup-closed-by-user') {
        return { success: false, error: 'Sign in cancelled' };
      }

      this.emit('error', { action: 'google', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Sign in with Apple
   */
  async signInWithApple() {
    try {
      this.emit('loading', { action: 'apple', loading: true });

      const result = await this.auth.signInWithPopup(this.appleProvider);

      this.emit('loading', { action: 'apple', loading: false });
      this.emit('loginSuccess', { user: result.user, provider: 'apple' });

      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'apple', loading: false });
      
      // Handle popup closed by user
      if (error.code === 'auth/popup-closed-by-user') {
        return { success: false, error: 'Sign in cancelled' };
      }

      this.emit('error', { action: 'apple', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  // ============================================
  // USER MANAGEMENT
  // ============================================

  /**
   * Sign out
   */
  async signOut() {
    try {
      await this.auth.signOut();
      this.user = null;
      this.profile = null;
      localStorage.removeItem('buzzaboo-remember-me');
      this.emit('signedOut');
      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Update user profile
   */
  async updateProfile(data) {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      const updates = {
        ...data,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp()
      };

      // Update Firestore profile
      await this.db.collection('users').doc(this.user.uid).update(updates);

      // Update Firebase Auth profile if display name or photo changed
      const authUpdates = {};
      if (data.displayName) authUpdates.displayName = data.displayName;
      if (data.avatar) authUpdates.photoURL = data.avatar;
      
      if (Object.keys(authUpdates).length > 0) {
        await this.user.updateProfile(authUpdates);
      }

      // Update local profile
      this.profile = { ...this.profile, ...updates };
      this.emit('profileUpdated', this.profile);

      return { success: true, profile: this.profile };
    } catch (error) {
      console.error('Error updating profile:', error);
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Update user preferences
   */
  async updatePreferences(preferences) {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      await this.db.collection('users').doc(this.user.uid).update({
        preferences: firebase.firestore.FieldValue.arrayUnion(preferences),
        'preferences': { ...this.profile.preferences, ...preferences },
        updatedAt: firebase.firestore.FieldValue.serverTimestamp()
      });

      this.profile.preferences = { ...this.profile.preferences, ...preferences };
      this.emit('preferencesUpdated', this.profile.preferences);
      
      // Apply theme if changed
      if (preferences.theme) {
        document.documentElement.setAttribute('data-theme', preferences.theme);
        localStorage.setItem('buzzaboo-theme', preferences.theme);
      }

      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Change password
   */
  async changePassword(currentPassword, newPassword) {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      // Re-authenticate user
      const credential = firebase.auth.EmailAuthProvider.credential(
        this.user.email,
        currentPassword
      );
      await this.user.reauthenticateWithCredential(credential);

      // Update password
      await this.user.updatePassword(newPassword);

      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Change email
   */
  async changeEmail(password, newEmail) {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      // Re-authenticate user
      const credential = firebase.auth.EmailAuthProvider.credential(
        this.user.email,
        password
      );
      await this.user.reauthenticateWithCredential(credential);

      // Update email
      await this.user.updateEmail(newEmail);

      // Send verification to new email
      await this.user.sendEmailVerification();

      // Update Firestore
      await this.db.collection('users').doc(this.user.uid).update({
        email: newEmail,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp()
      });

      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Delete account
   */
  async deleteAccount(password = null) {
    if (!this.user) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      // Re-authenticate if password provided (email/password users)
      if (password) {
        const credential = firebase.auth.EmailAuthProvider.credential(
          this.user.email,
          password
        );
        await this.user.reauthenticateWithCredential(credential);
      }

      // Delete Firestore data
      await this.db.collection('users').doc(this.user.uid).delete();

      // Delete user account
      await this.user.delete();

      this.emit('accountDeleted');
      return { success: true };
    } catch (error) {
      // May need re-authentication for social providers
      if (error.code === 'auth/requires-recent-login') {
        return { 
          success: false, 
          error: 'Please sign out and sign in again to delete your account',
          requiresReauth: true
        };
      }
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  /**
   * Upload avatar image
   */
  async uploadAvatar(file) {
    if (!this.user || !this.storage) {
      return { success: false, error: 'Storage not available' };
    }

    try {
      const extension = file.name.split('.').pop();
      const path = `avatars/${this.user.uid}.${extension}`;
      const ref = this.storage.ref(path);

      // Upload file
      await ref.put(file);

      // Get download URL
      const url = await ref.getDownloadURL();

      // Update profile
      await this.updateProfile({ avatar: url });

      return { success: true, url };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  // ============================================
  // AUTHENTICATION HELPERS
  // ============================================

  /**
   * Check if user is authenticated
   */
  isAuthenticated() {
    return !!this.user;
  }

  /**
   * Check if user email is verified
   */
  isEmailVerified() {
    return this.user?.emailVerified || false;
  }

  /**
   * Get current user
   */
  getCurrentUser() {
    return this.user;
  }

  /**
   * Get current profile
   */
  getProfile() {
    return this.profile;
  }

  /**
   * Get Firebase UID for LiveKit integration
   */
  getUID() {
    return this.user?.uid || null;
  }

  /**
   * Get display name for chat/streams
   */
  getDisplayName() {
    return this.profile?.displayName || this.user?.displayName || 'Anonymous';
  }

  /**
   * Get avatar URL
   */
  getAvatarUrl() {
    return this.profile?.avatar || this.user?.photoURL || 'https://i.pravatar.cc/150?img=1';
  }

  // ============================================
  // PROTECTED ROUTES
  // ============================================

  /**
   * Check if current page requires auth
   */
  isProtectedPage() {
    const protectedPages = ['dashboard.html', 'settings.html'];
    const currentPage = window.location.pathname.split('/').pop();
    return protectedPages.includes(currentPage);
  }

  /**
   * Redirect to login if not authenticated
   */
  requireAuth(redirectTo = null) {
    if (!this.isAuthenticated()) {
      const returnUrl = redirectTo || window.location.pathname;
      window.location.href = `/login.html?redirect=${encodeURIComponent(returnUrl)}`;
      return false;
    }
    return true;
  }

  /**
   * Redirect authenticated users away from auth pages
   */
  redirectIfAuthenticated() {
    if (this.isAuthenticated()) {
      const params = new URLSearchParams(window.location.search);
      const redirect = params.get('redirect') || '/index.html';
      window.location.href = redirect;
      return true;
    }
    return false;
  }

  // ============================================
  // UI UPDATES
  // ============================================

  /**
   * Update UI based on auth state
   */
  updateUI(isLoggedIn) {
    // Update all user menus
    const userMenus = document.querySelectorAll('.user-menu, .auth-user-menu');
    const authButtons = document.querySelectorAll('.auth-buttons');
    const logoutBtns = document.querySelectorAll('.logout-btn, [data-auth="logout"]');
    const userAvatars = document.querySelectorAll('.user-avatar, .auth-avatar');
    const userNames = document.querySelectorAll('.user-name, .auth-display-name');

    if (isLoggedIn && this.profile) {
      // Show user menus, hide auth buttons
      userMenus.forEach(el => el.style.display = 'flex');
      authButtons.forEach(el => el.style.display = 'none');

      // Update avatars and names
      userAvatars.forEach(el => {
        if (el.tagName === 'IMG') {
          el.src = this.getAvatarUrl();
          el.alt = this.getDisplayName();
        }
      });

      userNames.forEach(el => {
        el.textContent = this.getDisplayName();
      });

      // Add logout handlers
      logoutBtns.forEach(btn => {
        btn.onclick = () => this.signOut();
      });

    } else {
      // Show auth buttons, hide user menus
      userMenus.forEach(el => el.style.display = 'none');
      authButtons.forEach(el => el.style.display = 'flex');
    }

    // Check protected pages
    if (this.isProtectedPage() && !isLoggedIn) {
      window.location.href = `/login.html?redirect=${encodeURIComponent(window.location.pathname)}`;
    }
  }

  // ============================================
  // ERROR HANDLING
  // ============================================

  /**
   * Get user-friendly error message
   */
  getErrorMessage(error) {
    const errorMessages = {
      'auth/email-already-in-use': 'This email is already registered. Try logging in instead.',
      'auth/invalid-email': 'Please enter a valid email address.',
      'auth/operation-not-allowed': 'This sign-in method is not enabled.',
      'auth/weak-password': 'Password must be at least 6 characters.',
      'auth/user-disabled': 'This account has been disabled.',
      'auth/user-not-found': 'No account found with this email.',
      'auth/wrong-password': 'Incorrect password. Please try again.',
      'auth/invalid-credential': 'Invalid credentials. Please check your email and password.',
      'auth/too-many-requests': 'Too many attempts. Please try again later.',
      'auth/network-request-failed': 'Network error. Please check your connection.',
      'auth/popup-blocked': 'Pop-up was blocked. Please allow pop-ups for this site.',
      'auth/popup-closed-by-user': 'Sign-in was cancelled.',
      'auth/account-exists-with-different-credential': 'An account with this email exists using a different sign-in method.',
      'auth/requires-recent-login': 'Please sign out and sign in again to complete this action.',
      'auth/credential-already-in-use': 'This credential is already linked to another account.',
    };

    return errorMessages[error.code] || error.message || 'An unexpected error occurred.';
  }

  // ============================================
  // EVENT SYSTEM
  // ============================================

  /**
   * Subscribe to an event
   */
  on(event, handler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event).add(handler);
    return () => this.off(event, handler);
  }

  /**
   * Unsubscribe from an event
   */
  off(event, handler) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.delete(handler);
    }
  }

  /**
   * Emit an event
   */
  emit(event, data) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => {
        try {
          handler(data);
        } catch (error) {
          console.error(`Error in event handler for ${event}:`, error);
        }
      });
    }
  }

  /**
   * Cleanup on page unload
   */
  destroy() {
    if (this.unsubscribeAuth) {
      this.unsubscribeAuth();
    }
    if (this.unsubscribeProfile) {
      this.unsubscribeProfile();
    }
    this.eventHandlers.clear();
  }
}

// Export singleton instance
const buzzabooAuth = new BuzzabooAuth();
window.buzzabooAuth = buzzabooAuth;
window.BuzzabooAuth = BuzzabooAuth;

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  // Check if Firebase is loaded
  if (typeof firebase !== 'undefined') {
    buzzabooAuth.init().then(() => {
      // Dispatch custom event for other scripts
      window.dispatchEvent(new CustomEvent('buzzaboo-auth-ready'));
    });
  } else {
    console.warn('Firebase SDK not loaded. Auth features disabled.');
  }
});
