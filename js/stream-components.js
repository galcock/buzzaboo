/**
 * Buzzaboo Stream Components
 * UI components for live streaming with LiveKit
 */

// ============================================
// LIVE VIDEO PLAYER COMPONENT
// ============================================

class LiveVideoPlayer {
  constructor(containerId, options = {}) {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      console.error(`Container ${containerId} not found`);
      return;
    }
    
    this.options = {
      showControls: options.showControls !== false,
      showQualityBadge: options.showQualityBadge !== false,
      showViewerCount: options.showViewerCount !== false,
      autoplay: options.autoplay !== false,
      muted: options.muted || false,
      ...options
    };
    
    this.videoElement = null;
    this.currentTrack = null;
    this.isFullscreen = false;
    this.volume = 1;
    this.quality = '720p';
    
    this.init();
  }

  init() {
    this.container.innerHTML = `
      <div class="lk-player">
        <div class="lk-player-video-container">
          <video class="lk-player-video" autoplay playsinline ${this.options.muted ? 'muted' : ''}></video>
          <div class="lk-player-overlay"></div>
          <div class="lk-player-spinner">
            <div class="spinner"></div>
            <span>Connecting to stream...</span>
          </div>
          <div class="lk-player-offline">
            <div class="offline-icon">📺</div>
            <span>Stream is offline</span>
          </div>
        </div>
        
        ${this.options.showQualityBadge ? `
          <div class="lk-player-quality-badge">
            <span class="quality-text">--</span>
          </div>
        ` : ''}
        
        ${this.options.showViewerCount ? `
          <div class="lk-player-viewers">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z"/>
            </svg>
            <span class="viewer-count">0</span>
          </div>
        ` : ''}
        
        <div class="lk-player-live-badge">🔴 LIVE</div>
        
        ${this.options.showControls ? `
          <div class="lk-player-controls">
            <button class="lk-control-btn lk-play-btn" title="Play/Pause">
              <svg class="play-icon" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
                <path d="M8 5v14l11-7z"/>
              </svg>
              <svg class="pause-icon" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
                <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>
              </svg>
            </button>
            
            <div class="lk-volume-control">
              <button class="lk-control-btn lk-volume-btn" title="Volume">
                <svg class="volume-on" width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/>
                </svg>
                <svg class="volume-off" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
                  <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/>
                </svg>
              </button>
              <input type="range" class="lk-volume-slider" min="0" max="100" value="100">
            </div>
            
            <div class="lk-spacer"></div>
            
            <div class="lk-time-display">
              <span class="lk-live-indicator">● LIVE</span>
            </div>
            
            <div class="lk-quality-selector dropdown">
              <button class="lk-control-btn dropdown-trigger" title="Quality">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M19.14 12.94c.04-.31.06-.63.06-.94 0-.31-.02-.63-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.04.31-.06.63-.06.94s.02.63.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
                </svg>
              </button>
              <div class="dropdown-menu lk-quality-menu">
                <button class="dropdown-item" data-quality="1080p">1080p60</button>
                <button class="dropdown-item active" data-quality="720p">720p30</button>
                <button class="dropdown-item" data-quality="480p">480p30</button>
                <button class="dropdown-item" data-quality="360p">360p30 (Low)</button>
                <button class="dropdown-item" data-quality="auto">Auto</button>
              </div>
            </div>
            
            <button class="lk-control-btn lk-pip-btn" title="Picture-in-Picture">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M19 7h-8v6h8V7zm2-4H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H3V5h18v14z"/>
              </svg>
            </button>
            
            <button class="lk-control-btn lk-theater-btn" title="Theater Mode">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M19 4H5c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H5V6h14v12z"/>
              </svg>
            </button>
            
            <button class="lk-control-btn lk-fullscreen-btn" title="Fullscreen">
              <svg class="fullscreen-enter" width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/>
              </svg>
              <svg class="fullscreen-exit" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
                <path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/>
              </svg>
            </button>
          </div>
        ` : ''}
      </div>
    `;
    
    this.videoElement = this.container.querySelector('.lk-player-video');
    this.setupEventListeners();
    this.showSpinner(false);
    this.showOffline(true);
  }

  setupEventListeners() {
    // Play/Pause
    const playBtn = this.container.querySelector('.lk-play-btn');
    if (playBtn) {
      playBtn.addEventListener('click', () => this.togglePlay());
    }
    
    // Volume
    const volumeBtn = this.container.querySelector('.lk-volume-btn');
    const volumeSlider = this.container.querySelector('.lk-volume-slider');
    
    if (volumeBtn) {
      volumeBtn.addEventListener('click', () => this.toggleMute());
    }
    
    if (volumeSlider) {
      volumeSlider.addEventListener('input', (e) => {
        this.setVolume(e.target.value / 100);
      });
    }
    
    // Quality selector
    const qualityItems = this.container.querySelectorAll('.lk-quality-menu .dropdown-item');
    qualityItems.forEach(item => {
      item.addEventListener('click', () => {
        const quality = item.dataset.quality;
        this.setQuality(quality);
        qualityItems.forEach(i => i.classList.remove('active'));
        item.classList.add('active');
      });
    });
    
    // PiP
    const pipBtn = this.container.querySelector('.lk-pip-btn');
    if (pipBtn) {
      pipBtn.addEventListener('click', () => this.togglePiP());
    }
    
    // Theater mode
    const theaterBtn = this.container.querySelector('.lk-theater-btn');
    if (theaterBtn) {
      theaterBtn.addEventListener('click', () => {
        document.body.classList.toggle('theater-mode');
      });
    }
    
    // Fullscreen
    const fullscreenBtn = this.container.querySelector('.lk-fullscreen-btn');
    if (fullscreenBtn) {
      fullscreenBtn.addEventListener('click', () => this.toggleFullscreen());
    }
    
    // Dropdown menus
    this.container.querySelectorAll('.dropdown').forEach(dropdown => {
      const trigger = dropdown.querySelector('.dropdown-trigger');
      if (trigger) {
        trigger.addEventListener('click', (e) => {
          e.stopPropagation();
          dropdown.classList.toggle('active');
        });
      }
    });
    
    document.addEventListener('click', () => {
      this.container.querySelectorAll('.dropdown.active').forEach(d => {
        d.classList.remove('active');
      });
    });
    
    // Video events
    if (this.videoElement) {
      this.videoElement.addEventListener('play', () => this.updatePlayButton(true));
      this.videoElement.addEventListener('pause', () => this.updatePlayButton(false));
    }
  }

  /**
   * Attach a LiveKit track to the player
   */
  attachTrack(track) {
    if (!this.videoElement) return;
    
    this.currentTrack = track;
    track.attach(this.videoElement);
    
    this.showSpinner(false);
    this.showOffline(false);
    this.updateQualityBadge();
    
    if (this.options.autoplay) {
      this.videoElement.play().catch(console.error);
    }
  }

  /**
   * Detach current track
   */
  detachTrack() {
    if (this.currentTrack) {
      this.currentTrack.detach(this.videoElement);
      this.currentTrack = null;
    }
    this.showOffline(true);
  }

  /**
   * Show/hide loading spinner
   */
  showSpinner(show) {
    const spinner = this.container.querySelector('.lk-player-spinner');
    if (spinner) {
      spinner.style.display = show ? 'flex' : 'none';
    }
  }

  /**
   * Show/hide offline message
   */
  showOffline(show) {
    const offline = this.container.querySelector('.lk-player-offline');
    if (offline) {
      offline.style.display = show ? 'flex' : 'none';
    }
  }

  /**
   * Toggle play/pause
   */
  togglePlay() {
    if (this.videoElement) {
      if (this.videoElement.paused) {
        this.videoElement.play();
      } else {
        this.videoElement.pause();
      }
    }
  }

  /**
   * Update play button icon
   */
  updatePlayButton(isPlaying) {
    const playIcon = this.container.querySelector('.play-icon');
    const pauseIcon = this.container.querySelector('.pause-icon');
    if (playIcon && pauseIcon) {
      playIcon.style.display = isPlaying ? 'none' : 'block';
      pauseIcon.style.display = isPlaying ? 'block' : 'none';
    }
  }

  /**
   * Set volume
   */
  setVolume(value) {
    this.volume = Math.max(0, Math.min(1, value));
    if (this.videoElement) {
      this.videoElement.volume = this.volume;
      this.videoElement.muted = this.volume === 0;
    }
    this.updateVolumeIcon();
  }

  /**
   * Toggle mute
   */
  toggleMute() {
    if (this.videoElement) {
      this.videoElement.muted = !this.videoElement.muted;
      this.updateVolumeIcon();
    }
  }

  /**
   * Update volume icon
   */
  updateVolumeIcon() {
    const volumeOn = this.container.querySelector('.volume-on');
    const volumeOff = this.container.querySelector('.volume-off');
    if (volumeOn && volumeOff) {
      const isMuted = this.videoElement?.muted || this.volume === 0;
      volumeOn.style.display = isMuted ? 'none' : 'block';
      volumeOff.style.display = isMuted ? 'block' : 'none';
    }
  }

  /**
   * Set quality
   */
  async setQuality(quality) {
    this.quality = quality;
    this.updateQualityBadge();
    
    // If connected to LiveKit, update quality there
    if (window.livekitService?.isConnected) {
      try {
        await window.livekitService.setQuality(quality);
      } catch (e) {
        console.error('Failed to set quality:', e);
      }
    }
  }

  /**
   * Update quality badge
   */
  updateQualityBadge() {
    const badge = this.container.querySelector('.quality-text');
    if (badge) {
      const labels = {
        '1080p': '1080p60',
        '720p': '720p30',
        '480p': '480p30',
        '360p': '360p',
        'auto': 'AUTO'
      };
      badge.textContent = labels[this.quality] || this.quality;
    }
  }

  /**
   * Update viewer count
   */
  setViewerCount(count) {
    const countEl = this.container.querySelector('.viewer-count');
    if (countEl) {
      countEl.textContent = this.formatNumber(count);
    }
  }

  /**
   * Toggle Picture-in-Picture
   */
  async togglePiP() {
    if (!this.videoElement) return;
    
    try {
      if (document.pictureInPictureElement) {
        await document.exitPictureInPicture();
      } else if (document.pictureInPictureEnabled) {
        await this.videoElement.requestPictureInPicture();
      }
    } catch (e) {
      console.error('PiP error:', e);
    }
  }

  /**
   * Toggle fullscreen
   */
  async toggleFullscreen() {
    const playerEl = this.container.querySelector('.lk-player');
    
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
        this.isFullscreen = false;
      } else {
        await playerEl.requestFullscreen();
        this.isFullscreen = true;
      }
      this.updateFullscreenButton();
    } catch (e) {
      console.error('Fullscreen error:', e);
    }
  }

  /**
   * Update fullscreen button icon
   */
  updateFullscreenButton() {
    const enterIcon = this.container.querySelector('.fullscreen-enter');
    const exitIcon = this.container.querySelector('.fullscreen-exit');
    if (enterIcon && exitIcon) {
      enterIcon.style.display = this.isFullscreen ? 'none' : 'block';
      exitIcon.style.display = this.isFullscreen ? 'block' : 'none';
    }
  }

  formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }

  /**
   * Destroy player
   */
  destroy() {
    this.detachTrack();
    this.container.innerHTML = '';
  }
}

