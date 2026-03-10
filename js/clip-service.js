/**
 * Buzzaboo Clip Service
 * Auto-clipping service that detects highlight moments during video chats
 * and captures short clips for community browsing.
 *
 * Privacy-aware: only records when BOTH users are NOT in private mode.
 * Uses rolling buffer recording, Web Audio API for highlight detection,
 * and IndexedDB + Firestore for clip storage.
 */

const CLIP_CONFIG = {
  rollingBufferSeconds: 30,
  clipMinSeconds: 15,
  clipMaxSeconds: 30,
  highlightCheckIntervalMs: 5000,
  audioEnergyThreshold: 0.35,
  rapidChatCount: 5,
  rapidChatWindowMs: 10000,
  longConversationMs: 5 * 60 * 1000,
  canvasWidth: 640,
  canvasHeight: 240,
  canvasFps: 15,
  thumbnailWidth: 320,
  thumbnailHeight: 120,
  indexedDBName: 'buzzaboo-clips',
  indexedDBVersion: 1,
  indexedDBStore: 'clips',
  firestoreCollection: 'clips',
  mediaRecorderMimeType: 'video/webm;codecs=vp8',
  mediaRecorderBitrate: 1000000
};

class ClipService {
  constructor() {
    this.eventHandlers = new Map();
    this.isPrivate = false;

    // Recording state
    this.mediaRecorder = null;
    this.offscreenCanvas = null;
    this.canvasCtx = null;
    this.canvasStream = null;
    this.localVideo = null;
    this.remoteVideo = null;
    this.filterEngine = null;
    this.drawFrameId = null;
    this.rollingBuffer = [];
    this.bufferStartTime = null;
    this.isRecording = false;

    // Audio analysis state
    this.audioContext = null;
    this.analyserNode = null;
    this.audioDataArray = null;

    // Highlight detection state
    this.highlightCheckInterval = null;
    this.chatTimestamps = [];
    this.connectionStartTime = null;
    this.longConversationCaptured = false;

    // Firestore / Auth references
    this.db = null;
    this.userId = null;
  }

  // ============================================
  // PRIVACY
  // ============================================

  setPrivate(isPrivate) {
    this.isPrivate = isPrivate;
    if (isPrivate && this.isRecording) {
      this.pauseRecording();
    } else if (!isPrivate && this.localVideo && this.remoteVideo && !this.isRecording) {
      this.resumeRecording();
    }
  }

  // ============================================
  // RECORDING - Rolling Buffer
  // ============================================

  setFilterEngine(engine) {
    this.filterEngine = engine;
  }

  startRecording(localVideo, remoteVideo) {
    if (this.isRecording) return;
    if (this.isPrivate) return;

    this.localVideo = localVideo;
    this.remoteVideo = remoteVideo;
    this.connectionStartTime = Date.now();
    this.longConversationCaptured = false;
    this.chatTimestamps = [];

    this.initFirestore();
    this.setupCanvas();
    this.startMediaRecorder();
    this.startHighlightDetection();

    this.isRecording = true;
    this.emit('recordingStarted');
  }

  stopRecording() {
    this.stopHighlightDetection();
    this.stopMediaRecorder();
    this.stopCanvasDrawing();

    this.localVideo = null;
    this.remoteVideo = null;
    this.rollingBuffer = [];
    this.bufferStartTime = null;
    this.isRecording = false;
    this.connectionStartTime = null;
    this.longConversationCaptured = false;
    this.chatTimestamps = [];

    this.emit('recordingStopped');
  }

  /** @private */
  pauseRecording() {
    this.stopMediaRecorder();
    this.stopCanvasDrawing();
    this.stopHighlightDetection();
    this.rollingBuffer = [];
    this.bufferStartTime = null;
    this.isRecording = false;
    this.emit('recordingStopped');
  }

  /** @private */
  resumeRecording() {
    if (!this.localVideo || !this.remoteVideo) return;
    this.setupCanvas();
    this.startMediaRecorder();
    this.startHighlightDetection();
    this.isRecording = true;
    this.emit('recordingStarted');
  }

  /** @private */
  initFirestore() {
    if (typeof firebase !== 'undefined' && firebase.apps.length) {
      this.db = firebase.firestore();
      const user = firebase.auth().currentUser;
      this.userId = user ? user.uid : this.getAnonymousId();
    } else {
      this.userId = this.getAnonymousId();
    }
  }

  /** @private */
  getAnonymousId() {
    let id = localStorage.getItem('buzzaboo-anon-id');
    if (!id) {
      id = 'anon-' + crypto.randomUUID();
      localStorage.setItem('buzzaboo-anon-id', id);
    }
    return id;
  }

