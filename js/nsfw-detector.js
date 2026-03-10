/**
 * Buzzaboo NSFW Detection Service
 * Client-side content moderation using TensorFlow.js + NSFWJS
 *
 * Detects male genitalia exposure in video chat to protect minors from predators.
 * Scans both local and remote video feeds at regular intervals.
 */

const NSFW_CONFIG = {
  tfjsUrl: 'https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.17.0/dist/tf.min.js',
  nsfwjsUrl: 'https://cdn.jsdelivr.net/npm/nsfwjs@2.4.2/dist/nsfwjs.min.js',
  scanIntervalMs: 2500,
  canvasSize: 224,
  violationThreshold: 0.70,
  targetClass: 'Porn',
  storagePrefix: 'buzzaboo-violations-',
  suspensionDurations: [
    30 * 60 * 1000,       // 1st offense: 30 minutes
    2 * 60 * 60 * 1000,   // 2nd offense: 2 hours
    24 * 60 * 60 * 1000,  // 3rd offense: 24 hours
    Infinity              // 4th+: permanent
  ]
};

class NSFWDetector {
  constructor() {
    this.model = null;
    this.modelLoading = false;
    this.canvas = null;
    this.ctx = null;
    this.scanInterval = null;
    this.localVideo = null;
    this.remoteVideo = null;
    this.eventHandlers = new Map();
  }

  // ---------------------------------------------------------------------------
  // Script loader
  // ---------------------------------------------------------------------------

