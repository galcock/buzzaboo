/**
 * Buzzaboo Auth Modal Component
 * A reusable auth modal that can be triggered from any page
 */

class AuthModal {
  constructor() {
    this.modal = null;
    this.currentView = 'login';
    this.onSuccess = null;
    this.isOpen = false;
  }

  /**
   * Initialize the modal
   */
  init() {
    this.createModal();
    this.bindEvents();
    return this;
  }

  /**
   * Create the modal HTML
   */
  createModal() {
    const modalHTML = `
      <div class="auth-modal-overlay" id="authModalOverlay">
        <div class="auth-modal glass-card" id="authModal">
          <button class="auth-modal-close" id="authModalClose">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
          </button>
          
          <!-- Login View -->
          <div class="auth-modal-view" id="loginView">
            <div class="auth-header">
              <h2 class="auth-title">Welcome back</h2>
              <p class="auth-subtitle">Sign in to continue</p>
            </div>

            <div class="auth-message auth-message-error" id="loginError" style="display: none;">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>
              <span id="loginErrorText"></span>
            </div>

            <div class="auth-social">
              <button type="button" class="btn btn-social btn-google" id="modalGoogleLogin">
                <svg width="20" height="20" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
                <span>Continue with Google</span>
              </button>
              <button type="button" class="btn btn-social btn-apple" id="modalAppleLogin">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/></svg>
                <span>Continue with Apple</span>
              </button>
            </div>

            <div class="auth-divider"><span>or</span></div>

            <form id="modalLoginForm" class="auth-form">
              <div class="form-group">
                <input type="email" id="modalLoginEmail" class="form-input form-input-clean" placeholder="Email" required>
              </div>
              <div class="form-group">
                <input type="password" id="modalLoginPassword" class="form-input form-input-clean" placeholder="Password" required minlength="6">
              </div>
              <button type="submit" class="btn btn-primary btn-block" id="modalLoginBtn">
                <span class="btn-text">Sign In</span>
                <span class="btn-loader" style="display: none;">
                  <svg class="spinner" width="20" height="20" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="3" opacity="0.3"/><path d="M12 2a10 10 0 0 1 10 10" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>
                </span>
              </button>
            </form>

            <div class="auth-modal-footer">
              <a href="#" class="auth-link-small" id="showForgotPassword">Forgot password?</a>
              <span class="auth-footer-divider">•</span>
              <span>Don't have an account? <a href="#" class="auth-link" id="showSignup">Sign up</a></span>
            </div>
          </div>

          <!-- Signup View -->
          <div class="auth-modal-view" id="signupView" style="display: none;">
            <div class="auth-header">
              <h2 class="auth-title">Create account</h2>
              <p class="auth-subtitle">Join the Buzzaboo community</p>
            </div>

            <div class="auth-message auth-message-error" id="signupError" style="display: none;">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>
              <span id="signupErrorText"></span>
            </div>

            <div class="auth-social">
              <button type="button" class="btn btn-social btn-google" id="modalGoogleSignup">
                <svg width="20" height="20" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
                <span>Sign up with Google</span>
              </button>
            </div>

            <div class="auth-divider"><span>or</span></div>

            <form id="modalSignupForm" class="auth-form">
              <div class="form-group">
                <input type="text" id="modalSignupName" class="form-input form-input-clean" placeholder="Display name" required minlength="2">
              </div>
              <div class="form-group">
                <input type="email" id="modalSignupEmail" class="form-input form-input-clean" placeholder="Email" required>
              </div>
              <div class="form-group">
                <input type="password" id="modalSignupPassword" class="form-input form-input-clean" placeholder="Password (min 6 characters)" required minlength="6">
              </div>
              <button type="submit" class="btn btn-primary btn-block" id="modalSignupBtn">
                <span class="btn-text">Create Account</span>
                <span class="btn-loader" style="display: none;">
                  <svg class="spinner" width="20" height="20" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="3" opacity="0.3"/><path d="M12 2a10 10 0 0 1 10 10" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>
                </span>
              </button>
            </form>

            <div class="auth-modal-footer">
              <span>Already have an account? <a href="#" class="auth-link" id="showLogin">Sign in</a></span>
            </div>
          </div>

          <!-- Forgot Password View -->
          <div class="auth-modal-view" id="forgotView" style="display: none;">
            <div class="auth-header">
              <h2 class="auth-title">Reset password</h2>
              <p class="auth-subtitle">We'll send you a reset link</p>
            </div>

            <div class="auth-message auth-message-success" id="forgotSuccess" style="display: none;">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
              <span>Check your email for the reset link!</span>
            </div>

            <div class="auth-message auth-message-error" id="forgotError" style="display: none;">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>
              <span id="forgotErrorText"></span>
            </div>

            <form id="modalForgotForm" class="auth-form">
              <div class="form-group">
                <input type="email" id="modalForgotEmail" class="form-input form-input-clean" placeholder="Email" required>
              </div>
              <button type="submit" class="btn btn-primary btn-block" id="modalForgotBtn">
                <span class="btn-text">Send Reset Link</span>
                <span class="btn-loader" style="display: none;">
                  <svg class="spinner" width="20" height="20" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="3" opacity="0.3"/><path d="M12 2a10 10 0 0 1 10 10" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>
                </span>
              </button>
            </form>

            <div class="auth-modal-footer">
              <a href="#" class="auth-link" id="backToLogin">← Back to login</a>
            </div>
          </div>
        </div>
      </div>
    `;

    // Add styles
    const styles = `
      <style id="authModalStyles">
        .auth-modal-overlay {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.8);
          backdrop-filter: blur(4px);
          display: none;
          align-items: center;
          justify-content: center;
          z-index: 9999;
          padding: var(--spacing-lg);
          animation: fadeIn 0.2s ease-out;
        }

        .auth-modal-overlay.active {
          display: flex;
        }

        .auth-modal {
          width: 100%;
          max-width: 420px;
          padding: var(--spacing-2xl);
          position: relative;
          animation: slideUp 0.3s ease-out;
        }

        .auth-modal-close {
          position: absolute;
          top: var(--spacing-md);
          right: var(--spacing-md);
          background: none;
          border: none;
          color: var(--text-muted);
          cursor: pointer;
          padding: var(--spacing-xs);
          border-radius: var(--radius-sm);
          transition: all var(--transition-fast);
        }

        .auth-modal-close:hover {
          color: var(--text-primary);
          background: var(--bg-glass);
        }

        .auth-modal .auth-header {
          text-align: center;
          margin-bottom: var(--spacing-xl);
        }

        .auth-modal .auth-title {
          font-size: 1.5rem;
        }

        .auth-modal .auth-social {
          margin-bottom: var(--spacing-lg);
        }

        .form-input-clean {
          padding-left: var(--spacing-md) !important;
        }

        .auth-modal-footer {
          text-align: center;
          margin-top: var(--spacing-lg);
          font-size: 0.9rem;
          color: var(--text-secondary);
        }

        .auth-link-small {
          color: var(--text-muted);
          font-size: 0.85rem;
        }

        .auth-link-small:hover {
          color: var(--primary);
        }

        .auth-footer-divider {
          margin: 0 var(--spacing-sm);
          color: var(--text-muted);
        }

        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }

        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }
      </style>
    `;

    // Inject into page
    document.head.insertAdjacentHTML('beforeend', styles);
    document.body.insertAdjacentHTML('beforeend', modalHTML);

    this.modal = document.getElementById('authModalOverlay');
  }