  /** @private */
  setupCanvas() {
    this.offscreenCanvas = document.createElement('canvas');
    this.offscreenCanvas.width = CLIP_CONFIG.canvasWidth;
    this.offscreenCanvas.height = CLIP_CONFIG.canvasHeight;
    this.canvasCtx = this.offscreenCanvas.getContext('2d');

    this.drawFrame();
  }

  /** @private */
  drawFrame() {
    if (!this.canvasCtx || !this.localVideo || !this.remoteVideo) return;

    const ctx = this.canvasCtx;
    const halfWidth = CLIP_CONFIG.canvasWidth / 2;
    const height = CLIP_CONFIG.canvasHeight;

    // Clear canvas
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, CLIP_CONFIG.canvasWidth, height);

    // Draw local video on the left (use filter engine canvas if available for filtered output)
    if (this.filterEngine && this.filterEngine.getCanvas()) {
      ctx.drawImage(this.filterEngine.getCanvas(), 0, 0, halfWidth, height);
    } else if (this.localVideo.readyState >= 2) {
      ctx.drawImage(this.localVideo, 0, 0, halfWidth, height);
    }

    // Draw remote video on the right
    if (this.remoteVideo.readyState >= 2) {
      ctx.drawImage(this.remoteVideo, halfWidth, 0, halfWidth, height);
    }

