/**
 * Buzzaboo Authentication Service
 * Firebase Auth with anonymous fallback for video chat
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

  async init() {
    if (this.initialized) return;

    if (typeof firebase === 'undefined') {
      console.warn('Firebase SDK not loaded. Running in anonymous-only mode.');
      this.initialized = true;
      return true;
    }

    if (!firebase.apps.length) {
      firebase.initializeApp(window.firebaseConfig);
    }

    this.auth = firebase.auth();
    this.db = firebase.firestore();
    this.googleProvider = new firebase.auth.GoogleAuthProvider();
    this.appleProvider = new firebase.auth.OAuthProvider('apple.com');

    this.googleProvider.addScope('profile');
    this.googleProvider.addScope('email');
    this.appleProvider.addScope('email');
    this.appleProvider.addScope('name');

    const rememberMe = localStorage.getItem('buzzaboo-remember-me') === 'true';
    await this.auth.setPersistence(
      rememberMe
        ? firebase.auth.Auth.Persistence.LOCAL
        : firebase.auth.Auth.Persistence.SESSION
    );

    this.unsubscribeAuth = this.auth.onAuthStateChanged(async (user) => {
      this.user = user;
      if (user) {
        await this.loadUserProfile();
        this.emit('authStateChanged', { user: this.user, profile: this.profile });
        this.updateUI(true);
      } else {
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

  async loadUserProfile() {
    if (!this.user || !this.db) return null;

    try {
      if (this.unsubscribeProfile) {
        this.unsubscribeProfile();
      }

      this.unsubscribeProfile = this.db
        .collection('users')
        .doc(this.user.uid)
        .onSnapshot((doc) => {
          if (doc.exists) {
            this.profile = { id: doc.id, ...doc.data() };
          } else {
            this.createInitialProfile();
          }
          this.emit('profileUpdated', this.profile);
        });

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

  async createInitialProfile() {
    if (!this.user || !this.db) return null;

    const profile = {
      uid: this.user.uid,
      email: this.user.email,
      displayName: this.user.displayName || this.generateUsername(),
      username: this.generateUsername(),
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      preferences: {
        theme: 'dark',
        privateByDefault: false,
        interests: []
      }
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

  generateUsername() {
    const adjectives = ['Swift', 'Cool', 'Epic', 'Star', 'Cosmic', 'Neon', 'Cyber', 'Ultra', 'Bright', 'Wild'];
    const nouns = ['Bee', 'Buzz', 'Wave', 'Storm', 'Fire', 'Spark', 'Flash', 'Comet', 'Nova', 'Drift'];
    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    const num = Math.floor(Math.random() * 9999);
    return `${adj}${noun}${num}`;
  }

  // ============================================
  // ANONYMOUS ID (for users without accounts)
  // ============================================

  getAnonymousId() {
    let id = localStorage.getItem('buzzaboo-anon-id');
    if (!id) {
      id = 'anon-' + crypto.randomUUID();
      localStorage.setItem('buzzaboo-anon-id', id);
    }
    return id;
  }

  getUserId() {
    return this.user?.uid || this.getAnonymousId();
  }

  // ============================================
  // EMAIL/PASSWORD AUTHENTICATION
  // ============================================

  async signUpWithEmail(email, password, displayName = null) {
    try {
      this.emit('loading', { action: 'signup', loading: true });
      const result = await this.auth.createUserWithEmailAndPassword(email, password);

      if (displayName) {
        await result.user.updateProfile({ displayName });
      }

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

  async signInWithEmail(email, password, rememberMe = true) {
    try {
      this.emit('loading', { action: 'login', loading: true });

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

  // ============================================
  // SOCIAL AUTHENTICATION
  // ============================================

  async signInWithGoogle() {
    try {
      this.emit('loading', { action: 'google', loading: true });
      const result = await this.auth.signInWithPopup(this.googleProvider);
      this.emit('loading', { action: 'google', loading: false });
      this.emit('loginSuccess', { user: result.user, provider: 'google' });
      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'google', loading: false });
      if (error.code === 'auth/popup-closed-by-user') {
        return { success: false, error: 'Sign in cancelled' };
      }
      this.emit('error', { action: 'google', error });
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  async signInWithApple() {
    try {
      this.emit('loading', { action: 'apple', loading: true });
      const result = await this.auth.signInWithPopup(this.appleProvider);
      this.emit('loading', { action: 'apple', loading: false });
      this.emit('loginSuccess', { user: result.user, provider: 'apple' });
      return { success: true, user: result.user };
    } catch (error) {
      this.emit('loading', { action: 'apple', loading: false });
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

  async signOut() {
    try {
      if (this.auth) {
        await this.auth.signOut();
      }
      this.user = null;
      this.profile = null;
      localStorage.removeItem('buzzaboo-remember-me');
      this.emit('signedOut');
      return { success: true };
    } catch (error) {
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  async updateProfile(data) {
    if (!this.user || !this.db) {
      return { success: false, error: 'No user logged in' };
    }

    try {
      const updates = {
        ...data,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp()
      };

      await this.db.collection('users').doc(this.user.uid).update(updates);

      const authUpdates = {};
      if (data.displayName) authUpdates.displayName = data.displayName;
      if (Object.keys(authUpdates).length > 0) {
        await this.user.updateProfile(authUpdates);
      }

      this.profile = { ...this.profile, ...updates };
      this.emit('profileUpdated', this.profile);
      return { success: true, profile: this.profile };
    } catch (error) {
      console.error('Error updating profile:', error);
      return { success: false, error: this.getErrorMessage(error) };
    }
  }

  // ============================================
  // HELPERS
  // ============================================

  isAuthenticated() {
    return !!this.user;
  }

  isEmailVerified() {
    return this.user?.emailVerified || false;
  }

  getCurrentUser() {
    return this.user;
  }

  getProfile() {
    return this.profile;
  }

  getUID() {
    return this.user?.uid || null;
  }

  getDisplayName() {
    return this.profile?.displayName || this.user?.displayName || 'Stranger';
  }

  redirectIfAuthenticated() {
    if (this.isAuthenticated()) {
      const params = new URLSearchParams(window.location.search);
      const redirect = params.get('redirect') || '/chat.html';
      window.location.href = redirect;
      return true;
    }
    return false;
  }

  updateUI(isLoggedIn) {
    const userMenus = document.querySelectorAll('.user-menu, .auth-user-menu');
    const authButtons = document.querySelectorAll('.auth-buttons');
    const logoutBtns = document.querySelectorAll('.logout-btn, [data-auth="logout"]');
    const userNames = document.querySelectorAll('.user-name, .auth-display-name');

    if (isLoggedIn && this.profile) {
      userMenus.forEach(el => el.style.display = 'flex');
      authButtons.forEach(el => el.style.display = 'none');
      userNames.forEach(el => { el.textContent = this.getDisplayName(); });
      logoutBtns.forEach(btn => { btn.onclick = () => this.signOut(); });
    } else {
      userMenus.forEach(el => el.style.display = 'none');
      authButtons.forEach(el => el.style.display = 'flex');
    }
  }

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
    };
    return errorMessages[error.code] || error.message || 'An unexpected error occurred.';
  }

  // ============================================
  // EVENT SYSTEM
  // ============================================

  on(event, handler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event).add(handler);
    return () => this.off(event, handler);
  }

  off(event, handler) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) handlers.delete(handler);
  }

  emit(event, data) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => {
        try { handler(data); }
        catch (error) { console.error(`Error in event handler for ${event}:`, error); }
      });
    }
  }

  destroy() {
    if (this.unsubscribeAuth) this.unsubscribeAuth();
    if (this.unsubscribeProfile) this.unsubscribeProfile();
    this.eventHandlers.clear();
  }
}

const buzzabooAuth = new BuzzabooAuth();
window.buzzabooAuth = buzzabooAuth;
window.BuzzabooAuth = BuzzabooAuth;

document.addEventListener('DOMContentLoaded', () => {
  if (typeof firebase !== 'undefined') {
    buzzabooAuth.init().then(() => {
      window.dispatchEvent(new CustomEvent('buzzaboo-auth-ready'));
    });
  } else {
    buzzabooAuth.initialized = true;
    console.warn('Firebase SDK not loaded. Running in anonymous-only mode.');
    window.dispatchEvent(new CustomEvent('buzzaboo-auth-ready'));
  }
});
