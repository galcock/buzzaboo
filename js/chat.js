/**
 * Buzzaboo Chat Controller
 * Main orchestrator for the video chat page (chat.html)
 *
 * State machine: idle -> setup -> searching -> connected -> disconnected -> suspended
 * Coordinates: LiveKit (WebRTC), MatchingService, NSFWDetector, ClipService, BuzzabooAuth
 */

const CHAT_STATES = {
  IDLE: 'idle',
  SETUP: 'setup',
  SEARCHING: 'searching',
  CONNECTED: 'connected',
  DISCONNECTED: 'disconnected',
  SUSPENDED: 'suspended'
};

class ChatController {
  constructor() {
    this.state = CHAT_STATES.IDLE;
    this.agePool = null;
    this.interests = [];
    this.isPrivate = false;
    this.partnerId = null;
    this.roomName = null;
    this.previewStream = null;
    this.chatTimerInterval = null;
    this.chatStartTime = null;
    this.suspensionAnimFrameId = null;
    this.isCameraMuted = false;
    this.isMicMuted = false;

    // DOM element references (populated in bindDOM)
    this.dom = {};
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  async init() {
    this.bindDOM();
    this.bindEvents();
    this.bindBeforeUnload();

    const auth = window.buzzabooAuth;
    const userId = auth.getUserId();

    // Check for active suspension before anything else
    const suspension = window.nsfwDetector.checkSuspension(userId);
    if (suspension.isSuspended) {
      this.showSuspension(suspension);
      return;
    }

    // Determine age gate / consent flow
    const storedAge = localStorage.getItem('buzzaboo-age');
    if (storedAge) {
      this.agePool = parseInt(storedAge, 10) >= 18 ? 'adult' : 'minor';
      this.checkConsent();
    } else {
      this.showAgeGate();
    }
  }

  /**
   * Cache all DOM element references by ID.
   */
  bindDOM() {
    const ids = [
      'ageGate', 'ageInput', 'ageSubmitBtn', 'ageError', 'ageBlockedMsg',
      'consentBanner', 'consentAcceptBtn',
      'setupPanel', 'previewVideo', 'previewPlaceholder', 'interestInput',
      'interestTags', 'privacyToggle', 'startBtn',
      'chatView', 'remoteVideo', 'remotePlaceholder', 'searchingIndicator', 'localVideo',
      'chatStatusBar', 'chatStatus', 'chatTimer', 'recordingIndicator', 'privacyBadge',
      'toggleCameraBtn', 'toggleMicBtn', 'privacyBtn', 'textChatBtn', 'nextBtn', 'stopBtn',
      'textChatPanel', 'textChatMessages', 'textChatInput', 'sendMessageBtn',
      'suspensionOverlay', 'suspensionCountdown', 'offenseCount'
    ];

    for (const id of ids) {
      this.dom[id] = document.getElementById(id);
    }
  }

  /**
   * Bind all user-interaction event handlers.
   */
  bindEvents() {
    // Age gate
    if (this.dom.ageSubmitBtn) {
      this.dom.ageSubmitBtn.addEventListener('click', () => this.handleAgeSubmit());
    }
    if (this.dom.ageInput) {
      this.dom.ageInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') this.handleAgeSubmit();
      });
    }

    // Consent
    if (this.dom.consentAcceptBtn) {
      this.dom.consentAcceptBtn.addEventListener('click', () => this.handleConsentAccept());
    }