    this.drawFrameId = requestAnimationFrame(() => this.drawFrame());
  }

  /** @private */
  stopCanvasDrawing() {
    if (this.drawFrameId) {
      cancelAnimationFrame(this.drawFrameId);
      this.drawFrameId = null;
    }
  }

  /** @private */
  startMediaRecorder() {
    if (!this.offscreenCanvas) return;

    this.canvasStream = this.offscreenCanvas.captureStream(CLIP_CONFIG.canvasFps);

    const mimeType = MediaRecorder.isTypeSupported(CLIP_CONFIG.mediaRecorderMimeType)
      ? CLIP_CONFIG.mediaRecorderMimeType
      : 'video/webm';

    this.mediaRecorder = new MediaRecorder(this.canvasStream, {
      mimeType,
      videoBitsPerSecond: CLIP_CONFIG.mediaRecorderBitrate
    });

    this.rollingBuffer = [];
    this.bufferStartTime = Date.now();

    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data && event.data.size > 0) {
        this.rollingBuffer.push({
          blob: event.data,
          timestamp: Date.now()
        });
        this.trimBuffer();
      }
    };

    this.mediaRecorder.onerror = (event) => {
      console.error('MediaRecorder error:', event.error);
    };

    // Request data every second to maintain granular buffer
    this.mediaRecorder.start(1000);
  }

  /** @private */
  stopMediaRecorder() {
    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop();
    }
    this.mediaRecorder = null;
    if (this.canvasStream) {
      this.canvasStream.getTracks().forEach(track => track.stop());
      this.canvasStream = null;
    }
  }

  /** @private - Remove chunks older than the rolling buffer window */
  trimBuffer() {
    const cutoff = Date.now() - (CLIP_CONFIG.rollingBufferSeconds * 1000);
    while (this.rollingBuffer.length > 0 && this.rollingBuffer[0].timestamp < cutoff) {
      this.rollingBuffer.shift();
    }
  }

  // ============================================
  // AUDIO ANALYSIS
  // ============================================

  initAudioAnalyser(stream) {
    try {
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const source = this.audioContext.createMediaStreamSource(stream);
      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 256;
      this.analyserNode.smoothingTimeConstant = 0.3;
      source.connect(this.analyserNode);

      this.audioDataArray = new Uint8Array(this.analyserNode.frequencyBinCount);
    } catch (error) {
      console.error('Failed to initialize audio analyser:', error);
    }
  }

  /** @private - Returns normalized audio energy level (0-1) */
  getAudioEnergy() {
    if (!this.analyserNode || !this.audioDataArray) return 0;

    this.analyserNode.getByteFrequencyData(this.audioDataArray);

    let sum = 0;
    for (let i = 0; i < this.audioDataArray.length; i++) {
      sum += this.audioDataArray[i];
    }
    return sum / (this.audioDataArray.length * 255);
  }

  // ============================================
  // HIGHLIGHT DETECTION
  // ============================================

  /** @private */
  startHighlightDetection() {
    this.stopHighlightDetection();
    this.highlightCheckInterval = setInterval(
      () => this.checkForHighlight(),
      CLIP_CONFIG.highlightCheckIntervalMs
    );
  }

  /** @private */
  stopHighlightDetection() {
    if (this.highlightCheckInterval) {
      clearInterval(this.highlightCheckInterval);
      this.highlightCheckInterval = null;
    }
  }

  /**
   * Called periodically to detect highlight moments.
   * Triggers clip capture when a highlight is detected.
   */
  checkForHighlight() {
    if (!this.isRecording || this.isPrivate) return;
    if (this.rollingBuffer.length < CLIP_CONFIG.clipMinSeconds) return;

    let reason = null;

    // Check 1: Audio energy spike (loud reaction / laughter)
    const energy = this.getAudioEnergy();
    if (energy > CLIP_CONFIG.audioEnergyThreshold) {
      reason = 'audio_spike';
    }

    // Check 2: Rapid text chat (>5 messages in 10 seconds)
    if (!reason) {
      const now = Date.now();
      const windowStart = now - CLIP_CONFIG.rapidChatWindowMs;
      const recentMessages = this.chatTimestamps.filter(ts => ts >= windowStart);
      if (recentMessages.length >= CLIP_CONFIG.rapidChatCount) {
        reason = 'rapid_chat';
      }
    }

    // Check 3: Long conversation (>5 minutes connected) - capture once
    if (!reason && !this.longConversationCaptured && this.connectionStartTime) {
      const elapsed = Date.now() - this.connectionStartTime;
      if (elapsed >= CLIP_CONFIG.longConversationMs) {
        reason = 'long_conversation';
        this.longConversationCaptured = true;
      }
    }

    if (reason) {
      this.emit('highlightDetected', { reason });
      this.captureClip(reason);
    }
  }

  /**
   * Track incoming chat messages for rapid-chat highlight detection.
   * Call this whenever a chat message is sent or received.
   */
  onChatMessage() {
    this.chatTimestamps.push(Date.now());

    // Prune old timestamps beyond the detection window
    const cutoff = Date.now() - CLIP_CONFIG.rapidChatWindowMs;
    this.chatTimestamps = this.chatTimestamps.filter(ts => ts >= cutoff);
  }

  // ============================================
  // CLIP CAPTURE
  // ============================================

  async captureClip(reason) {
    if (this.rollingBuffer.length === 0) return null;

    try {
      // Determine how many seconds of buffer to capture (15-30s)
      const bufferDurationMs = this.rollingBuffer.length > 0
        ? Date.now() - this.rollingBuffer[0].timestamp
        : 0;
      const clipDurationMs = Math.min(
        bufferDurationMs,
        CLIP_CONFIG.clipMaxSeconds * 1000
      );
      const clipDurationSec = Math.round(clipDurationMs / 1000);

      // Take chunks from the buffer that fit within the clip window
      const clipCutoff = Date.now() - clipDurationMs;
      const clipChunks = this.rollingBuffer
        .filter(chunk => chunk.timestamp >= clipCutoff)
        .map(chunk => chunk.blob);

      if (clipChunks.length === 0) return null;

      // Create video blob from chunks
      const mimeType = this.mediaRecorder?.mimeType || 'video/webm';
      const videoBlob = new Blob(clipChunks, { type: mimeType });

      // Generate thumbnail from current canvas state
      const thumbnailDataUrl = this.generateThumbnail();

      // Create clip metadata
      const clipId = `clip-${Date.now()}`;
      const metadata = {
        id: clipId,
        userId: this.userId,
        duration: clipDurationSec,
        thumbnailDataUrl,
        createdAt: new Date().toISOString(),
        hearts: 0,
        reason: reason || 'manual',
        agePool: this.getAgePool()
      };

      // Store video blob in IndexedDB
      await this.saveToIndexedDB(clipId, videoBlob);

      // Store metadata in Firestore
      if (this.db) {
        await this.db
          .collection(CLIP_CONFIG.firestoreCollection)
          .doc(clipId)
          .set({
            ...metadata,
            createdAt: firebase.firestore.FieldValue.serverTimestamp()
          });
      }

      this.emit('clipCaptured', {
        clipId,
        duration: clipDurationSec,
        thumbnail: thumbnailDataUrl
      });

      return metadata;
    } catch (error) {
      console.error('Failed to capture clip:', error);
      return null;
    }
  }

  /** @private */
  generateThumbnail() {
    if (!this.offscreenCanvas) return null;

    const thumbCanvas = document.createElement('canvas');
    thumbCanvas.width = CLIP_CONFIG.thumbnailWidth;
    thumbCanvas.height = CLIP_CONFIG.thumbnailHeight;
    const thumbCtx = thumbCanvas.getContext('2d');
    thumbCtx.drawImage(
      this.offscreenCanvas,
      0, 0,
      CLIP_CONFIG.thumbnailWidth,
      CLIP_CONFIG.thumbnailHeight
    );
    return thumbCanvas.toDataURL('image/jpeg', 0.7);
  }

  /** @private */
  getAgePool() {
    if (!this.connectionStartTime) return 'unknown';
    const elapsed = Date.now() - this.connectionStartTime;
    if (elapsed < 60000) return 'first_minute';
    if (elapsed < 300000) return 'early';
    return 'established';
  }

  // ============================================
  // CLIP RETRIEVAL
  // ============================================

  /**
   * Fetch clip metadata from Firestore with pagination.
   * @param {Object} options
   * @param {number} [options.limit=20] - Number of clips to fetch
   * @param {*} [options.startAfter] - Firestore document snapshot to paginate after
   * @param {string} [options.userId] - Filter by userId
   * @returns {Promise<{clips: Array, lastDoc: *}>}
   */
  async getClips(options = {}) {
    if (!this.db) {
      console.warn('Firestore not available. Cannot fetch clips.');
      return { clips: [], lastDoc: null };
    }

    try {
      const limit = options.limit || 20;
      let query = this.db
        .collection(CLIP_CONFIG.firestoreCollection)
        .orderBy('createdAt', 'desc');

      if (options.userId) {
        query = query.where('userId', '==', options.userId);
      }

      if (options.startAfter) {
        query = query.startAfter(options.startAfter);
      }

      query = query.limit(limit);

      const snapshot = await query.get();
      const clips = [];
      let lastDoc = null;

      snapshot.forEach(doc => {
        clips.push({ id: doc.id, ...doc.data() });
        lastDoc = doc;
      });

      return { clips, lastDoc };
    } catch (error) {
      console.error('Failed to fetch clips:', error);
      return { clips: [], lastDoc: null };
    }
  }

  /**
   * Retrieve a video blob from IndexedDB by clip ID.
   * @param {string} clipId
   * @returns {Promise<Blob|null>}
   */
  async getClipBlob(clipId) {
    return this.getFromIndexedDB(clipId);
  }

  /**
   * Increment the hearts counter on a clip in Firestore.
   * @param {string} clipId
   * @returns {Promise<boolean>}
   */
  async heartClip(clipId) {
    if (!this.db) {
      console.warn('Firestore not available. Cannot heart clip.');
      return false;
    }

    try {
      await this.db
        .collection(CLIP_CONFIG.firestoreCollection)
        .doc(clipId)
        .update({
          hearts: firebase.firestore.FieldValue.increment(1)
        });
      return true;
    } catch (error) {
      console.error('Failed to heart clip:', error);
      return false;
    }
  }

  // ============================================
  // IndexedDB Helpers
  // ============================================

  /** @private */
  openDB() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(
        CLIP_CONFIG.indexedDBName,
        CLIP_CONFIG.indexedDBVersion
      );

      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(CLIP_CONFIG.indexedDBStore)) {
          db.createObjectStore(CLIP_CONFIG.indexedDBStore);
        }
      };

      request.onsuccess = (event) => {
        resolve(event.target.result);
      };

      request.onerror = (event) => {
        console.error('IndexedDB open error:', event.target.error);
        reject(event.target.error);
      };
    });
  }

  /** @private */
  async saveToIndexedDB(key, blob) {
    const db = await this.openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(CLIP_CONFIG.indexedDBStore, 'readwrite');
      const store = tx.objectStore(CLIP_CONFIG.indexedDBStore);
      const request = store.put(blob, key);

      request.onsuccess = () => resolve();
      request.onerror = (event) => {
        console.error('IndexedDB save error:', event.target.error);
        reject(event.target.error);
      };

      tx.oncomplete = () => db.close();
    });
  }

  /** @private */
  async getFromIndexedDB(key) {
    const db = await this.openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(CLIP_CONFIG.indexedDBStore, 'readonly');
      const store = tx.objectStore(CLIP_CONFIG.indexedDBStore);
      const request = store.get(key);

      request.onsuccess = (event) => resolve(event.target.result || null);
      request.onerror = (event) => {
        console.error('IndexedDB get error:', event.target.error);
        reject(event.target.error);
      };

      tx.oncomplete = () => db.close();
    });
  }

  // ============================================
  // CLEANUP
  // ============================================

  destroy() {
    this.stopRecording();

    if (this.audioContext) {
      this.audioContext.close().catch(() => {});
      this.audioContext = null;
      this.analyserNode = null;
      this.audioDataArray = null;
    }

    this.offscreenCanvas = null;
    this.canvasCtx = null;
    this.db = null;
    this.userId = null;
    this.eventHandlers.clear();
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
}

const clipService = new ClipService();
window.clipService = clipService;
window.ClipService = ClipService;
