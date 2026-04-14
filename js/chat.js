/**
 * Buzzaboo Chat Controller
 * Main orchestrator for the video chat page (chat.html)
 *
 * State machine: idle -> setup -> searching -> connected -> disconnected -> suspended
 * Coordinates: LiveKit, Matching, NSFW, Clips, Filters, Face Detection, AI Bots, Scoring
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

    // Filter engine
    this.filterEngine = null;
    this.faceDetector = null;
    this.activeFilter = null;
    this.autoBlurEnabled = true;
    this.faceRevealCountdown = null;
    this.faceRevealInterval = null;

    // Game mode
    this.gameModeEnabled = false;
    this.isBotSession = false;
    this.aiBotService = null;
    this.scoringService = null;
    this.gameTimer = null;
    this.guessTimerInterval = null;
    this.guessTimeLeft = 0;
    this.guessButtonDelay = null;
    this.hasGuessed = false;
    this.matchAttemptCount = 0;
    this.matchTimeoutId = null;

    // DOM element references
    this.dom = {};
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  async init() {
    this.bindDOM();
    this.bindEvents();
    this.bindBeforeUnload();

    // Initialize AI bot service
    this.aiBotService = new AIBotService();
    await this.aiBotService.init();

    // Initialize scoring service
    this.scoringService = new ScoringService();
    const auth = window.buzzabooAuth;
    const userId = auth.getUserId();
    const isAuth = auth.isAuthenticated();
    await this.scoringService.init(userId, isAuth);

    // Bind scoring events now that service is ready
    this.scoringService.on('scoreChanged', (data) => {
      this.updateScoreDisplay();
      if (data.reason) {
        this.showScoreAnimation(data.delta, data.reason);
      }
    });

    // Show game mode toggle if bots are available
    if (this.aiBotService.isAvailable() && this.dom.gameModeToggle) {
      this.dom.gameModeToggle.style.display = '';
    }

    // Show score badge if authenticated
    if (isAuth && this.dom.scoreBadge) {
      this.dom.scoreBadge.style.display = '';
      this.updateScoreDisplay();
    }

    // Check for active suspension
    const suspension = window.nsfwDetector.checkSuspension(userId);
    if (suspension.isSuspended) {
      this.showSuspension(suspension);
      return;
    }

    // Fast path: returning user with age + consent → skip everything, go straight to matching
    const storedAge = localStorage.getItem('buzzaboo-age');
    const hasConsent = localStorage.getItem('buzzaboo-consent') === 'true';

    if (storedAge && hasConsent) {
      this.agePool = parseInt(storedAge, 10) >= 18 ? 'adult' : 'minor';
      this.autoStartMatching();
      return;
    }

    // First-time user: age gate → consent → setup
    if (storedAge) {
      this.agePool = parseInt(storedAge, 10) >= 18 ? 'adult' : 'minor';
      this.checkConsent();
    } else {
      this.showAgeGate();
    }
  }

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
      'suspensionOverlay', 'suspensionCountdown', 'offenseCount', 'closeChatPanelBtn',
      // New elements
      'filterBtn', 'filterTray', 'filterTrayClose', 'filterGrid',
      'faceRevealOverlay', 'faceRevealNumber',
      'gameModeToggle', 'gameModeCheckbox',
      'guessBtn', 'guessModal', 'guessTimerValue', 'guessResult',
      'guessResultIcon', 'guessResultText', 'guessResultPoints',
      'scoreBadge', 'scoreValue', 'streakBadge', 'streakValue', 'scoreAnimation'
    ];

    for (const id of ids) {
      this.dom[id] = document.getElementById(id);
    }
  }

  bindEvents() {
    // One-click age buttons
    const ageAdultBtn = document.getElementById('ageAdultBtn');
    const ageTeenBtn = document.getElementById('ageTeenBtn');
    if (ageAdultBtn) {
      ageAdultBtn.addEventListener('click', () => {
        localStorage.setItem('buzzaboo-age', '18');
        localStorage.setItem('buzzaboo-consent', 'true');
        this.agePool = 'adult';
        if (this.dom.ageGate) this.dom.ageGate.style.display = 'none';
        this.autoStartMatching();
      });
    }
    if (ageTeenBtn) {
      ageTeenBtn.addEventListener('click', () => {
        localStorage.setItem('buzzaboo-age', '15');
        localStorage.setItem('buzzaboo-consent', 'true');
        this.agePool = 'minor';
        if (this.dom.ageGate) this.dom.ageGate.style.display = 'none';
        this.autoStartMatching();
      });
    }

    // Legacy age gate (kept for backwards compat)
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
      this.dom.privacyToggle.addEventListener('click', () => {
        this.setPrivacy(!this.isPrivate);
      });
    }

    // Game mode toggle
    if (this.dom.gameModeCheckbox) {
      this.dom.gameModeCheckbox.addEventListener('change', () => {
        this.gameModeEnabled = this.dom.gameModeCheckbox.checked;
      });
    }

    // Start chatting
    if (this.dom.startBtn) {
      this.dom.startBtn.addEventListener('click', () => this.startSearching());
    }

    // Chat controls
    if (this.dom.toggleCameraBtn) this.dom.toggleCameraBtn.addEventListener('click', () => this.toggleCamera());
    if (this.dom.toggleMicBtn) this.dom.toggleMicBtn.addEventListener('click', () => this.toggleMic());
    if (this.dom.privacyBtn) this.dom.privacyBtn.addEventListener('click', () => this.togglePrivacy());
    if (this.dom.textChatBtn) this.dom.textChatBtn.addEventListener('click', () => this.toggleTextChat());
    if (this.dom.closeChatPanelBtn) this.dom.closeChatPanelBtn.addEventListener('click', () => this.toggleTextChat());
    if (this.dom.nextBtn) this.dom.nextBtn.addEventListener('click', () => this.handleNext());
    if (this.dom.stopBtn) this.dom.stopBtn.addEventListener('click', () => this.handleStop());

    // Filter controls
    if (this.dom.filterBtn) this.dom.filterBtn.addEventListener('click', () => this.toggleFilterTray());
    if (this.dom.filterTrayClose) this.dom.filterTrayClose.addEventListener('click', () => this.closeFilterTray());

    // Filter category tabs
    document.querySelectorAll('.filter-cat').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.filter-cat').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.renderFilterGrid(btn.dataset.cat);
      });
    });

    // Guess button
    if (this.dom.guessBtn) this.dom.guessBtn.addEventListener('click', () => this.showGuessModal());

    // Guess options
    document.querySelectorAll('.guess-option').forEach(btn => {
      btn.addEventListener('click', () => this.handleGuess(btn.dataset.guess));
    });

    // Text chat send
    if (this.dom.sendMessageBtn) this.dom.sendMessageBtn.addEventListener('click', () => this.sendTextMessage());
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

  bindServiceEvents() {
    const matching = window.matchingService;
    const livekit = window.livekitService;
    const nsfw = window.nsfwDetector;
    const clip = window.clipService;

    matching.on('searching', () => this.updateStatus('Searching...'));
    matching.on('matched', (data) => this.handleMatch(data));
    matching.on('timeout', () => this.handleMatchTimeout());

    livekit.on('participantConnected', () => this.updateStatus('Connected'));
    livekit.on('participantDisconnected', () => this.handlePartnerDisconnected());
    livekit.on('trackSubscribed', ({ track, participant }) => this.handleTrackSubscribed(track, participant));
    livekit.on('trackUnsubscribed', ({ track }) => this.handleTrackUnsubscribed(track));
    livekit.on('disconnected', () => {
      if (this.state === CHAT_STATES.CONNECTED) this.handlePartnerDisconnected();
    });
    livekit.on('chatMessage', (message) => this.handleIncomingChatMessage(message));

    nsfw.on('violation', (data) => this.handleNSFWViolation(data));
    clip.on('clipCaptured', (data) => console.log('Clip captured:', data.clipId));
  }

  bindBeforeUnload() {
    // Use 'pagehide' with persisted check — only cleanup on REAL unload,
    // not when mobile Safari backgrounds the tab or locks the screen.
    window.addEventListener('pagehide', (e) => {
      if (!e.persisted) {
        this.cleanup();
      }
    });
    // Desktop: also listen to beforeunload for explicit page closes
    window.addEventListener('beforeunload', () => {
      // Only cleanup if we're in a terminal state — don't abandon queue on focus loss
      if (this.state === CHAT_STATES.CONNECTED || this.state === CHAT_STATES.DISCONNECTED) {
        this.cleanup();
      }
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
    if (error) error.style.display = 'none';
    if (blocked) blocked.style.display = 'none';

    if (isNaN(age) || age < 1 || age > 120) {
      if (error) { error.textContent = 'Please enter a valid age.'; error.style.display = ''; }
      return;
    }

    if (age < 13) {
      if (blocked) { blocked.textContent = 'You must be 13 or older to use Buzzaboo.'; blocked.style.display = ''; }
      return;
    }

    localStorage.setItem('buzzaboo-age', age.toString());
    this.agePool = age >= 18 ? 'adult' : 'minor';
    if (this.dom.ageGate) this.dom.ageGate.style.display = 'none';
    this.checkConsent();
  }

  // ============================================
  // CONSENT
  // ============================================

  checkConsent() {
    if (localStorage.getItem('buzzaboo-consent') === 'true') {
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

  async autoStartMatching() {
    window.buzzabooDebugLog && window.buzzabooDebugLog('autoStartMatching begin');
    this.state = CHAT_STATES.SETUP;

    try {
      window.buzzabooDebugLog && window.buzzabooDebugLog('Requesting camera...');
      // Request HD with minimums but let the device pick its natural aspect ratio
      // (forcing aspectRatio causes iOS to crop/zoom the sensor)
      this.previewStream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 1280, min: 640 },
          height: { ideal: 720, min: 480 },
          facingMode: 'user'
        },
        audio: true
      });
      const s = this.previewStream.getVideoTracks()[0]?.getSettings();
      window.buzzabooDebugLog && window.buzzabooDebugLog('Camera OK ' + (s?.width || '?') + 'x' + (s?.height || '?'));

      // Initialize filter engine
      try {
        this.filterEngine = new FilterEngine();
        this.filterEngine.init(this.previewStream);
        window.buzzabooDebugLog && window.buzzabooDebugLog('FilterEngine OK');
      } catch (feErr) {
        window.buzzabooDebugLog && window.buzzabooDebugLog('FilterEngine FAILED: ' + feErr.message);
        this.filterEngine = null;
      }

      try {
        if (!this.faceDetector) this.faceDetector = new FaceDetectionService();
        if (this.filterEngine) this.filterEngine.setFaceDetector(this.faceDetector);
      } catch (fdErr) {
        window.buzzabooDebugLog && window.buzzabooDebugLog('FaceDetector skipped: ' + fdErr.message);
      }

      const savedPrivacy = localStorage.getItem('buzzaboo-private');
      if (savedPrivacy !== null) this.isPrivate = savedPrivacy === 'true';

      window.buzzabooDebugLog && window.buzzabooDebugLog('Calling startSearching...');
      await this.startSearching();
    } catch (err) {
      window.buzzabooDebugLog && window.buzzabooDebugLog('autoStartMatching FAILED: ' + err.message);
      this.enterSetup();
    }
  }

  async enterSetup() {
    this.state = CHAT_STATES.SETUP;
    this.hideAll();
    if (this.dom.setupPanel) this.dom.setupPanel.style.display = '';

    // Load privacy preference
    const savedPrivacy = localStorage.getItem('buzzaboo-private');
    if (savedPrivacy !== null) {
      this.isPrivate = savedPrivacy === 'true';
    }

    // Load auto-blur preference
    const savedAutoBlur = localStorage.getItem('buzzaboo-auto-blur');
    this.autoBlurEnabled = savedAutoBlur !== 'false'; // Default true

    await this.startPreview();
  }

  async startPreview() {
    try {
      this.previewStream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 1280, min: 640 },
          height: { ideal: 720, min: 480 },
          facingMode: 'user'
        },
        audio: false
      });

      // Initialize filter engine with preview stream
      this.filterEngine = new FilterEngine();
      const processedStream = this.filterEngine.init(this.previewStream);

      // Initialize face detector lazily
      if (!this.faceDetector) {
        this.faceDetector = new FaceDetectionService();
      }
      this.filterEngine.setFaceDetector(this.faceDetector);

      // Show filtered preview
      if (this.dom.previewVideo) {
        this.dom.previewVideo.srcObject = processedStream;
        this.dom.previewVideo.muted = true;
        this.dom.previewVideo.play().catch(() => {});
        this.dom.previewVideo.style.display = '';
      }
      if (this.dom.previewPlaceholder) this.dom.previewPlaceholder.style.display = 'none';
    } catch (error) {
      console.error('Camera preview failed:', error);
      if (this.dom.previewPlaceholder) this.dom.previewPlaceholder.style.display = '';
      if (this.dom.previewVideo) this.dom.previewVideo.style.display = 'none';
    }
  }

  stopPreview() {
    if (this.filterEngine) {
      this.filterEngine.destroy();
      this.filterEngine = null;
    }
    if (this.previewStream) {
      this.previewStream.getTracks().forEach(track => track.stop());
      this.previewStream = null;
    }
    if (this.dom.previewVideo) this.dom.previewVideo.srcObject = null;
  }

  // ============================================
  // FILTER TRAY
  // ============================================

  toggleFilterTray() {
    if (this.dom.filterTray) {
      const visible = this.dom.filterTray.style.display !== 'none';
      this.dom.filterTray.style.display = visible ? 'none' : '';
      if (!visible) this.renderFilterGrid('face');
    }
  }

  closeFilterTray() {
    if (this.dom.filterTray) this.dom.filterTray.style.display = 'none';
  }

  renderFilterGrid(category) {
    const grid = this.dom.filterGrid;
    if (!grid) return;
    grid.innerHTML = '';

    const filters = {
      face: [
        { id: null, name: 'None', icon: '🚫' },
        { id: 'sunglasses', name: 'Shades', icon: '🕶️' },
        { id: 'devilhorns', name: 'Devil', icon: '😈' },
        { id: 'angelhalo', name: 'Angel', icon: '😇' },
        { id: 'neonoutline', name: 'Neon', icon: '💜' },
        { id: 'cartooneyes', name: 'Googly', icon: '👀' },
        { id: 'pixelretro', name: 'Pixel', icon: '🟩' }
      ],
      effects: [
        { id: null, name: 'None', icon: '🚫' },
        { id: 'vhs', name: 'VHS', icon: '📼' },
        { id: 'nightvision', name: 'Night', icon: '🌙' },
        { id: 'thermal', name: 'Thermal', icon: '🌡️' },
        { id: 'matrix', name: 'Matrix', icon: '💊' },
        { id: 'comicbook', name: 'Comic', icon: '💥' },
        { id: 'glitch', name: 'Glitch', icon: '⚡' }
      ],
      privacy: [
        { id: 'faceblur', name: 'Blur Face', icon: '🫣', toggle: true },
        { id: 'autoblur', name: 'Auto-Blur', icon: '⏱️', toggle: true }
      ]
    };

    const items = filters[category] || [];
    const currentFilter = this.filterEngine ? this.filterEngine.getFilter() : null;

    items.forEach(f => {
      const btn = document.createElement('button');
      btn.className = 'filter-item';

      if (f.toggle) {
        // Toggle-style button
        const isActive = f.id === 'faceblur'
          ? (this.filterEngine && this.filterEngine.isFaceBlurActive())
          : this.autoBlurEnabled;

        if (isActive) btn.classList.add('active');

        btn.addEventListener('click', () => {
          if (f.id === 'faceblur') {
            const newState = !(this.filterEngine && this.filterEngine.isFaceBlurActive());
            if (this.filterEngine) this.filterEngine.setFaceBlur(newState);
            if (newState && this.faceDetector && !this.faceDetector.isReady()) {
              this.faceDetector.init();
            }
          } else if (f.id === 'autoblur') {
            this.autoBlurEnabled = !this.autoBlurEnabled;
            localStorage.setItem('buzzaboo-auto-blur', this.autoBlurEnabled.toString());
          }
          this.renderFilterGrid(category);
        });
      } else {
        // Selection-style button
        if (currentFilter === f.id) btn.classList.add('active');

        btn.addEventListener('click', () => {
          if (this.filterEngine) {
            this.filterEngine.setFilter(f.id);
            // Load face detector for face filters
            if (f.id && ['sunglasses', 'devilhorns', 'angelhalo', 'neonoutline', 'cartooneyes', 'pixelretro'].includes(f.id)) {
              if (this.faceDetector && !this.faceDetector.isReady() && !this.faceDetector.isLoading()) {
                this.faceDetector.init();
              }
            }
          }
          this.renderFilterGrid(category);
        });
      }

      btn.innerHTML = `<span class="filter-item-icon">${f.icon}</span><span class="filter-item-name">${f.name}</span>`;
      grid.appendChild(btn);
    });
  }

  // ============================================
  // INTEREST TAGS
  // ============================================

  addInterest(tag) {
    if (!tag) return;
    const normalized = tag.toLowerCase().slice(0, 30);
    if (this.interests.includes(normalized)) return;
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
    if (window.clipService) window.clipService.setPrivate(isPrivate);
  }

  togglePrivacy() {
    this.setPrivacy(!this.isPrivate);
  }

  updatePrivacyUI() {
    if (this.dom.recordingIndicator) this.dom.recordingIndicator.style.display = this.isPrivate ? 'none' : '';
    if (this.dom.privacyBadge) this.dom.privacyBadge.style.display = this.isPrivate ? '' : 'none';
    if (this.dom.privacyBtn) {
      this.dom.privacyBtn.classList.toggle('active', this.isPrivate);
    }
  }

  // ============================================
  // SEARCH & MATCH
  // ============================================

  async startSearching() {
    if (this.state === CHAT_STATES.SEARCHING) return;
    this.state = CHAT_STATES.SEARCHING;
    this.matchAttemptCount = 0;
    this.hasGuessed = false;
    this.isBotSession = false;

    // Keep filter engine alive but stop preview display
    // We'll transfer it to the chat view
    if (this.dom.previewVideo) this.dom.previewVideo.srcObject = null;

    // If we don't have a filter engine yet, create one
    if (!this.filterEngine && this.previewStream) {
      this.filterEngine = new FilterEngine();
      this.filterEngine.init(this.previewStream);
      if (this.faceDetector) this.filterEngine.setFaceDetector(this.faceDetector);
    }

    // Switch UI to chat view
    this.hideAll();
    if (this.dom.chatView) this.dom.chatView.style.display = '';
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = '';
    if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = '';
    if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';
    if (this.dom.guessBtn) this.dom.guessBtn.style.display = 'none';

    // Show local video preview while waiting so user can see themselves
    // Use RAW camera stream (not filter engine) to preserve natural aspect ratio
    try {
      if (this.dom.localVideo && this.previewStream) {
        this.dom.localVideo.srcObject = this.previewStream;
        this.dom.localVideo.muted = true;
        this.dom.localVideo.play().catch(() => {});

        // Dynamically set PiP container aspect ratio to match actual camera dimensions
        // Portrait iPhone cam → 9:16 box, landscape webcam → 16:9 box, etc.
        const syncAspect = () => {
          const vw = this.dom.localVideo.videoWidth;
          const vh = this.dom.localVideo.videoHeight;
          if (vw && vh) {
            const container = this.dom.localVideo.parentElement;
            if (container) {
              container.style.aspectRatio = `${vw} / ${vh}`;
            }
          }
        };
        if (this.dom.localVideo.readyState >= 1) syncAspect();
        this.dom.localVideo.addEventListener('loadedmetadata', syncAspect, { once: true });

        window.buzzabooDebugLog && window.buzzabooDebugLog('Local preview shown (raw)');
      }
    } catch (previewErr) {
      window.buzzabooDebugLog && window.buzzabooDebugLog('Local preview failed: ' + previewErr.message);
    }

    this.updateStatus('Searching...');
    this.updatePrivacyUI();

    // Only use bots if game mode is explicitly enabled by user
    if (this.gameModeEnabled && this.aiBotService.shouldMatchWithBot(true)) {
      setTimeout(() => this.startBotMatch(), 1500 + Math.random() * 2000);
      return;
    }

    // Load NSFW model in background
    window.nsfwDetector.loadModel().catch(err => console.error('NSFW model load failed:', err));

    // Initialize LiveKit
    try {
      await window.livekitService.init();
      window.buzzabooDebugLog && window.buzzabooDebugLog('LiveKit OK');
    } catch (err) {
      window.buzzabooDebugLog && window.buzzabooDebugLog('LiveKit FAILED: ' + err.message);
    }

    // Set filter engine on LiveKit so it publishes processed track
    if (this.filterEngine) {
      try { window.livekitService.setFilterEngine(this.filterEngine); } catch (e) {
        window.buzzabooDebugLog && window.buzzabooDebugLog('setFilterEngine(livekit) FAILED: ' + e.message);
      }
    }

    // Set filter engine on clip service
    if (this.filterEngine) {
      try { window.clipService.setFilterEngine(this.filterEngine); } catch (e) {
        window.buzzabooDebugLog && window.buzzabooDebugLog('setFilterEngine(clip) FAILED: ' + e.message);
      }
    }

    // Initialize matching
    const auth = window.buzzabooAuth;
    const db = (typeof firebase !== 'undefined' && firebase.apps.length) ? firebase.firestore() : null;

    if (!db) {
      window.buzzabooDebugLog && window.buzzabooDebugLog('FIRESTORE UNAVAILABLE — firebase-config.js broken');
      this.updateStatus('Connection error — refresh the page');
      return;
    }

    const userId = auth.getUserId();
    window.buzzabooDebugLog && window.buzzabooDebugLog('Entering queue as ' + userId.slice(0, 20) + ' pool=' + this.agePool);
    window.matchingService.init(db, userId);

    try {
      await window.matchingService.enterQueue(this.interests, this.agePool);
      window.buzzabooDebugLog && window.buzzabooDebugLog('QUEUE ENTERED OK');

      // Keep searching — show user count and keep retrying
      this.matchTimeoutId = setTimeout(() => {
        if (this.state === CHAT_STATES.SEARCHING) {
          this.updateStatus('Waiting for someone to connect...');
          // Don't fall back to bot — keep searching for real humans
          // Matching service has its own retry loop
        }
      }, 15000);
    } catch (error) {
      console.error('Failed to enter queue:', error);
      this.updateStatus('Connecting... retrying');
      // Retry after 3 seconds instead of falling back to bot
      setTimeout(() => {
        this.state = CHAT_STATES.IDLE;
        this.startSearching();
      }, 3000);
    }
  }

  handleMatchTimeout() {
    // Called when matching service times out
    if (this.state === CHAT_STATES.SEARCHING && this.aiBotService.shouldFallbackToBot()) {
      this.startBotMatch();
    }
  }

  // ============================================
  // BOT MATCH
  // ============================================

  async startBotMatch() {
    if (this.state !== CHAT_STATES.SEARCHING) return;

    if (this.matchTimeoutId) {
      clearTimeout(this.matchTimeoutId);
      this.matchTimeoutId = null;
    }

    this.isBotSession = true;
    this.state = CHAT_STATES.CONNECTED;

    // Hide searching indicator
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = 'none';

    // Start bot session
    const session = await this.aiBotService.startBotSession(
      this.dom.remoteVideo,
      (text) => {
        // Bot sends a chat message
        this.appendChatMessage({
          isOwn: false,
          senderName: 'Stranger',
          text,
          timestamp: Date.now()
        });
        window.clipService.onChatMessage();
      }
    );

    if (!session) {
      // Bot failed to start, try regular matching
      this.isBotSession = false;
      this.state = CHAT_STATES.SEARCHING;
      this.handleNext();
      return;
    }

    // Show remote video or bot avatar
    if (session.bot.videoUrl) {
      if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = '';
      if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = 'none';
    } else {
      // No bot video — show an animated avatar placeholder
      if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';
      if (this.dom.remotePlaceholder) {
        this.dom.remotePlaceholder.style.display = '';
        this.dom.remotePlaceholder.innerHTML = `
          <div class="bot-avatar-placeholder">
            <div class="bot-avatar-circle">
              <span class="bot-avatar-emoji">🙂</span>
            </div>
            <p class="bot-avatar-name">${session.bot.name || 'Stranger'}</p>
            <p class="bot-avatar-hint">Say hi!</p>
          </div>`;
      }
      if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = 'none';
    }

    // Show local video with filter engine
    if (this.filterEngine && this.dom.localVideo) {
      this.dom.localVideo.srcObject = this.filterEngine.getProcessedStream();
      this.dom.localVideo.muted = true;
      this.dom.localVideo.play().catch(() => {});
    }

    // Listen for bot typing
    this.aiBotService.on('botTyping', (typing) => {
      // Could show typing indicator in text chat
    });

    // Auto-open text chat for text-only bots (no video)
    if (!session.bot.videoUrl && this.dom.textChatPanel) {
      this.dom.textChatPanel.classList.add('open');
    }

    // Start face reveal countdown if auto-blur enabled
    if (this.autoBlurEnabled) {
      this.startFaceReveal();
    }

    // Start chat timer
    this.startChatTimer();
    this.updateStatus('Connected');
    this.updatePrivacyUI();

    // Start clip recording if not private
    if (!this.isPrivate && this.dom.localVideo && this.dom.remoteVideo) {
      window.clipService.startRecording(this.dom.localVideo, this.dom.remoteVideo);
    }

    // Show guess button after 15 seconds if game mode is on
    if (this.gameModeEnabled) {
      this.guessButtonDelay = setTimeout(() => {
        if (this.dom.guessBtn && this.state === CHAT_STATES.CONNECTED) {
          this.dom.guessBtn.style.display = '';
        }
      }, 15000);

      // Auto-end guess window after 60 seconds
      this.gameTimer = setTimeout(() => {
        if (!this.hasGuessed && this.state === CHAT_STATES.CONNECTED) {
          // Time ran out, no guess made
          this.showGuessModal();
        }
      }, 60000);
    }
  }

  // ============================================
  // REAL MATCH
  // ============================================

  async handleMatch({ roomName, partnerId }) {
    if (this.matchTimeoutId) {
      clearTimeout(this.matchTimeoutId);
      this.matchTimeoutId = null;
    }

    this.roomName = roomName;
    this.partnerId = partnerId;
    this.isBotSession = false;

    const auth = window.buzzabooAuth;
    const userId = auth.getUserId();
    const displayName = auth.getDisplayName();

    // Connect to LiveKit room
    const connected = await window.livekitService.connect(roomName, userId, {
      displayName,
      metadata: { agePool: this.agePool }
    });

    if (!connected) {
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

    // Attach local video — use RAW camera stream for preview
    // (Filter engine is still what's published to LiveKit for the remote user)
    if (this.dom.localVideo && this.previewStream) {
      this.dom.localVideo.srcObject = this.previewStream;
      this.dom.localVideo.muted = true;
      this.dom.localVideo.play().catch(() => {});
    }

    // Transition to connected state
    this.state = CHAT_STATES.CONNECTED;
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = 'none';

    // Start NSFW scanning
    window.nsfwDetector.startScanning(this.dom.localVideo, this.dom.remoteVideo);

    // Start clip recording
    if (!this.isPrivate) {
      window.clipService.startRecording(this.dom.localVideo, this.dom.remoteVideo);
    }

    // Start face reveal countdown
    if (this.autoBlurEnabled) {
      this.startFaceReveal();
    }

    // Start chat timer
    this.startChatTimer();
    this.updateStatus('Connected');

    // Show guess button after 15 seconds in game mode
    if (this.gameModeEnabled) {
      this.guessButtonDelay = setTimeout(() => {
        if (this.dom.guessBtn && this.state === CHAT_STATES.CONNECTED) {
          this.dom.guessBtn.style.display = '';
        }
      }, 15000);

      this.gameTimer = setTimeout(() => {
        if (!this.hasGuessed && this.state === CHAT_STATES.CONNECTED) {
          this.showGuessModal();
        }
      }, 60000);
    }
  }

  // ============================================
  // FACE REVEAL COUNTDOWN
  // ============================================

  startFaceReveal() {
    if (!this.filterEngine) return;

    // Load face detector if not ready
    if (this.faceDetector && !this.faceDetector.isReady() && !this.faceDetector.isLoading()) {
      this.faceDetector.init();
    }

    this.filterEngine.setFaceBlur(true);
    this.faceRevealCountdown = 10;

    if (this.dom.faceRevealOverlay) this.dom.faceRevealOverlay.style.display = '';
    if (this.dom.faceRevealNumber) this.dom.faceRevealNumber.textContent = '10';

    this.faceRevealInterval = setInterval(() => {
      this.faceRevealCountdown--;

      if (this.dom.faceRevealNumber) {
        this.dom.faceRevealNumber.textContent = this.faceRevealCountdown;
        // Pulse animation
        this.dom.faceRevealNumber.classList.remove('pulse');
        void this.dom.faceRevealNumber.offsetWidth; // Force reflow
        this.dom.faceRevealNumber.classList.add('pulse');
      }

      if (this.faceRevealCountdown <= 0) {
        clearInterval(this.faceRevealInterval);
        this.faceRevealInterval = null;

        // Smooth blur dissolve
        this.animateBlurReveal();
      }
    }, 1000);
  }

  animateBlurReveal() {
    if (!this.filterEngine) return;

    const startRadius = 20;
    const duration = 1000;
    const startTime = performance.now();

    const animate = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(1, elapsed / duration);
      // Ease out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const radius = startRadius * (1 - eased);

      this.filterEngine.setBlurRadius(radius);

      if (progress < 1) {
        requestAnimationFrame(animate);
      } else {
        this.filterEngine.setFaceBlur(false);
        if (this.dom.faceRevealOverlay) this.dom.faceRevealOverlay.style.display = 'none';
      }
    };

    requestAnimationFrame(animate);
  }

  stopFaceReveal() {
    if (this.faceRevealInterval) {
      clearInterval(this.faceRevealInterval);
      this.faceRevealInterval = null;
    }
    if (this.dom.faceRevealOverlay) this.dom.faceRevealOverlay.style.display = 'none';
  }

  // ============================================
  // GUESS (Human or AI?)
  // ============================================

  showGuessModal() {
    if (this.hasGuessed) return;
    if (this.dom.guessModal) this.dom.guessModal.style.display = '';

    // Start countdown timer from remaining time
    this.guessTimeLeft = 30;
    if (this.dom.guessTimerValue) this.dom.guessTimerValue.textContent = this.guessTimeLeft;

    this.guessTimerInterval = setInterval(() => {
      this.guessTimeLeft--;
      if (this.dom.guessTimerValue) this.dom.guessTimerValue.textContent = this.guessTimeLeft;

      if (this.guessTimeLeft <= 0) {
        clearInterval(this.guessTimerInterval);
        this.guessTimerInterval = null;
        // Time's up — count as wrong guess
        this.handleGuess(this.isBotSession ? 'human' : 'ai');
      }
    }, 1000);
  }

  async handleGuess(guess) {
    if (this.hasGuessed) return;
    this.hasGuessed = true;

    // Clear timers
    if (this.guessTimerInterval) {
      clearInterval(this.guessTimerInterval);
      this.guessTimerInterval = null;
    }
    if (this.gameTimer) {
      clearTimeout(this.gameTimer);
      this.gameTimer = null;
    }

    // Hide modal
    if (this.dom.guessModal) this.dom.guessModal.style.display = 'none';
    if (this.dom.guessBtn) this.dom.guessBtn.style.display = 'none';

    // Determine correctness
    const actual = this.isBotSession ? 'ai' : 'human';
    const correct = guess === actual;

    // Record score
    const result = await this.scoringService.recordGuess(correct);

    // Show result
    this.showGuessResult(correct, result.points, actual);
  }

  showGuessResult(correct, points, actual) {
    if (!this.dom.guessResult) return;

    this.dom.guessResult.style.display = '';
    this.dom.guessResult.className = 'guess-result ' + (correct ? 'correct' : 'wrong');

    if (this.dom.guessResultIcon) {
      this.dom.guessResultIcon.textContent = correct ? '🎉' : '😮';
    }
    if (this.dom.guessResultText) {
      this.dom.guessResultText.textContent = correct
        ? `Correct! It was ${actual === 'ai' ? 'an AI' : 'a real human'}!`
        : `Wrong! It was actually ${actual === 'ai' ? 'an AI' : 'a real human'}!`;
    }
    if (this.dom.guessResultPoints) {
      this.dom.guessResultPoints.textContent = `${points > 0 ? '+' : ''}${points} points`;
      this.dom.guessResultPoints.className = 'guess-result-points ' + (points > 0 ? 'positive' : 'negative');
    }

    this.updateScoreDisplay();

    // Auto-hide after 3 seconds
    setTimeout(() => {
      if (this.dom.guessResult) this.dom.guessResult.style.display = 'none';
    }, 3000);
  }

  // ============================================
  // SCORING DISPLAY
  // ============================================

  updateScoreDisplay() {
    if (!this.scoringService || !window.buzzabooAuth.isAuthenticated()) return;

    const stats = this.scoringService.getStats();
    if (this.dom.scoreValue) this.dom.scoreValue.textContent = stats.score;
    if (this.dom.scoreBadge) this.dom.scoreBadge.style.display = '';

    if (stats.currentStreak >= 2) {
      if (this.dom.streakBadge) this.dom.streakBadge.style.display = '';
      if (this.dom.streakValue) this.dom.streakValue.textContent = stats.currentStreak;
    } else {
      if (this.dom.streakBadge) this.dom.streakBadge.style.display = 'none';
    }
  }

  showScoreAnimation(points, reason) {
    if (!this.dom.scoreAnimation) return;

    this.dom.scoreAnimation.textContent = `${points > 0 ? '+' : ''}${points}`;
    this.dom.scoreAnimation.className = 'score-animation ' + (points > 0 ? 'positive' : 'negative');
    this.dom.scoreAnimation.style.display = '';

    // Remove after animation
    setTimeout(() => {
      if (this.dom.scoreAnimation) this.dom.scoreAnimation.style.display = 'none';
    }, 1500);
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
      if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = 'none';
    } else if (track.kind === 'audio') {
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
      if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';
      if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = '';
    } else if (track.kind === 'audio') {
      const audioEl = document.getElementById('remoteAudio');
      if (audioEl) audioEl.srcObject = null;
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

    // Record chat duration for scoring
    if (this.chatStartTime) {
      const duration = Math.floor((Date.now() - this.chatStartTime) / 1000);
      this.scoringService.recordChat(duration);
    }

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

    // Record chat duration
    if (this.chatStartTime) {
      const duration = Math.floor((Date.now() - this.chatStartTime) / 1000);
      this.scoringService.recordChat(duration);
    }

    this.stopConnectedSession();
    this.state = CHAT_STATES.SEARCHING;
    this.clearTextChat();

    if (this.dom.remoteVideo) this.dom.remoteVideo.style.display = 'none';
    if (this.dom.remotePlaceholder) this.dom.remotePlaceholder.style.display = '';
    if (this.dom.searchingIndicator) this.dom.searchingIndicator.style.display = '';

    this.updateStatus('Searching...');

    // Re-start searching (will handle bot/human decision)
    this.state = CHAT_STATES.IDLE; // Reset so startSearching works
    await this.startSearching();
  }

  // ============================================
  // STOP
  // ============================================

  async handleStop() {
    if (this.chatStartTime) {
      const duration = Math.floor((Date.now() - this.chatStartTime) / 1000);
      this.scoringService.recordChat(duration);
    }

    this.stopConnectedSession();
    this.clearTextChat();
    this.state = CHAT_STATES.SETUP;
    await this.enterSetup();
  }

  async stopConnectedSession() {
    // Stop game mode timers
    if (this.gameTimer) { clearTimeout(this.gameTimer); this.gameTimer = null; }
    if (this.guessButtonDelay) { clearTimeout(this.guessButtonDelay); this.guessButtonDelay = null; }
    if (this.guessTimerInterval) { clearInterval(this.guessTimerInterval); this.guessTimerInterval = null; }
    if (this.matchTimeoutId) { clearTimeout(this.matchTimeoutId); this.matchTimeoutId = null; }

    // Hide game UI
    if (this.dom.guessBtn) this.dom.guessBtn.style.display = 'none';
    if (this.dom.guessModal) this.dom.guessModal.style.display = 'none';
    if (this.dom.guessResult) this.dom.guessResult.style.display = 'none';

    // Stop face reveal
    this.stopFaceReveal();
    if (this.filterEngine) {
      this.filterEngine.setFaceBlur(false);
    }

    // End bot session if active
    if (this.isBotSession) {
      this.aiBotService.endBotSession();
      this.isBotSession = false;
    }

    // Stop services
    window.nsfwDetector.stopScanning();
    window.clipService.stopRecording();
    await window.livekitService.disconnect();
    await window.matchingService.leaveQueue();
    this.stopChatTimer();

    this.partnerId = null;
    this.roomName = null;
    this.hasGuessed = false;
  }

  // ============================================
  // NSFW VIOLATION
  // ============================================

  async handleNSFWViolation({ source, confidence }) {
    if (source === 'local') {
      await this.stopConnectedSession();
      const auth = window.buzzabooAuth;
      const userId = auth.getUserId();
      const isAuth = auth.isAuthenticated();
      const db = (typeof firebase !== 'undefined' && firebase.apps.length) ? firebase.firestore() : null;
      await window.nsfwDetector.recordViolation(userId, isAuth, db);
      const suspension = window.nsfwDetector.checkSuspension(userId);
      this.showSuspension(suspension);
    } else if (source === 'remote') {
      if (this.partnerId) window.matchingService.reportPartner(this.partnerId, 'nsfw_auto_detection');
      this.handleNext();
    }
  }

  // ============================================
  // SUSPENSION
  // ============================================

  showSuspension(suspension) {
    this.state = CHAT_STATES.SUSPENDED;
    this.hideAll();
    if (this.dom.suspensionOverlay) this.dom.suspensionOverlay.style.display = '';
    if (this.dom.offenseCount) this.dom.offenseCount.textContent = suspension.offenseCount;

    if (suspension.isPermanent) {
      if (this.dom.suspensionCountdown) this.dom.suspensionCountdown.textContent = 'Permanently suspended';
      return;
    }

    const expiresAt = suspension.expiresAt;
    const updateCountdown = () => {
      const remaining = Math.max(0, expiresAt - Date.now());
      if (remaining <= 0) {
        if (this.dom.suspensionCountdown) this.dom.suspensionCountdown.textContent = '00:00:00';
        if (this.dom.suspensionOverlay) this.dom.suspensionOverlay.style.display = 'none';
        this.enterSetup();
        return;
      }
      const h = Math.floor(remaining / 3600000);
      const m = Math.floor((remaining % 3600000) / 60000);
      const s = Math.floor((remaining % 60000) / 1000);
      if (this.dom.suspensionCountdown) {
        this.dom.suspensionCountdown.textContent = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
      }
      this.suspensionAnimFrameId = requestAnimationFrame(updateCountdown);
    };

    if (this.suspensionAnimFrameId) cancelAnimationFrame(this.suspensionAnimFrameId);
    this.suspensionAnimFrameId = requestAnimationFrame(updateCountdown);
  }

  // ============================================
  // TEXT CHAT
  // ============================================

  toggleTextChat() {
    if (this.dom.textChatPanel) this.dom.textChatPanel.classList.toggle('open');
  }

  async sendTextMessage() {
    const input = this.dom.textChatInput;
    if (!input) return;
    const text = input.value.trim();
    if (!text || this.state !== CHAT_STATES.CONNECTED) return;
    input.value = '';

    if (this.isBotSession) {
      // Send to bot
      this.appendChatMessage({ isOwn: true, senderName: 'You', text, timestamp: Date.now() });
      this.aiBotService.handleUserMessage(text);
      window.clipService.onChatMessage();
    } else {
      try {
        await window.livekitService.sendChatMessage(text);
        window.clipService.onChatMessage();
      } catch (error) {
        console.error('Failed to send message:', error);
      }
    }
  }

  handleIncomingChatMessage(message) {
    this.appendChatMessage(message);
    if (!message.isOwn) window.clipService.onChatMessage();
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
    container.scrollTop = container.scrollHeight;
  }

  clearTextChat() {
    if (this.dom.textChatMessages) this.dom.textChatMessages.innerHTML = '';
    if (this.dom.textChatInput) this.dom.textChatInput.value = '';
    if (this.dom.textChatPanel) this.dom.textChatPanel.classList.remove('open');
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
    } catch (error) { console.error('Failed to toggle camera:', error); }
  }

  async toggleMic() {
    if (this.state !== CHAT_STATES.CONNECTED) return;
    try {
      const enabled = await window.livekitService.toggleMicrophone();
      this.isMicMuted = !enabled;
      this.updateToggleButtons();
    } catch (error) { console.error('Failed to toggle microphone:', error); }
  }

  updateToggleButtons() {
    if (this.dom.toggleCameraBtn) this.dom.toggleCameraBtn.classList.toggle('muted', this.isCameraMuted);
    if (this.dom.toggleMicBtn) this.dom.toggleMicBtn.classList.toggle('muted', this.isMicMuted);
  }

  // ============================================
  // CHAT TIMER
  // ============================================

  startChatTimer() {
    this.stopChatTimer();
    this.chatStartTime = Date.now();
    this.updateChatTimerDisplay();
    this.chatTimerInterval = setInterval(() => this.updateChatTimerDisplay(), 1000);
  }

  stopChatTimer() {
    if (this.chatTimerInterval) { clearInterval(this.chatTimerInterval); this.chatTimerInterval = null; }
    this.chatStartTime = null;
    if (this.dom.chatTimer) this.dom.chatTimer.textContent = '00:00';
  }

  updateChatTimerDisplay() {
    if (!this.chatStartTime || !this.dom.chatTimer) return;
    const elapsed = Date.now() - this.chatStartTime;
    const m = Math.floor(elapsed / 60000);
    const s = Math.floor((elapsed % 60000) / 1000);
    this.dom.chatTimer.textContent = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }

  // ============================================
  // UI HELPERS
  // ============================================

  hideAll() {
    const panels = ['ageGate', 'consentBanner', 'setupPanel', 'chatView', 'suspensionOverlay'];
    for (const id of panels) {
      if (this.dom[id]) this.dom[id].style.display = 'none';
    }
    if (this.suspensionAnimFrameId) {
      cancelAnimationFrame(this.suspensionAnimFrameId);
      this.suspensionAnimFrameId = null;
    }
  }

  updateStatus(text) {
    if (this.dom.chatStatus) this.dom.chatStatus.textContent = text;
  }

  // ============================================
  // CLEANUP
  // ============================================

  cleanup() {
    this.stopPreview();
    if (this.filterEngine) { this.filterEngine.destroy(); this.filterEngine = null; }
    if (this.faceDetector) { this.faceDetector.destroy(); this.faceDetector = null; }
    if (this.aiBotService) { this.aiBotService.destroy(); }
    if (this.scoringService) { this.scoringService.destroy(); }
    window.nsfwDetector.stopScanning();
    window.clipService.stopRecording();
    window.livekitService.disconnect();
    window.matchingService.leaveQueue();
    this.stopChatTimer();
    this.stopFaceReveal();
    if (this.gameTimer) clearTimeout(this.gameTimer);
    if (this.guessButtonDelay) clearTimeout(this.guessButtonDelay);
    if (this.matchTimeoutId) clearTimeout(this.matchTimeoutId);
    if (this.suspensionAnimFrameId) cancelAnimationFrame(this.suspensionAnimFrameId);
  }
}

// ============================================
// EXPORT & INITIALIZATION
// ============================================

const chatController = new ChatController();
window.chatController = chatController;

// Visible on-screen debug overlay — opt-in via ?debug=1 query param
const DEBUG_ENABLED = new URLSearchParams(location.search).get('debug') === '1';
const debugOverlay = document.createElement('div');
debugOverlay.id = 'buzzaboo-debug';
debugOverlay.style.cssText = 'position:fixed;bottom:0;left:0;right:0;background:rgba(0,0,0,0.9);color:#0f0;padding:8px;font-family:monospace;font-size:11px;z-index:99999;max-height:35vh;overflow-y:auto;white-space:pre-wrap;line-height:1.3;border-top:2px solid #0f0;' + (DEBUG_ENABLED ? '' : 'display:none;');
document.addEventListener('DOMContentLoaded', () => {
  document.body.appendChild(debugOverlay);
  // Add dismiss button
  const dismissBtn = document.createElement('button');
  dismissBtn.textContent = '✕ hide';
  dismissBtn.style.cssText = 'position:absolute;top:4px;right:4px;background:#333;color:#fff;border:1px solid #555;padding:2px 8px;font-size:10px;cursor:pointer;';
  dismissBtn.onclick = () => debugOverlay.style.display = 'none';
  debugOverlay.appendChild(dismissBtn);
});

function debugLog(msg) {
  console.log('[Buzzaboo]', msg);
  const line = document.createElement('div');
  line.textContent = new Date().toISOString().slice(11, 19) + ' ' + msg;
  debugOverlay.appendChild(line);
  debugOverlay.scrollTop = debugOverlay.scrollHeight;
}
window.buzzabooDebugLog = debugLog;

// Global error handlers — surface silent errors so we can debug
window.addEventListener('error', (e) => {
  debugLog('GLOBAL ERROR: ' + e.message + ' @ ' + (e.filename || '?') + ':' + (e.lineno || '?'));
});
window.addEventListener('unhandledrejection', (e) => {
  debugLog('UNHANDLED PROMISE: ' + (e.reason?.message || e.reason));
});

document.addEventListener('DOMContentLoaded', () => {
  let initialized = false;
  const doInit = () => {
    if (initialized) return;
    initialized = true;
    console.log('[Buzzaboo] Initializing chat controller...');
    chatController.init().catch(err => {
      console.error('[Buzzaboo] chatController.init failed:', err);
    });
  };
  window.addEventListener('buzzaboo-auth-ready', doInit);
  setTimeout(doInit, 2000);
});
