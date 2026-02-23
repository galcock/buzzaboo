/**
 * Buzzaboo Call Components
 * 1-on-1 video calls and multiview streaming
 */

// ============================================
// VIDEO CALL COMPONENT
// ============================================

class VideoCall {
  constructor(containerId, options = {}) {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      console.error(`Container ${containerId} not found`);
      return;
    }
    
    this.options = {
      localVideoId: 'local-video',
      remoteVideoId: 'remote-video',
      ...options
    };
    
    this.localVideoEl = null;
    this.remoteVideoEl = null;
    this.callState = 'idle'; // idle, connecting, connected, ended
    this.remotParticipant = null;
    
    this.init();
  }

  init() {
    this.container.innerHTML = `
      <div class="lk-video-call">
        <div class="lk-call-videos">
          <div class="lk-remote-video-container">
            <video id="${this.options.remoteVideoId}" class="lk-remote-video" autoplay playsinline></video>
            <div class="lk-remote-placeholder">
              <div class="placeholder-avatar">👤</div>
              <span>Waiting for participant...</span>
            </div>
            <div class="lk-remote-info">
              <span class="lk-remote-name"></span>
              <span class="lk-connection-quality">●</span>
            </div>
          </div>
          
          <div class="lk-local-video-container">
            <video id="${this.options.localVideoId}" class="lk-local-video" autoplay muted playsinline></video>
            <div class="lk-local-placeholder">
              <div class="placeholder-icon">📹</div>
            </div>
          </div>
        </div>
        
        <div class="lk-call-status">
          <span class="status-text">Not in a call</span>
          <span class="status-timer"></span>
        </div>
        
        <div class="lk-call-controls">
          <button class="lk-call-btn lk-camera-toggle" data-active="true" title="Toggle Camera">
            <svg class="icon-on" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z"/>
            </svg>
            <svg class="icon-off" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
              <path d="M21 6.5l-4 4V7c0-.55-.45-1-1-1H9.82L21 17.18V6.5zM3.27 2L2 3.27 4.73 6H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.21 0 .39-.08.54-.18L19.73 21 21 19.73 3.27 2z"/>
            </svg>
          </button>
          
          <button class="lk-call-btn lk-mic-toggle" data-active="true" title="Toggle Microphone">
            <svg class="icon-on" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 14c1.66 0 2.99-1.34 2.99-3L15 5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.48 6-3.3 6-6.72h-1.7z"/>
            </svg>
            <svg class="icon-off" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
              <path d="M19 11h-1.7c0 .74-.16 1.43-.43 2.05l1.23 1.23c.56-.98.9-2.09.9-3.28zm-4.02.17c0-.06.02-.11.02-.17V5c0-1.66-1.34-3-3-3S9 3.34 9 5v.18l5.98 5.99zM4.27 3L3 4.27l6.01 6.01V11c0 1.66 1.33 3 2.99 3 .22 0 .44-.03.65-.08l1.66 1.66c-.71.33-1.5.52-2.31.52-2.76 0-5.3-2.1-5.3-5.1H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c.91-.13 1.77-.45 2.54-.9L19.73 21 21 19.73 4.27 3z"/>
            </svg>
          </button>
          
          <button class="lk-call-btn lk-screen-toggle" data-active="false" title="Share Screen">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
              <path d="M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z"/>
            </svg>
          </button>
          
          <div class="lk-call-spacer"></div>
          
          <button class="lk-call-btn lk-end-call danger" title="End Call">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 9c-1.6 0-3.15.25-4.6.72v3.1c0 .39-.23.74-.56.9-.98.49-1.87 1.12-2.66 1.85-.18.18-.43.28-.7.28-.28 0-.53-.11-.71-.29L.29 13.08c-.18-.17-.29-.42-.29-.7 0-.28.11-.53.29-.71C3.34 8.78 7.46 7 12 7s8.66 1.78 11.71 4.67c.18.18.29.43.29.71 0 .28-.11.53-.29.71l-2.48 2.48c-.18.18-.43.29-.71.29-.27 0-.52-.11-.7-.28-.79-.74-1.69-1.36-2.67-1.85-.33-.16-.56-.5-.56-.9v-3.1C15.15 9.25 13.6 9 12 9z"/>
            </svg>
          </button>
        </div>
        
        <div class="lk-call-join" style="display:none;">
          <input type="text" class="lk-call-room-input" placeholder="Enter room code...">
          <button class="lk-join-btn">Join Call</button>
          <span class="or-divider">or</span>
          <button class="lk-create-btn">Create New Room</button>
        </div>
      </div>
    `;
    
    this.localVideoEl = this.container.querySelector('.lk-local-video');
    this.remoteVideoEl = this.container.querySelector('.lk-remote-video');
    
    this.setupEventListeners();
    this.showJoinUI();
  }

  setupEventListeners() {
    // Camera toggle
    this.container.querySelector('.lk-camera-toggle')?.addEventListener('click', async () => {
      await this.toggleCamera();
    });
    
    // Mic toggle
    this.container.querySelector('.lk-mic-toggle')?.addEventListener('click', async () => {
      await this.toggleMic();
    });
    
    // Screen share toggle
    this.container.querySelector('.lk-screen-toggle')?.addEventListener('click', async () => {
      await this.toggleScreenShare();
    });
    
    // End call
    this.container.querySelector('.lk-end-call')?.addEventListener('click', async () => {
      await this.endCall();
    });
    
    // Join room
    this.container.querySelector('.lk-join-btn')?.addEventListener('click', async () => {
      const input = this.container.querySelector('.lk-call-room-input');
      const roomCode = input?.value.trim();
      if (roomCode) {
        await this.joinRoom(roomCode);
      }
    });
    
    // Create room
    this.container.querySelector('.lk-create-btn')?.addEventListener('click', async () => {
      const roomCode = this.generateRoomCode();
      await this.joinRoom(roomCode);
    });
    
    // LiveKit events
    if (window.livekitService) {
      window.livekitService.on('participantConnected', ({ participant }) => {
        this.handleParticipantConnected(participant);
      });
      
      window.livekitService.on('participantDisconnected', ({ participant }) => {
        this.handleParticipantDisconnected(participant);
      });
      
      window.livekitService.on('trackSubscribed', ({ track, participant }) => {
        this.handleTrackSubscribed(track, participant);
      });
      
      window.livekitService.on('trackUnsubscribed', ({ track }) => {
        this.handleTrackUnsubscribed(track);
      });
    }
  }

  showJoinUI() {
    this.container.querySelector('.lk-call-join').style.display = 'flex';
    this.container.querySelector('.lk-call-controls').style.display = 'none';
    this.container.querySelector('.lk-call-videos').style.opacity = '0.5';
    this.setStatus('Enter a room code or create a new room');
  }

  hideJoinUI() {
    this.container.querySelector('.lk-call-join').style.display = 'none';
    this.container.querySelector('.lk-call-controls').style.display = 'flex';
    this.container.querySelector('.lk-call-videos').style.opacity = '1';
  }

  generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
  }

  async joinRoom(roomCode) {
    if (!window.livekitService) {
      console.error('LiveKit service not available');
      return;
    }
    
    this.setStatus('Connecting...');
    this.callState = 'connecting';
    
    const identity = 'user-' + Math.random().toString(36).substr(2, 9);
    
    try {
      const connected = await window.livekitService.connect(`call-${roomCode}`, identity, {
        canPublish: true,
        displayName: this.options.displayName || 'User'
      });
      
      if (connected) {
        this.hideJoinUI();
        
        // Enable camera and mic
        await this.enableLocalMedia();
        
        this.callState = 'connected';
        this.setStatus(`Room: ${roomCode}`, true);
        
        // Start call timer
        this.startTimer();
        
        // Check for existing participants
        const participants = window.livekitService.getParticipants();
        participants.filter(p => !p.isLocal).forEach(p => {
          this.handleParticipantConnected(p);
        });
        
        // Show room code for sharing
        this.showRoomCode(roomCode);
      }
    } catch (error) {
      console.error('Failed to join room:', error);
      this.setStatus('Failed to connect. Please try again.');
      this.callState = 'idle';
    }
  }

  async enableLocalMedia() {
    try {
      // Enable camera
      const videoTrack = await window.livekitService.enableCamera();
      if (videoTrack && this.localVideoEl) {
        window.livekitService.attachTrack(videoTrack, this.localVideoEl);
        this.container.querySelector('.lk-local-placeholder').style.display = 'none';
      }
      
      // Enable microphone
      await window.livekitService.enableMicrophone();
      
    } catch (error) {
      console.error('Failed to enable local media:', error);
    }
  }

  async toggleCamera() {
    const btn = this.container.querySelector('.lk-camera-toggle');
    const isActive = btn.dataset.active === 'true';
    
    try {
      if (isActive) {
        await window.livekitService?.disableCamera();
        this.container.querySelector('.lk-local-placeholder').style.display = 'flex';
      } else {
        const track = await window.livekitService?.enableCamera();
        if (track && this.localVideoEl) {
          window.livekitService.attachTrack(track, this.localVideoEl);
        }
        this.container.querySelector('.lk-local-placeholder').style.display = 'none';
      }
      
      btn.dataset.active = (!isActive).toString();
      btn.querySelector('.icon-on').style.display = isActive ? 'none' : 'block';
      btn.querySelector('.icon-off').style.display = isActive ? 'block' : 'none';
    } catch (error) {
      console.error('Camera toggle error:', error);
    }
  }

  async toggleMic() {
    const btn = this.container.querySelector('.lk-mic-toggle');
    const isActive = btn.dataset.active === 'true';
    
    try {
      if (isActive) {
        await window.livekitService?.disableMicrophone();
      } else {
        await window.livekitService?.enableMicrophone();
      }
      
      btn.dataset.active = (!isActive).toString();
      btn.querySelector('.icon-on').style.display = isActive ? 'none' : 'block';
      btn.querySelector('.icon-off').style.display = isActive ? 'block' : 'none';
    } catch (error) {
      console.error('Mic toggle error:', error);
    }
  }

  async toggleScreenShare() {
    const btn = this.container.querySelector('.lk-screen-toggle');
    const isActive = btn.dataset.active === 'true';
    
    try {
      if (isActive) {
        await window.livekitService?.disableScreenShare();
      } else {
        await window.livekitService?.enableScreenShare();
      }
      
      btn.dataset.active = (!isActive).toString();
      btn.classList.toggle('active', !isActive);
    } catch (error) {
      console.error('Screen share toggle error:', error);
    }
  }

  async endCall() {
    this.stopTimer();
    
    if (window.livekitService?.isConnected) {
      await window.livekitService.disconnect();
    }
    
    // Clear video elements
    if (this.localVideoEl) {
      this.localVideoEl.srcObject = null;
    }
    if (this.remoteVideoEl) {
      this.remoteVideoEl.srcObject = null;
    }
    
    this.container.querySelector('.lk-local-placeholder').style.display = 'flex';
    this.container.querySelector('.lk-remote-placeholder').style.display = 'flex';
    
    this.callState = 'ended';
    this.showJoinUI();
  }

  handleParticipantConnected(participant) {
    console.log('Participant connected:', participant.identity || participant.name);
    this.remoteParticipant = participant;
    
    const nameEl = this.container.querySelector('.lk-remote-name');
    if (nameEl) {
      nameEl.textContent = participant.name || participant.identity;
    }
    
    // Handle existing tracks
    if (participant.trackPublications) {
      participant.trackPublications.forEach(pub => {
        if (pub.track) {
          this.handleTrackSubscribed(pub.track, participant);
        }
      });
    }
  }

  handleParticipantDisconnected(participant) {
    console.log('Participant disconnected:', participant.identity);
    
    if (this.remoteParticipant?.sid === participant.sid) {
      this.remoteParticipant = null;
      this.container.querySelector('.lk-remote-placeholder').style.display = 'flex';
      this.container.querySelector('.lk-remote-name').textContent = '';
    }
  }

  handleTrackSubscribed(track, participant) {
    if (track.kind === 'video' && this.remoteVideoEl) {
      track.attach(this.remoteVideoEl);
      this.container.querySelector('.lk-remote-placeholder').style.display = 'none';
    } else if (track.kind === 'audio') {
      // Audio tracks auto-play
      const audioEl = document.createElement('audio');
      audioEl.autoplay = true;
      track.attach(audioEl);
    }
  }

  handleTrackUnsubscribed(track) {
    track.detach();
    
    if (track.kind === 'video') {
      this.container.querySelector('.lk-remote-placeholder').style.display = 'flex';
    }
  }

  setStatus(text, showTimer = false) {
    const statusText = this.container.querySelector('.status-text');
    const timerEl = this.container.querySelector('.status-timer');
    
    if (statusText) statusText.textContent = text;
    if (timerEl) timerEl.style.display = showTimer ? 'inline' : 'none';
  }

  startTimer() {
    this.callStartTime = Date.now();
    this.timerInterval = setInterval(() => {
      const elapsed = Date.now() - this.callStartTime;
      const minutes = Math.floor(elapsed / 60000);
      const seconds = Math.floor((elapsed % 60000) / 1000);
      
      const timerEl = this.container.querySelector('.status-timer');
      if (timerEl) {
        timerEl.textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
      }
    }, 1000);
  }

  stopTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
  }

  showRoomCode(code) {
    // Could show a modal or toast with the room code for sharing
    console.log('Share this room code:', code);
    
    // Copy to clipboard
    navigator.clipboard?.writeText(code).then(() => {
      console.log('Room code copied to clipboard');
    });
  }

  destroy() {
    this.stopTimer();
    this.container.innerHTML = '';
  }
}