  loadScript(src) {
    return new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${src}"]`);
      if (existing) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
      document.head.appendChild(script);
    });
  }

  // ---------------------------------------------------------------------------
  // Model loading
  // ---------------------------------------------------------------------------

  async loadModel() {
    if (this.model) return this.model;
    if (this.modelLoading) {
      // Wait for the in-flight load to finish
      return new Promise((resolve, reject) => {
        this.on('modelLoaded', () => resolve(this.model));
        this.on('modelError', (err) => reject(err));
      });
    }

    this.modelLoading = true;

    try {
      // Load TensorFlow.js first, then NSFWJS which depends on it
      if (typeof tf === 'undefined') {
        await this.loadScript(NSFW_CONFIG.tfjsUrl);
      }
      if (typeof nsfwjs === 'undefined') {
        await this.loadScript(NSFW_CONFIG.nsfwjsUrl);
      }

      // Load default MobileNet v2 quantized model
      this.model = await nsfwjs.load();

      // Create offscreen canvas for frame capture
      this.canvas = document.createElement('canvas');
      this.canvas.width = NSFW_CONFIG.canvasSize;
      this.canvas.height = NSFW_CONFIG.canvasSize;
      this.ctx = this.canvas.getContext('2d');

      this.modelLoading = false;
      console.log('NSFW detection model loaded');
      this.emit('modelLoaded');
      return this.model;
    } catch (error) {
      this.modelLoading = false;
      console.error('Failed to load NSFW model:', error);
      this.emit('modelError', error);
      throw error;
    }
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  async startScanning(localVideo, remoteVideo) {
    if (this.scanInterval) {
      this.stopScanning();
    }

    this.localVideo = localVideo;
    this.remoteVideo = remoteVideo;

    await this.loadModel();

    this.scanInterval = setInterval(() => this._scanBothFeeds(), NSFW_CONFIG.scanIntervalMs);
    console.log('NSFW scanning started');
    this.emit('scanningStarted');
  }

  stopScanning() {
    if (this.scanInterval) {
      clearInterval(this.scanInterval);
      this.scanInterval = null;
    }
    this.localVideo = null;
    this.remoteVideo = null;
    console.log('NSFW scanning stopped');
    this.emit('scanningStopped');
  }

  async _scanBothFeeds() {
    const scans = [];

    if (this.localVideo && this._isVideoReady(this.localVideo)) {
      scans.push(
        this.analyzeFrame(this.localVideo).then((result) => {
          if (result.isViolation) {
            this.emit('violation', {
              source: 'local',
              confidence: result.confidence,
              predictions: result.predictions
            });
          }
        })
      );
    }

    if (this.remoteVideo && this._isVideoReady(this.remoteVideo)) {
      scans.push(
        this.analyzeFrame(this.remoteVideo).then((result) => {
          if (result.isViolation) {
            this.emit('violation', {
              source: 'remote',
              confidence: result.confidence,
              predictions: result.predictions
            });
          }
        })
      );
    }

    try {
      await Promise.all(scans);
    } catch (error) {
      console.error('NSFW scan error:', error);
    }
  }

  _isVideoReady(videoElement) {
    return (
      videoElement &&
      videoElement.readyState >= 2 &&
      videoElement.videoWidth > 0 &&
      videoElement.videoHeight > 0
    );
  }

  // ---------------------------------------------------------------------------
  // Frame analysis
  // ---------------------------------------------------------------------------

  async analyzeFrame(videoElement) {
    if (!this.model || !this.ctx) {
      return { isViolation: false, confidence: 0, predictions: [] };
    }

    // Draw the current video frame to the offscreen canvas at 224x224
    this.ctx.drawImage(
      videoElement,
      0, 0,
      NSFW_CONFIG.canvasSize,
      NSFW_CONFIG.canvasSize
    );

    const predictions = await this.model.classify(this.canvas);

    const pornPrediction = predictions.find(
      (p) => p.className === NSFW_CONFIG.targetClass
    );
    const confidence = pornPrediction ? pornPrediction.probability : 0;
    const isViolation = confidence > NSFW_CONFIG.violationThreshold;

    return { isViolation, confidence, predictions };
  }

  // ---------------------------------------------------------------------------
  // Violation recording
  // ---------------------------------------------------------------------------

  async recordViolation(userId, isAuthenticated, db) {
    const data = this.getOffenseData(userId);
    const now = Date.now();

    data.offenseCount += 1;
    data.lastOffenseAt = now;

    // Calculate suspension duration based on offense count
    const durationIndex = Math.min(
      data.offenseCount - 1,
      NSFW_CONFIG.suspensionDurations.length - 1
    );
    const duration = NSFW_CONFIG.suspensionDurations[durationIndex];

    data.suspendedUntil = duration === Infinity ? Infinity : now + duration;
    data.isPermanent = duration === Infinity;

    // Always persist to localStorage
    const storageKey = NSFW_CONFIG.storagePrefix + userId;
    localStorage.setItem(storageKey, JSON.stringify(data));

    // Persist to Firestore if authenticated
    if (isAuthenticated && db) {
      try {
        await db.collection('violations').doc(userId).set(
          {
            offenseCount: data.offenseCount,
            lastOffenseAt: new Date(data.lastOffenseAt),
            suspendedUntil: data.isPermanent ? 'permanent' : new Date(data.suspendedUntil),
            isPermanent: data.isPermanent,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp()
          },
          { merge: true }
        );
      } catch (error) {
        console.error('Failed to write violation to Firestore:', error);
      }
    }

    return data;
  }

  // ---------------------------------------------------------------------------
  // Suspension checks
  // ---------------------------------------------------------------------------

  checkSuspension(userId) {
    const data = this.getOffenseData(userId);
    const now = Date.now();

    if (data.offenseCount === 0 || data.suspendedUntil === null) {
      return {
        isSuspended: false,
        isPermanent: false,
        expiresAt: null,
        remainingMs: 0,
        offenseCount: data.offenseCount
      };
    }

    if (data.isPermanent) {
      return {
        isSuspended: true,
        isPermanent: true,
        expiresAt: null,
        remainingMs: Infinity,
        offenseCount: data.offenseCount
      };
    }

    const remainingMs = Math.max(0, data.suspendedUntil - now);
    const isSuspended = remainingMs > 0;

    return {
      isSuspended,
      isPermanent: false,
      expiresAt: isSuspended ? data.suspendedUntil : null,
      remainingMs,
      offenseCount: data.offenseCount
    };
  }

  // ---------------------------------------------------------------------------
  // Offense data access
  // ---------------------------------------------------------------------------

  getOffenseData(userId) {
    const storageKey = NSFW_CONFIG.storagePrefix + userId;
    const stored = localStorage.getItem(storageKey);

    if (stored) {
      try {
        return JSON.parse(stored);
      } catch (_) {
        // Corrupt data; reset
      }
    }

    return {
      offenseCount: 0,
      lastOffenseAt: null,
      suspendedUntil: null,
      isPermanent: false
    };
  }

  // ---------------------------------------------------------------------------
  // Event system
  // ---------------------------------------------------------------------------

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
      handlers.forEach((handler) => {
        try {
          handler(data);
        } catch (error) {
          console.error(`Error in event handler for ${event}:`, error);
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  destroy() {
    this.stopScanning();
    this.model = null;
    this.canvas = null;
    this.ctx = null;
    this.eventHandlers.clear();
  }
}

const nsfwDetector = new NSFWDetector();
window.nsfwDetector = nsfwDetector;
