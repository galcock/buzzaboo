/* ============================================
   BUZZABOO - Face Detection Service
   MediaPipe Face Mesh integration for real-time
   face landmark detection (468 + 10 iris points).
   Loaded lazily — only when face filters are active.
   ============================================ */

class FaceDetectionService {
  constructor() {
    this.faceMesh = null;
    this.ready = false;
    this.loading = false;
    this.latestResults = null;
    this.onResultsCallback = null;
    this.videoElement = null;
    this.rafId = null;
    this.running = false;
    this.lastDetectTime = 0;
    this.detectInterval = 33; // ~30fps
  }

  async init() {
    if (this.ready || this.loading) return;
    this.loading = true;

    try {
      // Load MediaPipe scripts dynamically
      await this.loadScript('https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh@0.4.1633559619/face_mesh.js');

      this.faceMesh = new window.FaceMesh({
        locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh@0.4.1633559619/${file}`
      });

      this.faceMesh.setOptions({
        maxNumFaces: 1,
        refineLandmarks: true, // Enables iris landmarks (468-477)
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5
      });

      this.faceMesh.onResults((results) => {
        if (results.multiFaceLandmarks && results.multiFaceLandmarks.length > 0) {
          this.latestResults = results.multiFaceLandmarks[0];
        } else {
          this.latestResults = null;
        }
        if (this.onResultsCallback) {
          this.onResultsCallback(this.latestResults);
        }
      });

      // Warm up the model
      const warmupCanvas = document.createElement('canvas');
      warmupCanvas.width = 64;
      warmupCanvas.height = 64;
      const warmupCtx = warmupCanvas.getContext('2d');
      warmupCtx.fillStyle = '#000';
      warmupCtx.fillRect(0, 0, 64, 64);
      await this.faceMesh.send({ image: warmupCanvas });

      this.ready = true;
      this.loading = false;
      console.log('✓ MediaPipe Face Mesh loaded');
    } catch (err) {
      this.loading = false;
      console.error('Failed to load Face Mesh:', err);
    }
  }

  loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) {
        resolve();
        return;
      }
      const script = document.createElement('script');
      script.src = src;
      script.crossOrigin = 'anonymous';
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  isReady() {
    return this.ready;
  }

  isLoading() {
    return this.loading;
  }

  async detectFace(videoElement) {
    if (!this.ready || !this.faceMesh) return null;
    if (!videoElement || videoElement.readyState < 2) return null;

    try {
      await this.faceMesh.send({ image: videoElement });
      return this.latestResults;
    } catch (err) {
      return null;
    }
  }

  startContinuousDetection(videoElement) {
    this.videoElement = videoElement;
    this.running = true;
    this.detectLoop();
  }

  stopContinuousDetection() {
    this.running = false;
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
    this.videoElement = null;
  }

  detectLoop() {
    if (!this.running) return;

    const now = performance.now();
    if (now - this.lastDetectTime >= this.detectInterval) {
      this.lastDetectTime = now;
      if (this.videoElement && this.videoElement.readyState >= 2 && this.ready) {
        this.faceMesh.send({ image: this.videoElement }).catch(() => {});
      }
    }

    this.rafId = requestAnimationFrame(() => this.detectLoop());
  }

  onResults(callback) {
    this.onResultsCallback = callback;
  }

  getLatestLandmarks() {
    return this.latestResults;
  }

  getFaceBoundingBox(landmarks) {
    if (!landmarks) return null;

    let minX = 1, maxX = 0, minY = 1, maxY = 0;
    landmarks.forEach(pt => {
      minX = Math.min(minX, pt.x);
      maxX = Math.max(maxX, pt.x);
      minY = Math.min(minY, pt.y);
      maxY = Math.max(maxY, pt.y);
    });

    return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
  }

  getEyePositions(landmarks) {
    if (!landmarks) return null;

    const leftIndices = [33, 133, 160, 159, 158, 144, 145, 153];
    const rightIndices = [362, 263, 387, 386, 385, 373, 374, 380];

    const avg = (indices) => {
      let sx = 0, sy = 0, c = 0;
      indices.forEach(i => {
        if (landmarks[i]) { sx += landmarks[i].x; sy += landmarks[i].y; c++; }
      });
      return c > 0 ? { x: sx / c, y: sy / c } : null;
    };

    return { left: avg(leftIndices), right: avg(rightIndices) };
  }

  getForeheadPosition(landmarks) {
    if (!landmarks) return null;
    const indices = [10, 151, 9, 8];
    let sx = 0, sy = 0, c = 0;
    indices.forEach(i => {
      if (landmarks[i]) { sx += landmarks[i].x; sy += landmarks[i].y; c++; }
    });
    return c > 0 ? { x: sx / c, y: sy / c } : null;
  }

  getFaceOutline(landmarks) {
    if (!landmarks) return [];
    const indices = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109];

    return indices.filter(i => landmarks[i]).map(i => landmarks[i]);
  }

  destroy() {
    this.stopContinuousDetection();
    if (this.faceMesh) {
      this.faceMesh.close();
      this.faceMesh = null;
    }
    this.ready = false;
    this.latestResults = null;
    console.log('Face detection destroyed');
  }
}

// Export
window.FaceDetectionService = FaceDetectionService;
console.log('✓ Face detection service loaded');