// ============================================
// MULTIVIEW COMPONENT
// ============================================

class MultiviewGrid {
  constructor(containerId, options = {}) {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      console.error(`Container ${containerId} not found`);
      return;
    }
    
    this.options = {
      maxSlots: options.maxSlots || 4,
      layout: options.layout || '2x2',
      ...options
    };
    
    this.slots = [];
    this.activeConnections = new Map();
    
    this.init();
  }

  init() {
    this.render();
    this.setupEventListeners();
  }

  render() {
    let html = '';
    
    for (let i = 0; i < this.options.maxSlots; i++) {
      const slot = this.slots[i];
      
      if (slot && slot.active) {
        html += `
          <div class="lk-multiview-item active" data-slot="${i}">
            <video class="lk-multiview-video" autoplay playsinline></video>
            <div class="lk-multiview-overlay"></div>
            <div class="lk-multiview-info">
              <div class="lk-multiview-streamer">
                <img src="${slot.avatar || 'https://i.pravatar.cc/40'}" alt="${slot.name}" width="30" height="30">
                <span>${slot.name}</span>
              </div>
              <div class="lk-multiview-viewers">
                <span>👁️ ${this.formatNumber(slot.viewers || 0)}</span>
              </div>
            </div>
            <div class="lk-multiview-actions">
              <button class="lk-mv-btn lk-mv-mute" data-slot="${i}" title="Toggle Audio">🔊</button>
              <button class="lk-mv-btn lk-mv-fullscreen" data-slot="${i}" title="Fullscreen">⛶</button>
              <button class="lk-mv-btn lk-mv-close" data-slot="${i}" title="Remove">✕</button>
            </div>
          </div>
        `;
      } else {
        html += `
          <div class="lk-multiview-item empty" data-slot="${i}">
            <div class="lk-multiview-add">
              <div class="lk-multiview-add-icon">+</div>
              <div class="lk-multiview-add-text">Add Stream</div>
            </div>
          </div>
        `;
      }
    }
    
    this.container.innerHTML = html;
    this.container.className = `lk-multiview-container layout-${this.options.layout}`;
  }

  setupEventListeners() {
    this.container.addEventListener('click', async (e) => {
      const target = e.target;
      
      // Add stream
      const emptySlot = target.closest('.lk-multiview-item.empty');
      if (emptySlot) {
        const slotIndex = parseInt(emptySlot.dataset.slot);
        this.showStreamPicker(slotIndex);
        return;
      }
      
      // Close stream
      const closeBtn = target.closest('.lk-mv-close');
      if (closeBtn) {
        const slotIndex = parseInt(closeBtn.dataset.slot);
        await this.removeStream(slotIndex);
        return;
      }
      
      // Toggle mute
      const muteBtn = target.closest('.lk-mv-mute');
      if (muteBtn) {
        const slotIndex = parseInt(muteBtn.dataset.slot);
        this.toggleAudio(slotIndex);
        return;
      }
      
      // Fullscreen
      const fsBtn = target.closest('.lk-mv-fullscreen');
      if (fsBtn) {
        const slotIndex = parseInt(fsBtn.dataset.slot);
        this.toggleFullscreen(slotIndex);
        return;
      }
    });
  }

  /**
   * Add a stream to a slot
   */
  async addStream(slotIndex, streamInfo) {
    if (slotIndex >= this.options.maxSlots) return;
    
    const { roomName, identity, ...info } = streamInfo;
    
    // Create a new LiveKit service instance for this slot
    const service = new LiveKitService();
    await service.init();
    
    const viewerIdentity = `viewer-${Math.random().toString(36).substr(2, 9)}`;
    
    const connected = await service.connect(roomName, viewerIdentity, {
      canPublish: false, // Viewer only
      canSubscribe: true
    });
    
    if (connected) {
      this.slots[slotIndex] = {
        active: true,
        service: service,
        roomName: roomName,
        muted: false,
        ...info
      };
      
      this.activeConnections.set(slotIndex, service);
      
      // Setup track handlers
      service.on('trackSubscribed', ({ track }) => {
        if (track.kind === 'video') {
          const videoEl = this.container.querySelector(
            `.lk-multiview-item[data-slot="${slotIndex}"] video`
          );
          if (videoEl) {
            track.attach(videoEl);
          }
        }
      });
      
      this.render();
      this.setupEventListeners();
    }
  }

  /**
   * Remove a stream from a slot
   */
  async removeStream(slotIndex) {
    const service = this.activeConnections.get(slotIndex);
    
    if (service) {
      await service.disconnect();
      this.activeConnections.delete(slotIndex);
    }
    
    this.slots[slotIndex] = null;
    this.render();
    this.setupEventListeners();
  }

  /**
   * Toggle audio for a slot
   */
  toggleAudio(slotIndex) {
    const slot = this.slots[slotIndex];
    if (!slot) return;
    
    const videoEl = this.container.querySelector(
      `.lk-multiview-item[data-slot="${slotIndex}"] video`
    );
    
    if (videoEl) {
      videoEl.muted = !videoEl.muted;
      slot.muted = videoEl.muted;
      
      const muteBtn = this.container.querySelector(
        `.lk-mv-mute[data-slot="${slotIndex}"]`
      );
      if (muteBtn) {
        muteBtn.textContent = videoEl.muted ? '🔇' : '🔊';
      }
    }
  }

  /**
   * Toggle fullscreen for a slot
   */
  async toggleFullscreen(slotIndex) {
    const item = this.container.querySelector(
      `.lk-multiview-item[data-slot="${slotIndex}"]`
    );
    
    if (!item) return;
    
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await item.requestFullscreen();
      }
    } catch (e) {
      console.error('Fullscreen error:', e);
    }
  }

  /**
   * Set grid layout
   */
  setLayout(layout) {
    this.options.layout = layout;
    this.container.className = `lk-multiview-container layout-${layout}`;
  }

  /**
   * Show stream picker modal
   */
  showStreamPicker(slotIndex) {
    // Create modal
    const modal = document.createElement('div');
    modal.className = 'lk-modal-overlay active';
    modal.innerHTML = `
      <div class="lk-modal">
        <div class="lk-modal-header">
          <h3>Add Stream</h3>
          <button class="lk-modal-close">✕</button>
        </div>
        <div class="lk-modal-body">
          <div class="lk-stream-picker">
            <input type="text" class="lk-stream-search" placeholder="Enter room name or search...">
            <div class="lk-stream-list">
              ${this.renderStreamList()}
            </div>
          </div>
        </div>
      </div>
    `;
    
    document.body.appendChild(modal);
    
    // Event handlers
    modal.querySelector('.lk-modal-close').addEventListener('click', () => {
      modal.remove();
    });
    
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.remove();
      
      const item = e.target.closest('.lk-stream-picker-item');
      if (item) {
        const roomName = item.dataset.room;
        const name = item.dataset.name;
        const avatar = item.dataset.avatar;
        
        this.addStream(slotIndex, { roomName, name, avatar });
        modal.remove();
      }
    });
    
    // Search functionality
    const searchInput = modal.querySelector('.lk-stream-search');
    searchInput.addEventListener('keypress', async (e) => {
      if (e.key === 'Enter') {
        const roomName = searchInput.value.trim();
        if (roomName) {
          await this.addStream(slotIndex, { 
            roomName, 
            name: roomName,
            avatar: `https://i.pravatar.cc/40?u=${roomName}`
          });
          modal.remove();
        }
      }
    });
  }

  /**
   * Render stream list for picker
   */
  renderStreamList() {
    // Use mock data from the app
    const streams = window.Buzzaboo?.LIVE_STREAMS || [];
    const streamers = window.Buzzaboo?.STREAMERS || [];
    
    return streams.slice(0, 10).map(stream => {
      const streamer = streamers.find(s => s.id === stream.streamerId) || {};
      return `
        <div class="lk-stream-picker-item" 
             data-room="stream-${stream.streamerId}"
             data-name="${streamer.displayName || 'Streamer'}"
             data-avatar="${streamer.avatar || ''}">
          <img src="${streamer.avatar || 'https://i.pravatar.cc/40'}" 
               alt="${streamer.displayName}" 
               class="picker-avatar">
          <div class="picker-info">
            <div class="picker-name">${streamer.displayName || 'Streamer'}</div>
            <div class="picker-meta">${stream.game} • ${this.formatNumber(stream.viewers)} viewers</div>
          </div>
        </div>
      `;
    }).join('');
  }

  formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }

  /**
   * Disconnect all streams
   */
  async disconnectAll() {
    for (const [slotIndex, service] of this.activeConnections) {
      await service.disconnect();
    }
    this.activeConnections.clear();
    this.slots = [];
    this.render();
  }

  destroy() {
    this.disconnectAll();
    this.container.innerHTML = '';
  }
}

// Export components
window.VideoCall = VideoCall;
window.MultiviewGrid = MultiviewGrid;