  /**
   * Bind all event handlers
   */
  bindEvents() {
    // Close handlers
    document.getElementById('authModalClose').addEventListener('click', () => this.close());
    this.modal.addEventListener('click', (e) => {
      if (e.target === this.modal) this.close();
    });

    // View switching
    document.getElementById('showSignup').addEventListener('click', (e) => {
      e.preventDefault();
      this.showView('signup');
    });

    document.getElementById('showLogin').addEventListener('click', (e) => {
      e.preventDefault();
      this.showView('login');
    });

    document.getElementById('showForgotPassword').addEventListener('click', (e) => {
      e.preventDefault();
      this.showView('forgot');
    });

    document.getElementById('backToLogin').addEventListener('click', (e) => {
      e.preventDefault();
      this.showView('login');
    });

    // Login form
    document.getElementById('modalLoginForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      await this.handleLogin();
    });

    // Signup form
    document.getElementById('modalSignupForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      await this.handleSignup();
    });

    // Forgot password form
    document.getElementById('modalForgotForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      await this.handleForgotPassword();
    });

    // Social login
    document.getElementById('modalGoogleLogin').addEventListener('click', () => this.handleGoogleLogin());
    document.getElementById('modalAppleLogin').addEventListener('click', () => this.handleAppleLogin());
    document.getElementById('modalGoogleSignup').addEventListener('click', () => this.handleGoogleLogin());

    // Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.isOpen) {
        this.close();
      }
    });
  }

  /**
   * Show a specific view
   */
  showView(view) {
    this.currentView = view;
    
    // Hide all views
    document.querySelectorAll('.auth-modal-view').forEach(v => v.style.display = 'none');
    
    // Show requested view
    const viewMap = {
      'login': 'loginView',
      'signup': 'signupView',
      'forgot': 'forgotView'
    };
    
    document.getElementById(viewMap[view]).style.display = 'block';
    
    // Clear errors
    this.clearErrors();
  }

  /**
   * Open the modal
   */
  open(view = 'login', onSuccess = null) {
    this.onSuccess = onSuccess;
    this.showView(view);
    this.modal.classList.add('active');
    this.isOpen = true;
    document.body.style.overflow = 'hidden';
  }

  /**
   * Close the modal
   */
  close() {
    this.modal.classList.remove('active');
    this.isOpen = false;
    document.body.style.overflow = '';
    this.clearErrors();
    this.clearForms();
  }

  /**
   * Clear all error messages
   */
  clearErrors() {
    document.querySelectorAll('.auth-message').forEach(el => el.style.display = 'none');
  }

  /**
   * Clear all forms
   */
  clearForms() {
    document.getElementById('modalLoginForm').reset();
    document.getElementById('modalSignupForm').reset();
    document.getElementById('modalForgotForm').reset();
  }

  /**
   * Set loading state on a button
   */
  setLoading(buttonId, loading) {
    const btn = document.getElementById(buttonId);
    btn.disabled = loading;
    btn.querySelector('.btn-text').style.display = loading ? 'none' : 'inline';
    btn.querySelector('.btn-loader').style.display = loading ? 'inline-flex' : 'none';
  }

  /**
   * Show error message
   */
  showError(view, message) {
    const errorMap = {
      'login': ['loginError', 'loginErrorText'],
      'signup': ['signupError', 'signupErrorText'],
      'forgot': ['forgotError', 'forgotErrorText']
    };

    const [containerId, textId] = errorMap[view];
    document.getElementById(textId).textContent = message;
    document.getElementById(containerId).style.display = 'flex';
  }

  /**
   * Handle login
   */
  async handleLogin() {
    const email = document.getElementById('modalLoginEmail').value;
    const password = document.getElementById('modalLoginPassword').value;

    this.clearErrors();
    this.setLoading('modalLoginBtn', true);

    const result = await buzzabooAuth.signInWithEmail(email, password, true);

    this.setLoading('modalLoginBtn', false);

    if (result.success) {
      this.close();
      if (this.onSuccess) this.onSuccess(result.user);
    } else {
      this.showError('login', result.error);
    }
  }

  /**
   * Handle signup
   */
  async handleSignup() {
    const name = document.getElementById('modalSignupName').value;
    const email = document.getElementById('modalSignupEmail').value;
    const password = document.getElementById('modalSignupPassword').value;

    this.clearErrors();
    this.setLoading('modalSignupBtn', true);

    const result = await buzzabooAuth.signUpWithEmail(email, password, name);

    this.setLoading('modalSignupBtn', false);

    if (result.success) {
      this.close();
      if (this.onSuccess) this.onSuccess(result.user);
      // Show toast about verification email
      if (window.Toast) {
        Toast.success('Account created!', 'Please check your email to verify your account.');
      }
    } else {
      this.showError('signup', result.error);
    }
  }

  /**
   * Handle forgot password
   */
  async handleForgotPassword() {
    const email = document.getElementById('modalForgotEmail').value;

    this.clearErrors();
    this.setLoading('modalForgotBtn', true);

    const result = await buzzabooAuth.sendPasswordReset(email);

    this.setLoading('modalForgotBtn', false);

    if (result.success) {
      document.getElementById('forgotSuccess').style.display = 'flex';
    } else {
      this.showError('forgot', result.error);
    }
  }

  /**
   * Handle Google login
   */
  async handleGoogleLogin() {
    this.clearErrors();
    
    const result = await buzzabooAuth.signInWithGoogle();

    if (result.success) {
      this.close();
      if (this.onSuccess) this.onSuccess(result.user);
    } else if (result.error !== 'Sign in cancelled') {
      this.showError(this.currentView, result.error);
    }
  }

  /**
   * Handle Apple login
   */
  async handleAppleLogin() {
    this.clearErrors();
    
    const result = await buzzabooAuth.signInWithApple();

    if (result.success) {
      this.close();
      if (this.onSuccess) this.onSuccess(result.user);
    } else if (result.error !== 'Sign in cancelled') {
      this.showError(this.currentView, result.error);
    }
  }
}

// Create global instance
const authModal = new AuthModal();

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  authModal.init();
});

// Export
window.authModal = authModal;
window.AuthModal = AuthModal;