// ============================================
// LIVE CHAT COMPONENT
// ============================================

class LiveChat {
  constructor(containerId, options = {}) {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      console.error(`Container ${containerId} not found`);
      return;
    }
    
    this.options = {
      maxMessages: options.maxMessages || 200,
      showBadges: options.showBadges !== false,
      showTimestamps: options.showTimestamps || false,
      autoScroll: options.autoScroll !== false,
      ...options
    };
    
    this.messages = [];
    this.isAutoScrolling = true;
    this.userScrolledUp = false;
    
    this.init();
  }

  init() {
    this.container.innerHTML = `
      <div class="lk-chat">
        <div class="lk-chat-header">
          <div class="lk-chat-header-title">💬 Stream Chat</div>
          <div class="lk-chat-header-actions">
            <button class="lk-chat-settings-btn" title="Chat Settings">⚙️</button>
          </div>
        </div>
        
        <div class="lk-chat-messages"></div>
        
        <div class="lk-chat-paused" style="display: none;">
          <button class="lk-chat-resume-btn">Chat paused due to scroll. Click to resume.</button>
        </div>
        
        <div class="lk-chat-input-container">
          <div class="lk-chat-input-wrapper">
            <input type="text" class="lk-chat-input" placeholder="Send a message" maxlength="500">
            <button class="lk-chat-emote-btn" title="Emotes">😀</button>
            <button class="lk-chat-send-btn">Chat</button>
          </div>
        </div>
      </div>
    `;
    
    this.messagesContainer = this.container.querySelector('.lk-chat-messages');
    this.inputEl = this.container.querySelector('.lk-chat-input');
    this.sendBtn = this.container.querySelector('.lk-chat-send-btn');
    this.pausedEl = this.container.querySelector('.lk-chat-paused');
    
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Send message
    this.sendBtn?.addEventListener('click', () => this.sendMessage());
    this.inputEl?.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') this.sendMessage();
    });
    
    // Scroll detection
    this.messagesContainer?.addEventListener('scroll', () => {
      const { scrollTop, scrollHeight, clientHeight } = this.messagesContainer;
      const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
      
      if (isAtBottom) {
        this.userScrolledUp = false;
        this.pausedEl.style.display = 'none';
      } else {
        this.userScrolledUp = true;
        this.pausedEl.style.display = 'block';
      }
    });
    
    // Resume auto-scroll
    this.pausedEl?.querySelector('.lk-chat-resume-btn')?.addEventListener('click', () => {
      this.userScrolledUp = false;
      this.pausedEl.style.display = 'none';
      this.scrollToBottom();
    });
    
    // Connect to LiveKit chat
    if (window.livekitService) {
      window.livekitService.on('chatMessage', (message) => {
        this.addMessage(message);
      });
    }
  }

  /**
   * Send a chat message
   */
  async sendMessage() {
    const text = this.inputEl?.value.trim();
    if (!text) return;
    
    try {
      if (window.livekitService?.isConnected) {
        await window.livekitService.sendChatMessage(text);
      } else {
        // Local echo when not connected
        this.addMessage({
          id: Date.now(),
          senderId: 'local',
          senderName: 'You',
          text: text,
          timestamp: Date.now(),
          isOwn: true,
          badges: ['sub']
        });
      }
      this.inputEl.value = '';
    } catch (error) {
      console.error('Failed to send message:', error);
    }
  }

  /**
   * Add a message to chat
   */
  addMessage(message) {
    this.messages.push(message);
    
    // Limit messages
    while (this.messages.length > this.options.maxMessages) {
      this.messages.shift();
      this.messagesContainer?.querySelector('.lk-chat-message')?.remove();
    }
    
    this.renderMessage(message);
    
    if (!this.userScrolledUp && this.options.autoScroll) {
      this.scrollToBottom();
    }
  }

  /**
   * Render a single message
   */
  renderMessage(message) {
    const msgEl = document.createElement('div');
    msgEl.className = `lk-chat-message ${message.isOwn ? 'own' : ''}`;
    
    const badges = this.renderBadges(message.badges);
    const username = this.getUsernameClass(message);
    
    msgEl.innerHTML = `
      ${this.options.showTimestamps ? `<span class="lk-chat-timestamp">${this.formatTime(message.timestamp)}</span>` : ''}
      ${badges}
      <span class="lk-chat-username ${username}">${this.escapeHtml(message.senderName)}:</span>
      <span class="lk-chat-text">${this.parseEmotes(this.escapeHtml(message.text))}</span>
    `;
    
    this.messagesContainer?.appendChild(msgEl);
  }

  /**
   * Render badge icons
   */
  renderBadges(badges) {
    if (!badges || !this.options.showBadges) return '';
    
    const badgeIcons = {
      mod: '🛡️',
      sub: '⭐',
      vip: '💎',
      verified: '✓',
      broadcaster: '🎬'
    };
    
    return badges.map(badge => 
      `<span class="lk-chat-badge ${badge}">${badgeIcons[badge] || ''}</span>`
    ).join('');
  }

  /**
   * Get username CSS class
   */
  getUsernameClass(message) {
    if (message.badges?.includes('mod')) return 'mod';
    if (message.badges?.includes('vip')) return 'vip';
    if (message.badges?.includes('sub')) return 'sub';
    if (message.isOwn) return 'own';
    return '';
  }

  /**
   * Parse emotes in text
   */
  parseEmotes(text) {
    const emotes = {
      ':)': '😊', ':D': '😄', ':P': '😛', '<3': '❤️',
      'PogChamp': '😲', 'KEKW': '😂', 'Sadge': '😢',
      'LULW': '😆', 'monkaS': '😰', 'PepeHands': '😭',
      'LUL': '😂', 'Kappa': '😏', 'FeelsBadMan': '😞',
      'FeelsGoodMan': '😊', 'EZ': '😎', 'OMEGALUL': '🤣'
    };
    
    let result = text;
    Object.entries(emotes).forEach(([key, emoji]) => {
      const regex = new RegExp(key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
      result = result.replace(regex, emoji);
    });
    return result;
  }

  /**
   * Scroll to bottom
   */
  scrollToBottom() {
    if (this.messagesContainer) {
      this.messagesContainer.scrollTop = this.messagesContainer.scrollHeight;
    }
  }

  /**
   * Format timestamp
   */
  formatTime(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  /**
   * Escape HTML
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * Clear all messages
   */
  clear() {
    this.messages = [];
    if (this.messagesContainer) {
      this.messagesContainer.innerHTML = '';
    }
  }

  /**
   * Set placeholder for input
   */
  setPlaceholder(text) {
    if (this.inputEl) {
      this.inputEl.placeholder = text;
    }
  }

  /**
   * Enable/disable chat input
   */
  setEnabled(enabled) {
    if (this.inputEl) {
      this.inputEl.disabled = !enabled;
    }
    if (this.sendBtn) {
      this.sendBtn.disabled = !enabled;
    }
  }

  /**
   * Destroy chat
   */
  destroy() {
    this.container.innerHTML = '';
  }
}

// ============================================
// BROADCAST CONTROLS COMPONENT
// ============================================

class BroadcastControls {
  constructor(containerId, options = {}) {
    this.container = document.getElementById(containerId);
    if (!this.container) return;
    
    this.options = options;
    this.isLive = false;
    this.isCameraOn = false;
    this.isMicOn = false;
    this.isScreenSharing = false;
    
    this.init();
  }

  init() {
    this.container.innerHTML = `
      <div class="lk-broadcast-controls">
        <div class="lk-broadcast-preview">
          <video class="lk-broadcast-video" autoplay muted playsinline></video>
          <div class="lk-broadcast-preview-placeholder">
            <div class="preview-icon">📹</div>
            <span>Camera Preview</span>
          </div>
        </div>
        
        <div class="lk-broadcast-actions">
          <button class="lk-broadcast-btn lk-camera-btn" data-active="false">
            <span class="icon-on">📹</span>
            <span class="icon-off" style="display:none;">🚫</span>
            <span class="label">Camera</span>
          </button>
          
          <button class="lk-broadcast-btn lk-mic-btn" data-active="false">
            <span class="icon-on">🎤</span>
            <span class="icon-off" style="display:none;">🔇</span>
            <span class="label">Mic</span>
          </button>
          
          <button class="lk-broadcast-btn lk-screen-btn" data-active="false">
            <span class="icon-on">🖥️</span>
            <span class="icon-off" style="display:none;">❌</span>
            <span class="label">Screen</span>
          </button>
          
          <div class="lk-broadcast-spacer"></div>
          
          <button class="lk-broadcast-btn lk-settings-btn">
            <span class="icon">⚙️</span>
            <span class="label">Settings</span>
          </button>
        </div>
        
        <button class="lk-golive-btn" data-live="false">
          <span class="golive-text">🔴 Go Live</span>
          <span class="endstream-text" style="display:none;">⬛ End Stream</span>
        </button>
      </div>
    `;
    
    this.videoEl = this.container.querySelector('.lk-broadcast-video');
    this.placeholder = this.container.querySelector('.lk-broadcast-preview-placeholder');
    
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Camera toggle
    this.container.querySelector('.lk-camera-btn')?.addEventListener('click', async () => {
      await this.toggleCamera();
    });
    
    // Mic toggle
    this.container.querySelector('.lk-mic-btn')?.addEventListener('click', async () => {
      await this.toggleMic();
    });
    
    // Screen share toggle
    this.container.querySelector('.lk-screen-btn')?.addEventListener('click', async () => {
      await this.toggleScreenShare();
    });
    
    // Go Live button
    this.container.querySelector('.lk-golive-btn')?.addEventListener('click', async () => {
      await this.toggleLive();
    });
    
    // Settings
    this.container.querySelector('.lk-settings-btn')?.addEventListener('click', () => {
      this.showSettings();
    });
  }

  async toggleCamera() {
    const btn = this.container.querySelector('.lk-camera-btn');
    
    try {
      if (this.isCameraOn) {
        if (window.livekitService?.isConnected) {
          await window.livekitService.disableCamera();
        } else {
          // Stop preview
          const stream = this.videoEl?.srcObject;
          stream?.getTracks().forEach(t => t.stop());
          this.videoEl.srcObject = null;
        }
        this.isCameraOn = false;
        this.placeholder.style.display = 'flex';
      } else {
        if (window.livekitService?.isConnected) {
          const track = await window.livekitService.enableCamera();
          if (track && this.videoEl) {
            track.attach(this.videoEl);
          }
        } else {
          // Start preview
          const stream = await navigator.mediaDevices.getUserMedia({ video: true });
          if (this.videoEl) {
            this.videoEl.srcObject = stream;
          }
        }
        this.isCameraOn = true;
        this.placeholder.style.display = 'none';
      }
      
      this.updateButtonState(btn, this.isCameraOn);
    } catch (error) {
      console.error('Camera toggle error:', error);
    }
  }

  async toggleMic() {
    const btn = this.container.querySelector('.lk-mic-btn');
    
    try {
      if (this.isMicOn) {
        if (window.livekitService?.isConnected) {
          await window.livekitService.disableMicrophone();
        }
        this.isMicOn = false;
      } else {
        if (window.livekitService?.isConnected) {
          await window.livekitService.enableMicrophone();
        }
        this.isMicOn = true;
      }
      
      this.updateButtonState(btn, this.isMicOn);
    } catch (error) {
      console.error('Mic toggle error:', error);
    }
  }

  async toggleScreenShare() {
    const btn = this.container.querySelector('.lk-screen-btn');
    
    try {
      if (this.isScreenSharing) {
        if (window.livekitService?.isConnected) {
          await window.livekitService.disableScreenShare();
        }
        this.isScreenSharing = false;
      } else {
        if (window.livekitService?.isConnected) {
          await window.livekitService.enableScreenShare();
        }
        this.isScreenSharing = true;
      }
      
      this.updateButtonState(btn, this.isScreenSharing);
    } catch (error) {
      console.error('Screen share toggle error:', error);
    }
  }

  async toggleLive() {
    const btn = this.container.querySelector('.lk-golive-btn');
    
    if (this.isLive) {
      // End stream
      if (window.livekitService?.isConnected) {
        await window.livekitService.disconnect();
      }
      this.isLive = false;
      btn.dataset.live = 'false';
      btn.querySelector('.golive-text').style.display = 'inline';
      btn.querySelector('.endstream-text').style.display = 'none';
      
      if (this.options.onStreamEnd) {
        this.options.onStreamEnd();
      }
    } else {
      // Start stream
      if (!window.livekitService) {
        console.error('LiveKit service not initialized');
        return;
      }
      
      const roomName = this.options.roomName || 'broadcast-' + Date.now();
      const identity = this.options.identity || 'broadcaster-' + Math.random().toString(36).substr(2, 9);
      
      const connected = await window.livekitService.connect(roomName, identity, {
        canPublish: true,
        displayName: this.options.displayName || 'Broadcaster'
      });
      
      if (connected) {
        // Enable camera and mic
        if (!this.isCameraOn) await this.toggleCamera();
        if (!this.isMicOn) await this.toggleMic();
        
        this.isLive = true;
        btn.dataset.live = 'true';
        btn.querySelector('.golive-text').style.display = 'none';
        btn.querySelector('.endstream-text').style.display = 'inline';
        
        if (this.options.onStreamStart) {
          this.options.onStreamStart({ roomName, identity });
        }
      }
    }
  }

  updateButtonState(btn, isActive) {
    if (!btn) return;
    btn.dataset.active = isActive.toString();
    btn.querySelector('.icon-on').style.display = isActive ? 'inline' : 'none';
    btn.querySelector('.icon-off').style.display = isActive ? 'none' : 'inline';
  }

  showSettings() {
    // Could open a modal with device selection
    console.log('Show settings modal');
  }

  destroy() {
    if (this.videoEl?.srcObject) {
      this.videoEl.srcObject.getTracks().forEach(t => t.stop());
    }
    this.container.innerHTML = '';
  }
}

// Export components
window.LiveVideoPlayer = LiveVideoPlayer;
window.LiveChat = LiveChat;
window.BroadcastControls = BroadcastControls;