    // Interest tags
    if (this.dom.interestInput) {
      this.dom.interestInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          this.addInterest(this.dom.interestInput.value.trim());
        }
      });
    }

    // Privacy toggle
    if (this.dom.privacyToggle) {
      this.dom.privacyToggle.addEventListener('change', () => {
        this.setPrivacy(this.dom.privacyToggle.checked);
      });
    }

    // Start chatting
    if (this.dom.startBtn) {
      this.dom.startBtn.addEventListener('click', () => this.startSearching());
    }

    // Chat controls
    if (this.dom.toggleCameraBtn) {
      this.dom.toggleCameraBtn.addEventListener('click', () => this.toggleCamera());
    }
    if (this.dom.toggleMicBtn) {
      this.dom.toggleMicBtn.addEventListener('click', () => this.toggleMic());
    }
    if (this.dom.privacyBtn) {
      this.dom.privacyBtn.addEventListener('click', () => this.togglePrivacy());
    }
    if (this.dom.textChatBtn) {
      this.dom.textChatBtn.addEventListener('click', () => this.toggleTextChat());
    }
    if (this.dom.nextBtn) {
      this.dom.nextBtn.addEventListener('click', () => this.handleNext());
    }
    if (this.dom.stopBtn) {
      this.dom.stopBtn.addEventListener('click', () => this.handleStop());
    }

    // Text chat send
    if (this.dom.sendMessageBtn) {
      this.dom.sendMessageBtn.addEventListener('click', () => this.sendTextMessage());
    }
    if (this.dom.textChatInput) {
      this.dom.textChatInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          this.sendTextMessage();
        }
      });
    }

    // Service events
    this.bindServiceEvents();
  }

  /**
   * Subscribe to events from matching, livekit, nsfw, and clip services.
   */
  bindServiceEvents() {
    const matching = window.matchingService;
    const livekit = window.livekitService;
    const nsfw = window.nsfwDetector;
    const clip = window.clipService;

    matching.on('searching', () => {
      this.updateStatus('Searching...');
    });

    matching.on('matched', (data) => {
      this.handleMatch(data);
    });

    livekit.on('participantConnected', () => {
      this.updateStatus('Connected');
    });

    livekit.on('participantDisconnected', () => {
      this.handlePartnerDisconnected();
    });

    livekit.on('trackSubscribed', ({ track, participant }) => {
      this.handleTrackSubscribed(track, participant);
    });

    livekit.on('trackUnsubscribed', ({ track }) => {
      this.handleTrackUnsubscribed(track);
    });

    livekit.on('disconnected', () => {
      if (this.state === CHAT_STATES.CONNECTED) {
        this.handlePartnerDisconnected();
      }
    });

    livekit.on('chatMessage', (message) => {
      this.handleIncomingChatMessage(message);
    });

    nsfw.on('violation', (data) => {
      this.handleNSFWViolation(data);
    });

    clip.on('clipCaptured', (data) => {
      console.log('Clip captured:', data.clipId);
    });
  }

  /**
   * Register cleanup on page unload.
   */
  bindBeforeUnload() {
    window.addEventListener('beforeunload', () => {
      this.cleanup();
    });
  }

  // ============================================
  // AGE GATE
  // ============================================

  showAgeGate() {
    this.hideAll();
    if (this.dom.ageGate) this.dom.ageGate.style.display = '';
  }

  handleAgeSubmit() {
    const input = this.dom.ageInput;
    const error = this.dom.ageError;
    const blocked = this.dom.ageBlockedMsg;

    if (!input) return;

    const age = parseInt(input.value, 10);

    // Clear previous error states
    if (error) error.style.display = 'none';
    if (blocked) blocked.style.display = 'none';

    if (isNaN(age) || age < 1 || age > 120) {
      if (error) {
        error.textContent = 'Please enter a valid age.';
        error.style.display = '';
      }
      return;
    }

    if (age < 13) {
      if (blocked) {
        blocked.textContent = 'You must be 13 or older to use Buzzaboo.';
        blocked.style.display = '';
      }
      return;
    }

    // Valid age: store and determine pool
    localStorage.setItem('buzzaboo-age', age.toString());
    this.agePool = age >= 18 ? 'adult' : 'minor';

    if (this.dom.ageGate) this.dom.ageGate.style.display = 'none';
    this.checkConsent();
  }

  // ============================================
  // CONSENT
  // ============================================

  checkConsent() {
    const consented = localStorage.getItem('buzzaboo-consent') === 'true';
    if (consented) {
      this.enterSetup();
    } else {
      this.showConsentBanner();
    }
  }

  showConsentBanner() {
    if (this.dom.consentBanner) this.dom.consentBanner.style.display = '';
  }

  handleConsentAccept() {
    localStorage.setItem('buzzaboo-consent', 'true');
    if (this.dom.consentBanner) this.dom.consentBanner.style.display = 'none';
    this.enterSetup();
  }

  // ============================================
  // SETUP PHASE
  // ============================================

  async enterSetup() {
    this.state = CHAT_STATES.SETUP;
    this.hideAll();

    if (this.dom.setupPanel) this.dom.setupPanel.style.display = '';

    // Load default privacy preference from auth profile if available
    const auth = window.buzzabooAuth;
    if (auth.isAuthenticated() && auth.getProfile) {
      const profile = auth.getProfile();
      if (profile && profile.preferences && profile.preferences.privateByDefault) {
        this.isPrivate = true;
        if (this.dom.privacyToggle) this.dom.privacyToggle.checked = true;
      }
    }

    // Restore saved privacy preference from localStorage
    const savedPrivacy = localStorage.getItem('buzzaboo-private');
    if (savedPrivacy !== null) {
      this.isPrivate = savedPrivacy === 'true';
      if (this.dom.privacyToggle) this.dom.privacyToggle.checked = this.isPrivate;
    }

    // Start camera preview
    await this.startPreview();
  }

  async startPreview() {
    try {
      this.previewStream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
        audio: false
      });

      if (this.dom.previewVideo) {
        this.dom.previewVideo.srcObject = this.previewStream;
        this.dom.previewVideo.muted = true;
        this.dom.previewVideo.play().catch(() => {});
        this.dom.previewVideo.style.display = '';
      }
      if (this.dom.previewPlaceholder) {
        this.dom.previewPlaceholder.style.display = 'none';
      }
    } catch (error) {
      console.error('Camera preview failed:', error);
      if (this.dom.previewPlaceholder) {
        this.dom.previewPlaceholder.style.display = '';
      }
      if (this.dom.previewVideo) {
        this.dom.previewVideo.style.display = 'none';
      }
    }
  }

  stopPreview() {
    if (this.previewStream) {
      this.previewStream.getTracks().forEach(track => track.stop());
      this.previewStream = null;
    }
    if (this.dom.previewVideo) {
      this.dom.previewVideo.srcObject = null;
    }
  }

  // ============================================
  // INTEREST TAGS
  // ============================================

  addInterest(tag) {
    if (!tag) return;

    // Normalize: lowercase, trim, limit length
    const normalized = tag.toLowerCase().slice(0, 30);

    // Prevent duplicates
    if (this.interests.includes(normalized)) return;

    // Limit total tags
    if (this.interests.length >= 10) return;

    this.interests.push(normalized);
    this.renderInterests();

    if (this.dom.interestInput) this.dom.interestInput.value = '';
  }

  removeInterest(tag) {
    this.interests = this.interests.filter(t => t !== tag);
    this.renderInterests();
  }

  renderInterests() {
    const container = this.dom.interestTags;
    if (!container) return;

    container.innerHTML = '';

    for (const tag of this.interests) {
      const el = document.createElement('span');
      el.className = 'interest-tag';
      el.textContent = tag;

      const removeBtn = document.createElement('button');
      removeBtn.className = 'interest-tag-remove';
      removeBtn.textContent = '\u00D7';
      removeBtn.setAttribute('aria-label', `Remove ${tag}`);
      removeBtn.addEventListener('click', () => this.removeInterest(tag));

      el.appendChild(removeBtn);
      container.appendChild(el);
    }
  }

  // ============================================
  // PRIVACY
  // ============================================

  setPrivacy(isPrivate) {
    this.isPrivate = isPrivate;
    localStorage.setItem('buzzaboo-private', isPrivate.toString());
    this.updatePrivacyUI();

    if (window.clipService) {
      window.clipService.setPrivate(isPrivate);
    }
  }

  togglePrivacy() {
    this.setPrivacy(!this.isPrivate);
    if (this.dom.privacyToggle) this.dom.privacyToggle.checked = this.isPrivate;
  }

  updatePrivacyUI() {
    if (this.dom.recordingIndicator) {
      this.dom.recordingIndicator.style.display = this.isPrivate ? 'none' : '';
    }
    if (this.dom.privacyBadge) {
      this.dom.privacyBadge.style.display = this.isPrivate ? '' : 'none';
    }
    if (this.dom.privacyBtn) {
      if (this.isPrivate) {
        this.dom.privacyBtn.classList.add('active');
      } else {
        this.dom.privacyBtn.classList.remove('active');
      }
    }
  }

  // ============================================
  // SEARCH & MATCH
  // ============================================

  async startSearching() {
    if (this.state === CHAT_STATES.SEARCHING) return;

    this.state = CHAT_STATES.SEARCHING;

    // Stop preview stream — LiveKit will manage its own tracks
    this.stopPreview();

    // Switch UI to chat view
    this.hideAll();
    if (this.dom.chatView) this.dom.chatView.style.display = '';
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = '';
    if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = '';
    if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';

    this.updateStatus('Searching...');
    this.updatePrivacyUI();

    // Load NSFW model in background (non-blocking)
    window.nsfwDetector.loadModel().catch(err => {
      console.error('NSFW model load failed:', err);
    });

    // Initialize LiveKit
    await window.livekitService.init();

    // Initialize matching service with Firestore
    const auth = window.buzzabooAuth;
    const db = (typeof firebase !== 'undefined' && firebase.apps.length)
      ? firebase.firestore()
      : null;
    const userId = auth.getUserId();

    window.matchingService.init(db, userId);

    // Enter the matchmaking queue
    try {
      await window.matchingService.enterQueue(this.interests, this.agePool);
    } catch (error) {
      console.error('Failed to enter queue:', error);
      this.updateStatus('Connection error. Try again.');
      this.state = CHAT_STATES.SETUP;
      this.enterSetup();
    }
  }

  async handleMatch({ roomName, partnerId }) {
    this.roomName = roomName;
    this.partnerId = partnerId;

    const auth = window.buzzabooAuth;
    const userId = auth.getUserId();
    const displayName = auth.getDisplayName();

    // Connect to LiveKit room
    const connected = await window.livekitService.connect(roomName, userId, {
      displayName: displayName,
      metadata: { agePool: this.agePool }
    });

    if (!connected) {
      console.error('Failed to connect to LiveKit room');
      this.updateStatus('Connection failed. Retrying...');
      this.handleNext();
      return;
    }

    // Enable camera and microphone
    try {
      await window.livekitService.enableCamera();
      await window.livekitService.enableMicrophone();
    } catch (error) {
      console.error('Failed to enable media:', error);
    }

    this.isCameraMuted = false;
    this.isMicMuted = false;
    this.updateToggleButtons();

    // Attach local video
    const localTrack = window.livekitService.localVideoTrack;
    if (localTrack && this.dom.localVideo) {
      window.livekitService.attachTrack(localTrack, this.dom.localVideo);
      this.dom.localVideo.muted = true;
    }

    // Transition to connected state
    this.state = CHAT_STATES.CONNECTED;

    // Hide searching indicator
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = 'none';

    // Start NSFW scanning
    window.nsfwDetector.startScanning(this.dom.localVideo, this.dom.remoteVideo);

    // Start clip recording (if not private)
    if (!this.isPrivate) {
      window.clipService.startRecording(this.dom.localVideo, this.dom.remoteVideo);
    }

    // Start chat timer
    this.startChatTimer();

    this.updateStatus('Connected');
  }

  // ============================================
  // TRACK HANDLING
  // ============================================

  handleTrackSubscribed(track, participant) {
    if (!track) return;

    if (track.kind === 'video') {
      if (this.dom.remoteVideo) {
        window.livekitService.attachTrack(track, this.dom.remoteVideo);
        this.dom.remoteVideo.style.display = '';
      }
      if (this.dom.remotePlaceholder) {
        this.dom.remotePlaceholder.style.display = 'none';
      }
    } else if (track.kind === 'audio') {
      // Create or reuse an audio element for remote audio
      let audioEl = document.getElementById('remoteAudio');
      if (!audioEl) {
        audioEl = document.createElement('audio');
        audioEl.id = 'remoteAudio';
        audioEl.autoplay = true;
        document.body.appendChild(audioEl);
      }
      window.livekitService.attachTrack(track, audioEl);
    }
  }

  handleTrackUnsubscribed(track) {
    if (!track) return;

    if (track.kind === 'video') {
      if (this.dom.remoteVideo) {
        this.dom.remoteVideo.style.display = 'none';
      }
      if (this.dom.remotePlaceholder) {
        this.dom.remotePlaceholder.style.display = '';
      }
    } else if (track.kind === 'audio') {
      const audioEl = document.getElementById('remoteAudio');
      if (audioEl) {
        audioEl.srcObject = null;
      }
    }

    track.detach();
  }

  // ============================================
  // PARTNER DISCONNECTED
  // ============================================

  handlePartnerDisconnected() {
    if (this.state !== CHAT_STATES.CONNECTED) return;

    this.state = CHAT_STATES.DISCONNECTED;
    this.updateStatus('Partner disconnected');
    this.stopConnectedSession();

    // Auto-search for a new partner after a short delay
    setTimeout(() => {
      if (this.state === CHAT_STATES.DISCONNECTED) {
        this.startSearching();
      }
    }, 1500);
  }

  // ============================================
  // NEXT / SKIP
  // ============================================

  async handleNext() {
    if (this.state !== CHAT_STATES.CONNECTED && this.state !== CHAT_STATES.SEARCHING) return;

    this.stopConnectedSession();
    this.state = CHAT_STATES.SEARCHING;

    // Clear text chat
    this.clearTextChat();

    // Reset remote video display
    if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';
    if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = '';
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = '';

    this.updateStatus('Searching...');

    // Re-enter queue
    try {
      const auth = window.buzzabooAuth;
      const db = (typeof firebase !== 'undefined' && firebase.apps.length)
        ? firebase.firestore()
        : null;
      const userId = auth.getUserId();

      window.matchingService.init(db, userId);
      await window.matchingService.enterQueue(this.interests, this.agePool);
    } catch (error) {
      console.error('Failed to re-enter queue:', error);
      this.updateStatus('Connection error. Try again.');
    }
  }

  // ============================================
  // STOP
  // ============================================

  async handleStop() {
    this.stopConnectedSession();
    this.clearTextChat();

    // Return to setup state and restart preview
    this.state = CHAT_STATES.SETUP;
    await this.enterSetup();
  }

  /**
   * Stop all active connected-state services.
   * Shared between next, stop, and disconnect flows.
   */
  async stopConnectedSession() {
    // Stop NSFW scanning
    window.nsfwDetector.stopScanning();

    // Stop clip recording
    window.clipService.stopRecording();

    // Disconnect LiveKit
    await window.livekitService.disconnect();

    // Leave matchmaking queue
    await window.matchingService.leaveQueue();

    // Stop chat timer
    this.stopChatTimer();

    // Clear partner state
    this.partnerId = null;
    this.roomName = null;
  }

  // ============================================
  // NSFW VIOLATION HANDLING
  // ============================================

  async handleNSFWViolation({ source, confidence }) {
    if (source === 'local') {
      // Local user violated: disconnect, record, suspend
      console.warn(`Local NSFW violation detected (confidence: ${confidence.toFixed(2)})`);

      await this.stopConnectedSession();

      const auth = window.buzzabooAuth;
      const userId = auth.getUserId();
      const isAuth = auth.isAuthenticated();
      const db = (typeof firebase !== 'undefined' && firebase.apps.length)
        ? firebase.firestore()
        : null;

      const data = await window.nsfwDetector.recordViolation(userId, isAuth, db);
      const suspension = window.nsfwDetector.checkSuspension(userId);
      this.showSuspension(suspension);
    } else if (source === 'remote') {
      // Remote user violated: report and auto-skip
      console.warn(`Remote NSFW violation detected (confidence: ${confidence.toFixed(2)})`);

      if (this.partnerId) {
        window.matchingService.reportPartner(this.partnerId, 'nsfw_auto_detection');
      }

      this.handleNext();
    }
  }

  // ============================================
  // SUSPENSION DISPLAY
  // ============================================

  showSuspension(suspension) {
    this.state = CHAT_STATES.SUSPENDED;
    this.hideAll();

    if (this.dom.suspensionOverlay) this.dom.suspensionOverlay.style.display = '';
    if (this.dom.offenseCount) this.dom.offenseCount.textContent = suspension.offenseCount;

    if (suspension.isPermanent) {
      if (this.dom.suspensionCountdown) {
        this.dom.suspensionCountdown.textContent = 'Permanently suspended';
      }
      return;
    }

    // Animate countdown using requestAnimationFrame
    const expiresAt = suspension.expiresAt;
    const updateCountdown = () => {
      const remaining = Math.max(0, expiresAt - Date.now());

      if (remaining <= 0) {
        if (this.dom.suspensionCountdown) {
          this.dom.suspensionCountdown.textContent = '00:00:00';
        }
        // Suspension expired — return to setup
        if (this.dom.suspensionOverlay) this.dom.suspensionOverlay.style.display = 'none';
        this.enterSetup();
        return;
      }

      const hours = Math.floor(remaining / 3600000);
      const minutes = Math.floor((remaining % 3600000) / 60000);
      const seconds = Math.floor((remaining % 60000) / 1000);

      const formatted =
        String(hours).padStart(2, '0') + ':' +
        String(minutes).padStart(2, '0') + ':' +
        String(seconds).padStart(2, '0');

      if (this.dom.suspensionCountdown) {
        this.dom.suspensionCountdown.textContent = formatted;
      }

      this.suspensionAnimFrameId = requestAnimationFrame(updateCountdown);
    };

    // Cancel any previous countdown animation
    if (this.suspensionAnimFrameId) {
      cancelAnimationFrame(this.suspensionAnimFrameId);
    }

    this.suspensionAnimFrameId = requestAnimationFrame(updateCountdown);
  }

  // ============================================
  // TEXT CHAT
  // ============================================

  toggleTextChat() {
    if (this.dom.textChatPanel) {
      this.dom.textChatPanel.classList.toggle('open');
    }
  }

  async sendTextMessage() {
    const input = this.dom.textChatInput;
    if (!input) return;

    const text = input.value.trim();
    if (!text) return;

    if (this.state !== CHAT_STATES.CONNECTED) return;

    input.value = '';

    try {
      await window.livekitService.sendChatMessage(text);
      // The chatMessage event will handle UI update for own messages
      // Notify clip service of chat activity
      window.clipService.onChatMessage();
    } catch (error) {
      console.error('Failed to send message:', error);
    }
  }

  handleIncomingChatMessage(message) {
    this.appendChatMessage(message);

    // Notify clip service of chat activity for highlight detection
    if (!message.isOwn) {
      window.clipService.onChatMessage();
    }
  }

  appendChatMessage(message) {
    const container = this.dom.textChatMessages;
    if (!container) return;

    const msgEl = document.createElement('div');
    msgEl.className = 'chat-message' + (message.isOwn ? ' own' : '');

    const nameEl = document.createElement('span');
    nameEl.className = 'chat-message-name';
    nameEl.textContent = message.isOwn ? 'You' : (message.senderName || 'Stranger');

    const textEl = document.createElement('span');
    textEl.className = 'chat-message-text';
    textEl.textContent = message.text;

    msgEl.appendChild(nameEl);
    msgEl.appendChild(textEl);
    container.appendChild(msgEl);

    // Auto-scroll to bottom
    container.scrollTop = container.scrollHeight;
  }

  clearTextChat() {
    if (this.dom.textChatMessages) {
      this.dom.textChatMessages.innerHTML = '';
    }
    if (this.dom.textChatInput) {
      this.dom.textChatInput.value = '';
    }
    // Close text chat panel
    if (this.dom.textChatPanel) {
      this.dom.textChatPanel.classList.remove('open');
    }
  }

  // ============================================
  // CAMERA / MIC TOGGLES
  // ============================================

  async toggleCamera() {
    if (this.state !== CHAT_STATES.CONNECTED) return;

    try {
      const enabled = await window.livekitService.toggleCamera();
      this.isCameraMuted = !enabled;
      this.updateToggleButtons();
    } catch (error) {
      console.error('Failed to toggle camera:', error);
    }
  }

  async toggleMic() {
    if (this.state !== CHAT_STATES.CONNECTED) return;

    try {
      const enabled = await window.livekitService.toggleMicrophone();
      this.isMicMuted = !enabled;
      this.updateToggleButtons();
    } catch (error) {
      console.error('Failed to toggle microphone:', error);
    }
  }

  updateToggleButtons() {
    if (this.dom.toggleCameraBtn) {
      if (this.isCameraMuted) {
        this.dom.toggleCameraBtn.classList.add('muted');
      } else {
        this.dom.toggleCameraBtn.classList.remove('muted');
      }
    }
    if (this.dom.toggleMicBtn) {
      if (this.isMicMuted) {
        this.dom.toggleMicBtn.classList.add('muted');
      } else {
        this.dom.toggleMicBtn.classList.remove('muted');
      }
    }
  }

  // ============================================
  // CHAT TIMER
  // ============================================

  startChatTimer() {
    this.stopChatTimer();
    this.chatStartTime = Date.now();
    this.updateChatTimerDisplay();

    this.chatTimerInterval = setInterval(() => {
      this.updateChatTimerDisplay();
    }, 1000);
  }

  stopChatTimer() {
    if (this.chatTimerInterval) {
      clearInterval(this.chatTimerInterval);
      this.chatTimerInterval = null;
    }
    this.chatStartTime = null;

    if (this.dom.chatTimer) {
      this.dom.chatTimer.textContent = '00:00';
    }
  }

  updateChatTimerDisplay() {
    if (!this.chatStartTime || !this.dom.chatTimer) return;

    const elapsed = Date.now() - this.chatStartTime;
    const minutes = Math.floor(elapsed / 60000);
    const seconds = Math.floor((elapsed % 60000) / 1000);

    this.dom.chatTimer.textContent =
      String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
  }

  // ============================================
  // UI HELPERS
  // ============================================

  hideAll() {
    const panels = [
      'ageGate', 'consentBanner', 'setupPanel', 'chatView', 'suspensionOverlay'
    ];
    for (const id of panels) {
      if (this.dom[id]) this.dom[id].style.display = 'none';
    }

    // Cancel any active suspension countdown
    if (this.suspensionAnimFrameId) {
      cancelAnimationFrame(this.suspensionAnimFrameId);
      this.suspensionAnimFrameId = null;
    }
  }

  updateStatus(text) {
    if (this.dom.chatStatus) {
      this.dom.chatStatus.textContent = text;
    }
  }

  // ============================================
  // CLEANUP
  // ============================================

  cleanup() {
    this.stopPreview();
    window.nsfwDetector.stopScanning();
    window.clipService.stopRecording();
    window.livekitService.disconnect();
    window.matchingService.leaveQueue();
    this.stopChatTimer();

    if (this.suspensionAnimFrameId) {
      cancelAnimationFrame(this.suspensionAnimFrameId);
      this.suspensionAnimFrameId = null;
    }
  }
}

// ============================================
// EXPORT & INITIALIZATION
// ============================================

const chatController = new ChatController();
window.chatController = chatController;

document.addEventListener('DOMContentLoaded', () => {
  let initialized = false;

  const doInit = () => {
    if (initialized) return;
    initialized = true;
    chatController.init();
  };

  // Wait for auth service to be ready
  window.addEventListener('buzzaboo-auth-ready', doInit);

  // Fallback: initialize after 2 seconds if auth-ready never fires
  setTimeout(doInit, 2000);
});
